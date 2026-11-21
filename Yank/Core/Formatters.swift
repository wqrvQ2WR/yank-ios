import Foundation

enum Fmt {
    static func bytes(_ n: Int64) -> String {
        guard n > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(n) B" : String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "--" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "3:45", "1:02:03" -> 초
    static func parseClock(_ text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count == text.split(separator: ":").count else { return 0 }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// 파일 이름으로 쓸 수 없는 글자를 치운다.
    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var out = s.components(separatedBy: bad).joined(separator: " ")
        out = out.trimmingCharacters(in: .whitespaces)
        while out.hasPrefix(".") { out.removeFirst() }
        if out.count > 120 { out = String(out.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return out.isEmpty ? "video" : out
    }

    /// %(title)s, %(uploader)s, %(id)s, %(ext)s 만 지원하는 작은 템플릿.
    static func fileName(template: String, title: String, uploader: String, id: String, ext: String) -> String {
        var t = template.isEmpty ? "%(title)s.%(ext)s" : template
        let map = ["%(title)s": title, "%(uploader)s": uploader, "%(id)s": id, "%(ext)s": ext]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: k == "%(ext)s" ? v : safeFileName(v)) }
        if !t.lowercased().hasSuffix("." + ext) { t += "." + ext }
        return safeFileName(t)
    }
}

/// 사용자가 넣은 글이 어떤 종류인지.
enum InputKind: Equatable {
    case empty
    case video(String)     // videoId
    case badURL
    case query(String)
}

enum InputParser {
    static func classify(_ raw: String) -> InputKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        let lower = text.lowercased()
        let looksURL = lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("youtu.be/") || lower.hasPrefix("www.") || lower.hasPrefix("youtube.com")
            || lower.hasPrefix("m.youtube.com") || lower.hasPrefix("music.youtube.com")
        guard looksURL else { return .query(text) }
        if let id = videoID(from: text) { return .video(id) }
        return .badURL
    }

    static func videoID(from text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let comps = URLComponents(string: s), let host = comps.host?.lowercased() else { return nil }
        let path = comps.path
        let segs = path.split(separator: "/").map(String.init)
        func ok(_ id: String?) -> String? {
            guard let id, id.count == 11,
                  id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
            return id
        }
        if host == "youtu.be" || host == "www.youtu.be" { return ok(segs.first) }
        guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, let id = ok(v) { return id }
        if segs.count >= 2, ["shorts", "embed", "live", "v", "e"].contains(segs[0]) { return ok(segs[1]) }
        return nil
    }

    /// 채널 링크 / @핸들 / 영상 링크를 구독 입력으로 분류.
    enum ChannelInput: Equatable {
        case channelId(String)
        case handleURL(String)   // 해석이 필요한 주소
        case video(String)
    }

    static func channelInput(_ raw: String) -> ChannelInput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.hasPrefix("@"), text.count > 1, !text.contains(" ") {
            return .handleURL("https://www.youtube.com/\(text)")
        }
        var s = text
        if !s.lowercased().hasPrefix("http") {
            guard s.lowercased().hasPrefix("youtube.com") || s.lowercased().hasPrefix("www.youtube.com")
                    || s.lowercased().hasPrefix("m.youtube.com") else { return nil }
            s = "https://" + s
        }
        guard let comps = URLComponents(string: s), let host = comps.host?.lowercased(),
              host.hasSuffix("youtube.com") else {
            if let id = videoID(from: text) { return .video(id) }
            return nil
        }
        let segs = comps.path.split(separator: "/").map(String.init)
        if let first = segs.first {
            if first == "channel", segs.count >= 2, segs[1].hasPrefix("UC") { return .channelId(segs[1]) }
            if first.hasPrefix("@") || ((first == "c" || first == "user") && segs.count >= 2) {
                let head = first.hasPrefix("@") ? first : "\(first)/\(segs[1])"
                return .handleURL("https://www.youtube.com/\(head)")
            }
        }
        if let id = videoID(from: text) { return .video(id) }
        return nil
    }
}

/// 새로 올라온 영상만 가려낸다. 목록은 최신순.
func pickNewEntries<T>(_ entries: [T], seenIds: [String], idOf: (T) -> String) -> [T] {
    let seen = Set(seenIds)
    return entries.filter { !seen.contains(idOf($0)) }
}
