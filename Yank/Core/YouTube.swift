import Foundation

/// 유튜브 내부(InnerTube) API 클라이언트. yt-dlp 없이 직접 스트림 주소를 얻는다.
/// 유튜브가 클라이언트 정책을 바꾸면 깨질 수 있어서, 클라이언트 설정은 한 곳(Client)에 모아 뒀다.
enum YouTube {

    struct Client {
        var name: String
        var version: String
        var userAgent: String
        var extra: [String: Any]
        var headerClientName: String   // X-YouTube-Client-Name 숫자
    }

    static let ios = Client(
        name: "IOS", version: "20.10.4",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        extra: ["deviceMake": "Apple", "deviceModel": "iPhone16,2", "osName": "iOS", "osVersion": "18.3.2.22D82"],
        headerClientName: "5")

    static let androidVR = Client(
        name: "ANDROID_VR", version: "1.62.27",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
        extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L"],
        headerClientName: "28")

    static let web = Client(
        name: "WEB", version: "2.20250310.01.00",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        extra: [:], headerClientName: "1")

    /// 위에서부터 차례로 시도한다.
    static let playerClients = [ios, androidVR]

    static var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.httpAdditionalHeaders = ["Accept-Language": "en-US,en;q=0.9"]
        return URLSession(configuration: c)
    }()

    private static var lang: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    // MARK: 요청

    private static func call(_ endpoint: String, client: Client, body: [String: Any]) async throws -> [String: Any] {
        var clientCtx: [String: Any] = [
            "clientName": client.name, "clientVersion": client.version,
            "hl": lang, "gl": Locale.current.region?.identifier ?? "US",
        ]
        client.extra.forEach { clientCtx[$0.key] = $0.value }
        var payload = body
        payload["context"] = ["client": clientCtx]

        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(client.headerClientName, forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw YankError.http(http.statusCode) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YankError.parse(endpoint)
        }
        return obj
    }

    // MARK: 영상 정보 + 스트림

    static func player(id: String) async throws -> VideoInfo {
        var lastReason = ""
        for client in playerClients {
            let json: [String: Any]
            do {
                json = try await call("player", client: client,
                                      body: ["videoId": id, "contentCheckOk": true, "racyCheckOk": true])
            } catch { lastReason = error.localizedDescription; continue }

            let status = json.dict("playabilityStatus")
            if let st = status?["status"] as? String, st != "OK" {
                lastReason = (status?["reason"] as? String) ?? st
                continue
            }
            let formats = parseFormats(json.dict("streamingData"))
            if formats.isEmpty { lastReason = "No stream"; continue }
            let details = json.dict("videoDetails") ?? [:]
            let thumbs = details.dict("thumbnail")?["thumbnails"] as? [[String: Any]]
            return VideoInfo(
                id: id,
                title: (details["title"] as? String) ?? id,
                author: (details["author"] as? String) ?? "",
                channelId: details["channelId"] as? String,
                durationSeconds: Int((details["lengthSeconds"] as? String) ?? "") ?? 0,
                thumbnail: (thumbs?.last?["url"] as? String) ?? "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                formats: formats, userAgent: client.userAgent)
        }
        throw YankError.notPlayable(lastReason.isEmpty ? "Unavailable" : lastReason)
    }

    static func parseFormats(_ streaming: [String: Any]?) -> [StreamFormat] {
        guard let streaming else { return [] }
        let all = ((streaming["formats"] as? [[String: Any]]) ?? []) + ((streaming["adaptiveFormats"] as? [[String: Any]]) ?? [])
        return all.compactMap { f in
            guard let itag = f["itag"] as? Int, let urlStr = f["url"] as? String, let url = URL(string: urlStr),
                  let mimeFull = f["mimeType"] as? String else { return nil }
            let parts = mimeFull.components(separatedBy: ";")
            let mime = parts[0].trimmingCharacters(in: .whitespaces)
            var codecs = ""
            if let r = mimeFull.range(of: "codecs=\"") {
                codecs = String(mimeFull[r.upperBound...]).replacingOccurrences(of: "\"", with: "")
            }
            let isVideo = mime.hasPrefix("video/")
            let codecList = codecs.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let hasAudioCodec = codecList.contains { $0.hasPrefix("mp4a") || $0.hasPrefix("opus") }
            return StreamFormat(
                itag: itag, url: url, mime: mime, codecs: codecs,
                width: f["width"] as? Int ?? 0, height: f["height"] as? Int ?? 0,
                bitrate: f["bitrate"] as? Int ?? 0,
                contentLength: Int64((f["contentLength"] as? String) ?? "") ?? 0,
                hasVideo: isVideo, hasAudio: !isVideo || (isVideo && hasAudioCodec && codecList.count > 1))
        }
    }

    // MARK: 검색

    static func search(_ query: String) async throws -> [SearchResult] {
        let json = try await call("search", client: web, body: ["query": query, "params": "EgIQAQ%3D%3D"])
        return videos(in: json)
    }

    // MARK: 채널

    /// 채널 영상 탭 최신 목록. 쇼츠/라이브 탭은 포함되지 않는다.
    static func channel(id: String) async throws -> ChannelListing {
        let json = try await call("browse", client: web, body: ["browseId": id, "params": "EgZ2aWRlb3PyBgQKAjoA"])
        let name = ((json.dict("metadata")?.dict("channelMetadataRenderer"))?["title"] as? String)
            ?? ((json.dict("header")?.dict("pageHeaderRenderer"))?["pageTitle"] as? String) ?? id
        return ChannelListing(name: name, channelId: id, videos: videos(in: json))
    }

    /// 채널 주소/핸들 -> channelId
    static func resolveChannel(url: String) async throws -> String {
        let json = try await call("navigation/resolve_url", client: web, body: ["url": url])
        if let id = (json.dict("endpoint")?.dict("browseEndpoint"))?["browseId"] as? String, id.hasPrefix("UC") {
            return id
        }
        throw YankError.invalidURL
    }

    // MARK: 응답에서 영상 카드 뽑기

    static func videos(in root: Any) -> [SearchResult] {
        var out: [SearchResult] = []
        var seen = Set<String>()
        func add(_ r: SearchResult?) {
            guard let r, !seen.contains(r.id) else { return }
            seen.insert(r.id); out.append(r)
        }
        walk(root) { key, node in
            if key == "videoRenderer" { add(fromVideoRenderer(node)) }
            else if key == "lockupViewModel" { add(fromLockup(node)) }
        }
        return out
    }

    private static func walk(_ node: Any, _ visit: (String, [String: Any]) -> Void) {
        if let d = node as? [String: Any] {
            for k in d.keys.sorted() {
                if let sub = d[k] as? [String: Any] { visit(k, sub) }
                walk(d[k] as Any, visit)
            }
        } else if let a = node as? [Any] {
            for v in a { walk(v, visit) }
        }
    }

    private static func text(_ node: Any?) -> String? {
        guard let d = node as? [String: Any] else { return nil }
        if let s = d["simpleText"] as? String { return s }
        if let runs = d["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
        return nil
    }

    private static func fromVideoRenderer(_ d: [String: Any]) -> SearchResult? {
        guard let id = d["videoId"] as? String else { return nil }
        let thumbs = d.dict("thumbnail")?["thumbnails"] as? [[String: Any]]
        return SearchResult(
            id: id, title: text(d["title"]) ?? id,
            channel: text(d["ownerText"]) ?? text(d["longBylineText"]),
            durationSeconds: Fmt.parseClock(text(d["lengthText"])),
            viewText: text(d["viewCountText"]) ?? text(d["shortViewCountText"]),
            thumbnail: (thumbs?.last?["url"] as? String) ?? "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    /// 2025 년부터 일부 목록이 쓰는 새 카드 형식.
    private static func fromLockup(_ d: [String: Any]) -> SearchResult? {
        guard (d["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_VIDEO",
              let id = d["contentId"] as? String else { return nil }
        let meta = d.dict("metadata")?.dict("lockupMetadataViewModel")
        let title = (meta?.dict("title"))?["content"] as? String
        return SearchResult(id: id, title: title ?? id, channel: nil, durationSeconds: 0, viewText: nil,
                            thumbnail: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }
}

extension Dictionary where Key == String, Value == Any {
    func dict(_ k: String) -> [String: Any]? { self[k] as? [String: Any] }
}

// MARK: 포맷 고르기

struct StreamPlan {
    var video: StreamFormat?
    var audio: StreamFormat?
    /// 영상+소리가 한 파일인 스트림(화질이 낮음). 합칠 수 없을 때만 쓴다.
    var muxed: StreamFormat?
    var userAgent: String
    var ext: String
    var estimatedBytes: Int64 {
        if let m = muxed { return m.contentLength }
        return (video?.contentLength ?? 0) + (audio?.contentLength ?? 0)
    }
}

enum FormatPicker {
    /// iOS 에는 ffmpeg 가 없어서 AVFoundation 이 합칠 수 있는 H.264(mp4) + AAC(m4a) 만 고른다.
    static func plan(info: VideoInfo, format: DownloadFormat) throws -> StreamPlan {
        let audios = info.formats.filter { !$0.hasVideo && $0.isMP4 && $0.isAAC }
            .sorted { $0.bitrate > $1.bitrate }
        if format.isAudio {
            guard let a = audios.first else { throw YankError.noStream }
            return StreamPlan(video: nil, audio: a, muxed: nil, userAgent: info.userAgent, ext: "m4a")
        }
        let cap = format.heightCap ?? Int.max
        let videos = info.formats.filter { $0.hasVideo && !$0.hasAudio && $0.isMP4 && $0.isH264 && $0.height <= cap }
            .sorted { ($0.height, $0.bitrate) > ($1.height, $1.bitrate) }
        let muxed = info.formats.filter { $0.hasVideo && $0.hasAudio && $0.isMP4 && $0.height <= cap }
            .sorted { $0.height > $1.height }.first
        if let v = videos.first, let a = audios.first {
            // 합친 쪽이 통짜 스트림보다 화질이 낮으면 통짜를 쓴다.
            if let m = muxed, m.height > v.height {
                return StreamPlan(video: nil, audio: nil, muxed: m, userAgent: info.userAgent, ext: "mp4")
            }
            return StreamPlan(video: v, audio: a, muxed: nil, userAgent: info.userAgent, ext: "mp4")
        }
        if let m = muxed { return StreamPlan(video: nil, audio: nil, muxed: m, userAgent: info.userAgent, ext: "mp4") }
        throw YankError.noStream
    }
}
