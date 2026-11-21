import Foundation

enum YankError: LocalizedError {
    case invalidURL
    case notPlayable(String)
    case noStream
    case http(Int)
    case parse(String)
    case mergeFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid link"
        case .notPlayable(let r): return r
        case .noStream: return "No downloadable stream"
        case .http(let c): return "HTTP \(c)"
        case .parse(let m): return "Parse error: \(m)"
        case .mergeFailed(let m): return "Merge failed: \(m)"
        case .saveFailed(let m): return "Save failed: \(m)"
        }
    }
}

enum DownloadFormat: String, Codable, CaseIterable, Identifiable {
    case best, p1080, p720, audio

    var id: String { rawValue }
    var isAudio: Bool { self == .audio }
    /// 높이 제한. nil 이면 제한 없음.
    var heightCap: Int? {
        switch self {
        case .p1080: return 1080
        case .p720: return 720
        default: return nil
        }
    }
    var titleKey: String {
        switch self {
        case .best: return "format_best"
        case .p1080: return "format_1080p"
        case .p720: return "format_720p"
        case .audio: return "format_audio_m4a"
        }
    }
}

enum JobState: String, Codable {
    case queued, fetching, downloading, serverPreparing, processing, exporting, completed, failed, canceled

    var isActive: Bool {
        switch self {
        case .queued, .fetching, .downloading, .serverPreparing, .processing, .exporting: return true
        default: return false
        }
    }
    var isRunning: Bool { isActive && self != .queued }
    var titleKey: String {
        switch self {
        case .queued: return "state_queued"
        case .fetching: return "state_fetching"
        case .downloading: return "state_downloading"
        case .serverPreparing: return "state_server"
        case .processing: return "state_processing"
        case .exporting: return "state_exporting"
        case .completed: return "state_completed"
        case .failed: return "state_failed"
        case .canceled: return "state_canceled"
        }
    }
}

struct DownloadJob: Codable, Identifiable, Equatable {
    var id: String
    var url: String
    var format: DownloadFormat
    var title: String
    var thumbnail: String?
    var uploader: String?
    var durationSeconds: Int = 0
    var state: JobState = .queued
    /// 0...100
    var progress: Double = 0
    var speedBytesPerSec: Int64 = 0
    var etaSeconds: Int64 = -1
    var totalBytes: Int64 = 0
    /// Documents 폴더 안의 파일 이름 (앱을 다시 설치해도 경로가 바뀌지 않게 이름만 저장)
    var outputFile: String?
    var savedToPhotos: Bool = false
    /// 직접 받기가 막혀서(403 등) 파이 서버를 거친 작업
    var viaServer: Bool = false
    var error: String?
    var createdAt: Date = Date()
    var finishedAt: Date?

    var downloadedBytes: Int64 {
        totalBytes > 0 ? Int64(Double(totalBytes) * progress / 100) : 0
    }
}

struct SearchResult: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var channel: String?
    var durationSeconds: Int
    var viewText: String?
    var thumbnail: String?

    var url: String { "https://www.youtube.com/watch?v=\(id)" }
}

struct StreamFormat {
    var itag: Int
    var url: URL
    var mime: String          // video/mp4
    var codecs: String        // avc1.640028 또는 mp4a.40.2
    var width: Int
    var height: Int
    var bitrate: Int
    var contentLength: Int64
    var hasVideo: Bool
    var hasAudio: Bool

    var isMP4: Bool { mime.hasPrefix("video/mp4") || mime.hasPrefix("audio/mp4") }
    var isH264: Bool { codecs.hasPrefix("avc1") }
    var isAAC: Bool { codecs.contains("mp4a") }
}

struct VideoInfo {
    var id: String
    var title: String
    var author: String
    var channelId: String?
    var durationSeconds: Int
    var thumbnail: String?
    var formats: [StreamFormat]
    var userAgent: String
}

struct ChannelListing {
    var name: String
    var channelId: String
    var videos: [SearchResult]
}

/// 구독한 채널 하나.
struct Subscription: Codable, Identifiable, Equatable {
    var channelId: String
    var name: String
    var enabled: Bool = true
    var seenIds: [String] = []
    var addedAt: Date = Date()
    var lastCheckedAt: Date?
    var lastNewAt: Date?
    var lastError: String?
    var totalDownloaded: Int = 0

    var id: String { channelId }
    static let maxSeen = 100
}
