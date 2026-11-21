import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case light, system, dark
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .light: return "theme_light"
        case .system: return "theme_system"
        case .dark: return "theme_dark"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

/// 화면과 다운로드 관리자가 함께 읽는 설정. UserDefaults 에 바로 저장된다.
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var defaultFormat: DownloadFormat { didSet { d.set(defaultFormat.rawValue, forKey: "defaultFormat") } }
    @Published var concurrent: Int { didSet { d.set(concurrent, forKey: "concurrent") } }
    @Published var saveToPhotos: Bool { didSet { d.set(saveToPhotos, forKey: "saveToPhotos") } }
    @Published var filenameTemplate: String { didSet { d.set(filenameTemplate, forKey: "filenameTemplate") } }
    @Published var theme: ThemeMode { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var autoDownloadNew: Bool { didSet { d.set(autoDownloadNew, forKey: "autoDownloadNew") } }
    /// 직접 받기가 막힌 영상을 대신 받아 줄 서버(yank-pi). 토큰은 소스에 넣지 않고 사용자가 설정에 붙여 넣는다.
    @Published var serverEnabled: Bool { didSet { d.set(serverEnabled, forKey: "serverEnabled") } }
    @Published var serverURL: String { didSet { d.set(serverURL, forKey: "serverURL") } }
    @Published var serverToken: String { didSet { d.set(serverToken, forKey: "serverToken") } }

    init() {
        defaultFormat = DownloadFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .best
        let c = d.integer(forKey: "concurrent")
        concurrent = c == 0 ? 2 : min(max(c, 1), 3)
        saveToPhotos = d.object(forKey: "saveToPhotos") as? Bool ?? true
        filenameTemplate = d.string(forKey: "filenameTemplate") ?? "%(title)s.%(ext)s"
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .light
        autoDownloadNew = d.object(forKey: "autoDownloadNew") as? Bool ?? true
        serverEnabled = d.object(forKey: "serverEnabled") as? Bool ?? true
        serverURL = d.string(forKey: "serverURL") ?? "http://pi.taild4dc8e.ts.net:8260"
        serverToken = d.string(forKey: "serverToken") ?? ""
    }
}

/// JSON 파일 하나로 목록을 저장하는 작은 도우미.
enum Disk {
    static var supportDir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    /// 파일 앱의 "나의 iPhone > Yank" 에 보이는 폴더.
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: supportDir.appendingPathComponent(name)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(value) { try? data.write(to: supportDir.appendingPathComponent(name), options: .atomic) }
    }
}
