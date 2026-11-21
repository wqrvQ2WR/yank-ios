import Foundation

/// yank-pi 서버(파이의 yt-dlp) 클라이언트. 직접 받기가 403 으로 막힌 영상을 대신 받아 달라고 부탁한다.
struct ServerClient {
    let base: URL
    let token: String

    init?(url: String, token: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !token.isEmpty, let u = URL(string: trimmed), u.scheme?.hasPrefix("http") == true else { return nil }
        self.base = u; self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Job: Decodable {
        var id: String
        var state: String
        var progress: Double
        var speed: Int64
        var eta: Int64
        var size: Int64
        var file: String?
        var error: String?
        var title: String?
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        r.httpMethod = method
        r.setValue(token, forHTTPHeaderField: "X-Token")
        r.httpBody = body
        return r
    }

    private func send<T: Decodable>(_ r: URLRequest, as: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            if h.statusCode == 401 { throw YankError.unauthorized }
            throw YankError.http(h.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 연결과 토큰이 맞는지 본다. 없는 작업을 물어서 404 가 오면 인증은 통과한 것이다.
    func check() async throws {
        let (_, resp) = try await URLSession.shared.data(for: request("jobs/none"))
        guard let h = resp as? HTTPURLResponse else { throw YankError.http(0) }
        if h.statusCode == 401 { throw YankError.unauthorized }
        if h.statusCode != 404 && h.statusCode != 200 { throw YankError.http(h.statusCode) }
    }

    func create(videoId: String, format: DownloadFormat) async throws -> Job {
        let body = try JSONSerialization.data(withJSONObject: ["videoId": videoId, "format": format.rawValue])
        return try await send(request("jobs", method: "POST", body: body), as: Job.self)
    }

    func status(_ id: String) async throws -> Job { try await send(request("jobs/\(id)"), as: Job.self) }

    func delete(_ id: String) async { _ = try? await URLSession.shared.data(for: request("jobs/\(id)", method: "DELETE")) }

    /// 서버가 끝낸 파일을 받는다.
    func download(_ job: Job, to dest: URL, onBytes: @escaping (Int64) -> Void) async throws {
        try await StreamDownloader.ranged(url: base.appendingPathComponent("jobs/\(job.id)/file"),
                                          headers: ["X-Token": token], knownSize: job.size,
                                          chunk: 8 * 1024 * 1024, to: dest, onBytes: onBytes)
    }
}
