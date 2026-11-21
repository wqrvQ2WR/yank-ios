import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var subs: SubscriptionStore
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings

    @State private var input = ""
    @State private var adding = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Header(title: L("nav_subscriptions"), subtitle: L("sub_subtitle"))
            List {
                Section {
                    TextField(L("sub_input_label"), text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                        .onSubmit(add)
                    Button(action: add) { Text(adding ? L("sub_adding") : L("sub_add")) }
                        .buttonStyle(GradientButtonStyle(enabled: !input.isEmpty && !adding))
                        .disabled(input.isEmpty || adding)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Toggle(L("sub_auto"), isOn: $settings.autoDownloadNew)
                    Text(L("sub_auto_desc")).font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task {
                            message = L("sub_checking")
                            let n = await subs.checkAll(manager: manager, format: settings.defaultFormat)
                            message = n > 0 ? LF("notif_new_videos_title", n) : L("update_none")
                        }
                    } label: {
                        HStack { Text(subs.checking ? L("sub_checking") : L("sub_check_now")); Spacer(); if subs.checking { ProgressView() } }
                    }.disabled(subs.checking || subs.subs.isEmpty)
                }
                Section(L("sub_list_title")) {
                    if subs.subs.isEmpty {
                        Text(L("sub_empty")).foregroundStyle(.secondary)
                    }
                    ForEach(subs.subs) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.subheadline.weight(.semibold))
                            Text(status(s)).font(.caption).foregroundStyle(s.lastError == nil ? Color.secondary : Color.red)
                        }
                        .swipeActions { Button(L("sub_remove"), role: .destructive) { subs.remove(s.channelId) } }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func status(_ s: Subscription) -> String {
        if let e = s.lastError { return LF("sub_status_error", e) }
        guard let t = s.lastCheckedAt else { return L("sub_status_waiting") }
        return LF("sub_status_ok", t.formatted(date: .abbreviated, time: .shortened), s.totalDownloaded)
    }

    private func add() {
        let text = input
        guard !text.isEmpty, !adding else { return }
        adding = true; message = L("sub_adding")
        Task {
            do {
                let s = try await subs.subscribe(input: text)
                message = LF("sub_added", s.name); input = ""
            } catch SubscriptionStore.SubscribeError.already {
                message = L("sub_already")
            } catch YankError.invalidURL {
                message = L("sub_invalid")
            } catch { message = LF("sub_failed", error.localizedDescription) }
            adding = false
        }
    }
}
