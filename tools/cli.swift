import Foundation

// 맥에서 핵심 로직(추출·다운로드·합치기)을 검증하는 작은 CLI. tools/test.sh 가 빌드한다.
// 사용: yankcli search <검색어> | info <url> | get <url> [best|p1080|p720|audio] | channel <@핸들> | selftest
@main
struct CLI {
    static func main() async {
        let a = Array(CommandLine.arguments.dropFirst())
        do {
            switch a.first {
            case "selftest": try selftest()
            case "search":
                for r in try await YouTube.search(a.dropFirst().joined(separator: " ")).prefix(8) {
                    print(r.id, Fmt.duration(r.durationSeconds), r.title, "|", r.channel ?? "-", "|", r.viewText ?? "-")
                }
            case "info":
                guard case .video(let id) = InputParser.classify(a[1]) else { throw YankError.invalidURL }
                let info = try await YouTube.player(id: id)
                print(info.title, "-", info.author, info.channelId ?? "", Fmt.duration(info.durationSeconds))
                for f in info.formats { print(" ", f.itag, f.mime, f.codecs, f.height, f.bitrate, f.contentLength) }
                for fmt in DownloadFormat.allCases {
                    let p = try FormatPicker.plan(info: info, format: fmt)
                    print(fmt.rawValue, "->", p.video?.itag ?? p.muxed?.itag ?? 0, p.audio?.itag ?? 0, p.ext, Fmt.bytes(p.estimatedBytes))
                }
            case "channel":
                var s = a[1]
                if case .handleURL(let u)? = InputParser.channelInput(s) { s = try await YouTube.resolveChannel(url: u) }
                let l = try await YouTube.channel(id: s)
                print(l.name, l.channelId, l.videos.count)
                for v in l.videos.prefix(5) { print(" ", v.id, v.title) }
            case "get":
                guard case .video(let id) = InputParser.classify(a[1]) else { throw YankError.invalidURL }
                let fmt = DownloadFormat(rawValue: a.count > 2 ? a[2] : "p720") ?? .p720
                try await get(id: id, format: fmt)
            default: print("selftest | search q | info url | channel @x | get url [fmt]")
            }
        } catch { print("ERROR:", error.localizedDescription); exit(1) }
    }

    static func get(id: String, format: DownloadFormat) async throws {
        let info = try await YouTube.player(id: id)
        let plan = try FormatPicker.plan(info: info, format: format)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yankcli-\(id)")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let meter = ProgressMeter()
        let total = plan.estimatedBytes
        let t0 = Date()
        let ticker = Task {
            while !Task.isCancelled {
                let s = meter.snapshot()
                print("\r  \(Fmt.bytes(s.done)) / \(Fmt.bytes(total))  \(Fmt.bytes(s.speed))/s    ", terminator: "")
                fflush(stdout)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        defer { ticker.cancel() }
        let out = dir.appendingPathComponent("out." + plan.ext)
        if let m = plan.muxed {
            try await StreamDownloader.download(m, userAgent: plan.userAgent, to: out) { meter.add($0) }
        } else if let v = plan.video, let au = plan.audio {
            let vf = dir.appendingPathComponent("v.mp4"), af = dir.appendingPathComponent("a.m4a")
            async let x = StreamDownloader.download(v, userAgent: plan.userAgent, to: vf) { meter.add($0) }
            async let y = StreamDownloader.download(au, userAgent: plan.userAgent, to: af) { meter.add($0) }
            _ = try await (x, y)
            print("\n  merging")
            try await Merger.merge(video: vf, audio: af, to: out)
        } else if let au = plan.audio {
            let raw = dir.appendingPathComponent("raw.m4a")
            try await StreamDownloader.download(au, userAgent: plan.userAgent, to: raw) { meter.add($0) }
            try await Merger.remuxAudio(raw, to: out)
        }
        print("\nOK \(out.path) \(Fmt.bytes((try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int64) ?? 0)) in \(Int(Date().timeIntervalSince(t0)))s")
    }

    static func selftest() throws {
        func eq<T: Equatable>(_ a: T, _ b: T, _ m: String) { if a != b { print("FAIL", m, a, b); exit(1) } }
        eq(InputParser.classify("https://youtu.be/dQw4w9WgXcQ?t=3"), .video("dQw4w9WgXcQ"), "youtu.be")
        eq(InputParser.classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=x"), .video("dQw4w9WgXcQ"), "watch")
        eq(InputParser.classify("https://youtube.com/shorts/dQw4w9WgXcQ"), .video("dQw4w9WgXcQ"), "shorts")
        eq(InputParser.classify("https://example.com/x"), .badURL, "bad")
        eq(InputParser.classify("뉴진스 하입보이"), .query("뉴진스 하입보이"), "query")
        eq(InputParser.classify("  "), .empty, "empty")
        eq(InputParser.channelInput("@veritasium"), .handleURL("https://www.youtube.com/@veritasium"), "handle")
        eq(InputParser.channelInput("https://www.youtube.com/channel/UCHnyfMqiRRG1u-2MsSQLbXA/videos"), .channelId("UCHnyfMqiRRG1u-2MsSQLbXA"), "chan")
        eq(Fmt.parseClock("1:02:03"), 3723, "clock")
        eq(Fmt.parseClock("3:45"), 225, "clock2")
        eq(Fmt.bytes(1536), "1.5 KB", "bytes")
        eq(Fmt.fileName(template: "%(title)s.%(ext)s", title: "a/b:c", uploader: "u", id: "i", ext: "mp4"), "a b c.mp4", "fname")
        eq(pickNewEntries(["a", "b", "c"], seenIds: ["b"]) { $0 }, ["a", "c"], "new")
        print("selftest OK")
    }
}
