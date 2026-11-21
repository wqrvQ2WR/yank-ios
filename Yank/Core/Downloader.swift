import Foundation
import AVFoundation

/// 스트림 하나를 조각(Range)으로 나눠 받는다. 유튜브는 한 번에 통으로 요청하면 속도를 제한한다.
enum StreamDownloader {
    static let chunk: Int64 = 4 * 1024 * 1024

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    /// 받은 바이트 수를 [onBytes] 로 알린다. 총 크기를 돌려준다.
    @discardableResult
    static func download(_ format: StreamFormat, userAgent: String, to dest: URL,
                         onBytes: @escaping (Int64) -> Void) async throws -> Int64 {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let out = try FileHandle(forWritingTo: dest)
        defer { try? out.close() }

        var offset: Int64 = 0
        var total: Int64 = format.contentLength
        while total == 0 || offset < total {
            try Task.checkCancellation()
            let end = offset + chunk - 1
            var lastError: Error?
            var done = false
            for attempt in 0..<4 {
                do {
                    var req = URLRequest(url: format.url)
                    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                    req.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
                    let (tmp, resp) = try await session.download(for: req)
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    guard let http = resp as? HTTPURLResponse else { throw YankError.http(0) }
                    guard http.statusCode == 200 || http.statusCode == 206 else { throw YankError.http(http.statusCode) }
                    if total == 0, let cr = http.value(forHTTPHeaderField: "Content-Range"),
                       let t = Int64(cr.split(separator: "/").last ?? "") { total = t }
                    let n = try append(tmp, to: out)
                    if n == 0 { throw YankError.http(0) }
                    offset += n
                    onBytes(n)
                    // 서버가 Range 를 무시하고 통으로 준 경우
                    if http.statusCode == 200 { total = offset }
                    done = true
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch let e as URLError where e.code == .cancelled {
                    throw CancellationError()
                } catch {
                    lastError = error
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
                }
            }
            if !done { throw lastError ?? YankError.http(0) }
            if total == 0 { total = offset }   // 크기를 끝내 몰라도 무한 루프 방지는 위 n==0 이 한다
            if total > 0, offset >= total { break }
        }
        return offset
    }

    private static func append(_ src: URL, to out: FileHandle) throws -> Int64 {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        var n: Int64 = 0
        while let data = try input.read(upToCount: 1 << 20), !data.isEmpty {
            try out.write(contentsOf: data)
            n += Int64(data.count)
        }
        return n
    }
}

/// 영상 + 소리 파일을 다시 인코딩하지 않고 mp4 하나로 합친다. (ffmpeg 없이 AVFoundation 만으로)
///
/// AVMutableComposition 은 쓰지 않는다. 유튜브의 조각난(fragmented) mp4 는 AVAsset.duration 을
/// 실제의 2배로 읽어서, 그걸 그대로 넣으면 영상이 반 속도가 된다. 대신 샘플을 있는 그대로
/// (원래 시각표대로) 읽어서 새 파일에 옮겨 쓴다.
enum Merger {
    static func merge(video: URL, audio: URL, to dest: URL) async throws {
        try? FileManager.default.removeItem(at: dest)
        let vAsset = AVURLAsset(url: video), aAsset = AVURLAsset(url: audio)
        guard let vTrack = try await vAsset.loadTracks(withMediaType: .video).first,
              let aTrack = try await aAsset.loadTracks(withMediaType: .audio).first else {
            throw YankError.mergeFailed("no tracks")
        }
        let vFormat = try await vTrack.load(.formatDescriptions).first
        let aFormat = try await aTrack.load(.formatDescriptions).first
        let transform = try await vTrack.load(.preferredTransform)

        let vReader = try AVAssetReader(asset: vAsset), aReader = try AVAssetReader(asset: aAsset)
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: nil)
        let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
        vOut.alwaysCopiesSampleData = false; aOut.alwaysCopiesSampleData = false
        vReader.add(vOut); aReader.add(aOut)

        let writer = try AVAssetWriter(outputURL: dest, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vFormat)
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: aFormat)
        vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
        vIn.transform = transform
        writer.add(vIn); writer.add(aIn)
        writer.shouldOptimizeForNetworkUse = true

        guard vReader.startReading(), aReader.startReading() else {
            throw YankError.mergeFailed(vReader.error?.localizedDescription ?? aReader.error?.localizedDescription ?? "read")
        }
        guard writer.startWriting() else { throw YankError.mergeFailed(writer.error?.localizedDescription ?? "write") }
        writer.startSession(atSourceTime: .zero)

        async let v: Void = pump(vOut, into: vIn, label: "video")
        async let a: Void = pump(aOut, into: aIn, label: "audio")
        _ = try await (v, a)

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw YankError.mergeFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    /// 조각난 m4a 를 일반 m4a 로 다시 싼다. (재생기·파일 앱 호환용)
    static func remuxAudio(_ src: URL, to dest: URL) async throws {
        try? FileManager.default.removeItem(at: dest)
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw YankError.mergeFailed("no audio") }
        let format = try await track.load(.formatDescriptions).first
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        let writer = try AVAssetWriter(outputURL: dest, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else {
            throw YankError.mergeFailed(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "start")
        }
        writer.startSession(atSourceTime: .zero)
        try await pump(out, into: input, label: "audio-only")
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw YankError.mergeFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    private static func pump(_ output: AVAssetReaderTrackOutput, into input: AVAssetWriterInput, label: String) async throws {
        let queue = DispatchQueue(label: "yank.merge." + label)
        final class Box: @unchecked Sendable { let output: AVAssetReaderTrackOutput; let input: AVAssetWriterInput
            init(_ o: AVAssetReaderTrackOutput, _ i: AVAssetWriterInput) { output = o; input = i } }
        let box = Box(output, input)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            box.input.requestMediaDataWhenReady(on: queue) {
                while box.input.isReadyForMoreMediaData {
                    if let sample = box.output.copyNextSampleBuffer() {
                        // 조각 경계에 끼어 있는 빈 샘플(데이터 없음)은 버린다. 안 버리면 트랙 길이가 2배가 된다.
                        if CMSampleBufferGetNumSamples(sample) == 0 || CMSampleBufferGetTotalSampleSize(sample) == 0 { continue }
                        if !box.input.append(sample) { box.input.markAsFinished(); cont.resume(); return }
                    } else {
                        box.input.markAsFinished(); cont.resume(); return
                    }
                }
            }
        }
    }
}

/// 여러 스트림이 함께 쓰는 진행 집계. 속도는 최근 몇 초 평균.
final class ProgressMeter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var done: Int64 = 0
    private var samples: [(Date, Int64)] = []

    func add(_ n: Int64) {
        lock.lock(); defer { lock.unlock() }
        done += n
        let now = Date()
        samples.append((now, done))
        samples.removeAll { now.timeIntervalSince($0.0) > 4 }
    }

    func snapshot() -> (done: Int64, speed: Int64) {
        lock.lock(); defer { lock.unlock() }
        guard let first = samples.first, let last = samples.last, last.0 > first.0 else { return (done, 0) }
        let dt = last.0.timeIntervalSince(first.0)
        return (done, Int64(Double(last.1 - first.1) / dt))
    }
}
