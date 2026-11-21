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
        .sheet(isPresented: $manager.needsPassword, onDismiss: { manager.cancelPassword() }) {
            PasswordSheet().environmentObject(manager)
        }
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

/// 서버 비밀번호를 한 번 묻는 창. 맞으면 저장되고 다시는 뜨지 않는다.
struct PasswordSheet: View {
    @EnvironmentObject var manager: DownloadManager
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(L("settings_server_token"), text: $password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).submitLabel(.done).onSubmit { submit() }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                } footer: { Text(L("password_desc")) }
            }
            .navigationTitle(L("password_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("password_cancel")) { manager.cancelPassword() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { submit() } label: { if busy { ProgressView() } else { Text(L("password_confirm")) } }
                        .disabled(busy || password.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard !busy, !password.isEmpty else { return }
        busy = true; error = nil
        Task {
            error = await manager.submitPassword(password)
            busy = false
        }
    }
}
