import SwiftUI

struct RootView: View {
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var subs: SubscriptionStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView(goQueue: { tab = 1 })
                .tabItem { Label(L("nav_home"), systemImage: "arrow.down.circle.fill") }.tag(0)
            QueueView()
                .tabItem { Label(L("nav_downloads"), systemImage: "list.bullet.rectangle.fill") }.tag(1)
                .badge(manager.activeCount)
            SubscriptionsView()
                .tabItem { Label(L("nav_subscriptions"), systemImage: "bell.badge.fill") }.tag(2)
            SettingsView()
                .tabItem { Label(L("nav_settings"), systemImage: "gearshape.fill") }.tag(3)
        }
        .overlay(alignment: .top) { ToastView(text: $manager.toast) }
        .onChange(of: phase) { _, new in
            if new == .active { checkSubscriptions() }
        }
        .task { checkSubscriptions() }
    }

    private func checkSubscriptions() {
        guard settings.autoDownloadNew, subs.isStale() else { return }
        Task {
            let n = await subs.checkAll(manager: manager, format: settings.defaultFormat)
            if n > 0 { manager.toast = LF("notif_new_videos_title", n) }
        }
    }
}

struct ToastView: View {
    @Binding var text: String?
    var body: some View {
        if let t = text {
            Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Brand.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: t) {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    withAnimation { text = nil }
                }
        }
    }
}
