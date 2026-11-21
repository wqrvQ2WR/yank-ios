import SwiftUI

@main
struct YankApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var manager: DownloadManager
    @StateObject private var subs = SubscriptionStore()

    init() {
        let s = AppSettings()
        _settings = StateObject(wrappedValue: s)
        _manager = StateObject(wrappedValue: DownloadManager(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(subs)
                .preferredColorScheme(settings.theme.scheme)
                .tint(Brand.violet)
        }
    }
}
