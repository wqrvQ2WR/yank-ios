import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var serverStatus: String?
    @State private var testing = false

    var body: some View {
        VStack(spacing: 0) {
            Header(title: L("nav_settings"))
            Form {
                Section(L("settings_storage")) {
                    Toggle(L("settings_save_to_photos"), isOn: $settings.saveToPhotos)
                    Text(L("settings_save_to_photos_desc")).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("settings_filename_template"))
                        TextField("%(title)s.%(ext)s", text: $settings.filenameTemplate)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Text(L("settings_filename_template_ios_desc")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("settings_downloads")) {
                    Picker(L("format_label"), selection: $settings.defaultFormat) {
                        ForEach(DownloadFormat.allCases) { Text(L($0.titleKey)).tag($0) }
                    }
                    Stepper(value: $settings.concurrent, in: 1...3) {
                        HStack { Text(L("settings_concurrent")); Spacer(); Text("\(settings.concurrent)").foregroundStyle(.secondary) }
                    }
                    Text(L("settings_keep_open_hint")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("settings_server")) {
                    Toggle(L("settings_server_use"), isOn: $settings.serverEnabled)
                    TextField(L("settings_server_url"), text: $settings.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(L("settings_server_token"), text: $settings.serverToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        Task { await testServer() }
                    } label: {
                        HStack { Text(L("settings_server_test")); Spacer(); if testing { ProgressView() } }
                    }.disabled(testing || settings.serverToken.isEmpty)
                    if let serverStatus { Text(serverStatus).font(.caption).foregroundStyle(.secondary) }
                    Text(L("settings_server_desc")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("settings_appearance")) {
                    Picker(L("settings_theme"), selection: $settings.theme) {
                        ForEach(ThemeMode.allCases) { Text(L($0.titleKey)).tag($0) }
                    }
                }
                Section(L("settings_updates")) {
                    HStack {
                        Text(L("settings_app_version")); Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func testServer() async {
        testing = true; serverStatus = nil
        defer { testing = false }
        guard let c = ServerClient(url: settings.serverURL, token: settings.serverToken) else {
            serverStatus = LF("server_fail", L("invalid_url")); return
        }
        do { try await c.check(); serverStatus = L("server_ok") }
        catch { serverStatus = LF("server_fail", error.localizedDescription) }
    }
}
