import Foundation
import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

/// 대기열과 다운로드 진행을 맡는다. 화면은 이 객체의 jobs 만 본다.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var jobs: [DownloadJob]
    @Published var toast: String?
    /// 서버 비밀번호가 필요할 때 true. 화면이 입력창을 띄운다.
    @Published var needsPassword = false
    private var passwordWaiters: [CheckedContinuation<Bool, Never>] = []

    let settings: AppSettings
    private var tasks: [String: Task<Void, Never>] = [:]
    private static let file = "jobs.json"
    private var bgTask: Int = 0   // UIBackgroundTaskIdentifier.rawValue

    init(settings: AppSettings) {
        self.settings = settings
        var loaded = Disk.load(Self.file, as: [DownloadJob].self) ?? []
        // 앱이 꺼질 때 진행 중이던 작업은 처음부터 다시 받는다.
        for i in loaded.indices where loaded[i].state.isActive {
            loaded[i].state = .queued; loaded[i].progress = 0; loaded[i].speedBytesPerSec = 0
        }
        jobs = loaded
        pump()
    }

    var activeCount: Int { jobs.filter { $0.state.isActive }.count }

    // MARK: 조작

    func enqueue(url: String, format: DownloadFormat, title: String? = nil, thumbnail: String? = nil, uploader: String? = nil) {
        let job = DownloadJob(id: UUID().uuidString, url: url, format: format, title: title ?? url,
                              thumbnail: thumbnail, uploader: uploader)
        jobs.insert(job, at: 0)
        persist(); pump()
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        if let j = job(id), j.state == .queued { update(id) { $0.state = .canceled; $0.finishedAt = Date() } }
    }

    func cancelAll() { jobs.filter { $0.state.isActive }.forEach { cancel($0.id) } }

    func retry(_ id: String) {
        update(id) { $0.state = .queued; $0.progress = 0; $0.error = nil; $0.finishedAt = nil }
        pump()
    }

    func remove(_ id: String, deleteFile: Bool = false) {
        tasks[id]?.cancel()
        if deleteFile, let f = job(id)?.outputFile { try? FileManager.default.removeItem(at: Disk.documents.appendingPathComponent(f)) }
        jobs.removeAll { $0.id == id }
        persist()
    }

    func clearFinished() { jobs.removeAll { !$0.state.isActive }; persist() }

    func fileURL(_ job: DownloadJob) -> URL? {
        guard let f = job.outputFile else { return nil }
        let u = Disk.documents.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    // MARK: 내부

    private func job(_ id: String) -> DownloadJob? { jobs.first { $0.id == id } }

    private func update(_ id: String, _ f: (inout DownloadJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        f(&jobs[i]); persist(); refreshIdleTimer()
    }

    private var persistWork: DispatchWorkItem?
    private func persist() {
        persistWork?.cancel()
        let snapshot = jobs
        let w = DispatchWorkItem { Disk.save(snapshot, Self.file) }
        persistWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }

    private func refreshIdleTimer() {
        #if canImport(UIKit) && !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = jobs.contains { $0.state.isRunning }
        #endif
    }

    private func pump() {
        let running = jobs.filter { $0.state.isRunning }.count
        var slots = settings.concurrent - running
        // 오래된 것부터
        for j in jobs.reversed() where j.state == .queued && slots > 0 && tasks[j.id] == nil {
            slots -= 1
            update(j.id) { $0.state = .fetching }
            let id = j.id
            tasks[id] = Task { [weak self] in
                await self?.run(id)
                await MainActor.run { self?.tasks[id] = nil; self?.pump() }
            }
        }
    }

    private func run(_ id: String) async {
        guard let start = job(id) else { return }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("yank-\(id)")
        beginBackground()
        defer { try? FileManager.default.removeItem(at: work); endBackground() }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // 1) 정보 + 2) 직접 받기. 막히면(403 등) 설정한 파이 서버에 맡긴다.
            guard case .video(let vid) = InputParser.classify(start.url) else { throw YankError.invalidURL }
            var info: VideoInfo?
            var out = work.appendingPathComponent("out.mp4")
            var ext = start.format.isAudio ? "m4a" : "mp4"
            var titleFromServer: String?
            do {
                let i = try await YouTube.player(id: vid)
                info = i
                let plan = try FormatPicker.plan(info: i, format: start.format)
                update(id) {
                    $0.title = i.title; $0.thumbnail = i.thumbnail; $0.uploader = i.author
                    $0.durationSeconds = i.durationSeconds; $0.totalBytes = plan.estimatedBytes; $0.state = .downloading
                }
                ext = plan.ext
                out = work.appendingPathComponent("out." + ext)
                try await direct(id: id, plan: plan, work: work, out: out)
            } catch let e where Self.shouldFallBack(e) {
                guard settings.serverEnabled else { throw YankError.notPlayable(L("error_blocked_no_server")) }
                update(id) { $0.viaServer = true; $0.state = .serverPreparing; $0.progress = 0 }
                var result: (String, String?)?
                for attempt in 0..<2 {
                    let server = try await obtainServer()
                    do {
                        result = try await viaServer(id: id, videoId: vid, server: server, work: work, into: &out)
                        break
                    } catch YankError.unauthorized where attempt == 0 {
                        settings.serverToken = ""   // 저장된 비밀번호가 틀리면 지우고 다시 묻는다
                    }
                }
                guard let (fileExt, title) = result else { throw YankError.unauthorized }
                ext = fileExt; titleFromServer = title
            }
            let title = info?.title ?? titleFromServer ?? start.title
            let author = info?.author ?? start.uploader ?? ""
            try Task.checkCancellation()
            // 3) 저장
            update(id) { $0.state = .exporting }
            let name = Fmt.fileName(template: settings.filenameTemplate, title: title, uploader: author, id: vid, ext: ext)
            let final = uniqueURL(Disk.documents.appendingPathComponent(name))
            try FileManager.default.moveItem(at: out, to: final)
            let size = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size] as? Int64) ?? nil
            update(id) {
                $0.state = .completed; $0.progress = 100; $0.outputFile = final.lastPathComponent
                $0.finishedAt = Date(); $0.speedBytesPerSec = 0; $0.etaSeconds = -1
                if let size { $0.totalBytes = size }
            }
            // 사진 앱 저장은 권한 창이 뜰 수 있어서 작업 완료와 분리한다(창에서 오래 머물러도 대기열이 막히지 않게).
            if ext == "mp4", settings.saveToPhotos {
                Task { [weak self] in
                    if (try? await Self.saveToPhotos(final)) != nil { self?.update(id) { $0.savedToPhotos = true } }
                }
            }
        } catch is CancellationError {
            update(id) { $0.state = .canceled; $0.finishedAt = Date() }
        } catch {
            update(id) { $0.state = .failed; $0.error = error.localizedDescription; $0.finishedAt = Date() }
        }
    }

    /// 직접 받아도 소용없는 오류(접근 제한·스트림 없음)인지.
    nonisolated static func shouldFallBack(_ e: Error) -> Bool {
        if e is CancellationError { return false }
        switch e as? YankError {
        case .http(let c)?: return c == 403 || c == 401 || c == 410
        case .noStream?, .notPlayable?: return true
        default: return false
        }
    }

    /// 유튜브에서 직접 받아 합친다.
    private func direct(id: String, plan: StreamPlan, work: URL, out: URL) async throws {
        let meter = ProgressMeter()
        let total = max(plan.estimatedBytes, 1)
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                let s = meter.snapshot()
                let remain = s.speed > 0 ? (total - s.done) / s.speed : -1
                await MainActor.run {
                    self?.update(id) {
                        guard $0.state == .downloading else { return }
                        $0.progress = min(Double(s.done) / Double(total) * 100, 99.5)
                        $0.speedBytesPerSec = s.speed; $0.etaSeconds = remain
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { ticker.cancel() }
        let ua = plan.userAgent
        if let m = plan.muxed {
            try await StreamDownloader.download(m, userAgent: ua, to: out) { meter.add($0) }
        } else if let v = plan.video, let a = plan.audio {
            let vf = work.appendingPathComponent("v.mp4"), af = work.appendingPathComponent("a.m4a")
            async let x = StreamDownloader.download(v, userAgent: ua, to: vf) { meter.add($0) }
            async let y = StreamDownloader.download(a, userAgent: ua, to: af) { meter.add($0) }
            _ = try await (x, y)
            update(id) { $0.state = .processing; $0.progress = 99.5; $0.speedBytesPerSec = 0; $0.etaSeconds = -1 }
            try await Merger.merge(video: vf, audio: af, to: out)
        } else if let a = plan.audio {
            let raw = work.appendingPathComponent("raw.m4a")
            try await StreamDownloader.download(a, userAgent: ua, to: raw) { meter.add($0) }
            update(id) { $0.state = .processing; $0.progress = 99.5; $0.speedBytesPerSec = 0; $0.etaSeconds = -1 }
            try await Merger.remuxAudio(raw, to: out)
        }
    }

    /// 파이 서버가 받아서 합친 파일을 받아 온다. 서버 준비 0~60%, 파일 전송 60~100%.
    private func viaServer(id: String, videoId: String, server: ServerClient, work: URL,
                           into out: inout URL) async throws -> (String, String?) {
        let created = try await server.create(videoId: videoId, format: job(id)?.format ?? .best)
        defer { Task { await server.delete(created.id) } }
        var current = created
        while current.state != "completed" {
            try Task.checkCancellation()
            if current.state == "failed" { throw YankError.notPlayable(current.error ?? "Server failed") }
            update(id) {
                $0.progress = min(current.progress * 0.6, 60); $0.speedBytesPerSec = current.speed
                $0.etaSeconds = current.eta; $0.totalBytes = max(current.size, $0.totalBytes)
                if let t = current.title, $0.title == $0.url { $0.title = t }
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            current = try await server.status(created.id)
        }
        let fileExt = ((current.file ?? "") as NSString).pathExtension.isEmpty ? "mp4" : (current.file! as NSString).pathExtension
        out = work.appendingPathComponent("out." + fileExt)
        update(id) { $0.state = .downloading; $0.progress = 60 }
        let meter = ProgressMeter()
        let total = max(current.size, 1)
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                let s = meter.snapshot()
                await MainActor.run {
                    self?.update(id) {
                        guard $0.state == .downloading else { return }
                        $0.progress = 60 + min(Double(s.done) / Double(total) * 40, 39.5)
                        $0.speedBytesPerSec = s.speed
                        $0.etaSeconds = s.speed > 0 ? (total - s.done) / s.speed : -1
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { ticker.cancel() }
        try await server.download(current, to: out) { meter.add($0) }
        return (fileExt, current.title)
    }

    // MARK: 서버 비밀번호

    /// 저장된 비밀번호로 서버 클라이언트를 만든다. 없으면 입력창을 띄우고 답을 기다린다.
    private func obtainServer() async throws -> ServerClient {
        while true {
            if let s = ServerClient(url: settings.serverURL, token: settings.serverToken) { return s }
            let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                passwordWaiters.append(c); needsPassword = true
            }
            if !ok { throw YankError.notPlayable(L("error_blocked_no_server")) }
        }
    }

    /// 입력한 비밀번호가 맞으면 저장하고 기다리던 작업을 이어 가게 한다. 틀리면 오류 문구를 돌려준다.
    func submitPassword(_ pw: String) async -> String? {
        guard let c = ServerClient(url: settings.serverURL, token: pw) else { return L("invalid_url") }
        do { try await c.check() }
        catch YankError.unauthorized { return L("password_wrong") }
        catch { return LF("server_fail", error.localizedDescription) }
        settings.serverToken = pw.trimmingCharacters(in: .whitespacesAndNewlines)
        needsPassword = false
        let w = passwordWaiters; passwordWaiters = []
        w.forEach { $0.resume(returning: true) }
        return nil
    }

    func cancelPassword() {
        needsPassword = false
        let w = passwordWaiters; passwordWaiters = []
        w.forEach { $0.resume(returning: false) }
    }

    private func uniqueURL(_ url: URL) -> URL {
        var candidate = url, n = 2
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) (\(n)).\(ext)"); n += 1
        }
        return candidate
    }

    nonisolated static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw YankError.saveFailed("Photos permission") }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // iOS 는 앱이 백그라운드로 가면 곧 멈춘다. 잠깐(수십 초)은 이어 받도록 요청만 해 둔다.
    private func beginBackground() {
        #if canImport(UIKit) && !os(macOS)
        guard bgTask == 0 else { return }
        let id = UIApplication.shared.beginBackgroundTask(withName: "yank-download") { [weak self] in self?.endBackground(force: true) }
        bgTask = id.rawValue
        #endif
    }

    private func endBackground(force: Bool = false) {
        #if canImport(UIKit) && !os(macOS)
        if bgTask != 0, force || !jobs.contains(where: { $0.state.isRunning }) {
            UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: bgTask)); bgTask = 0
        }
        #endif
    }
}
