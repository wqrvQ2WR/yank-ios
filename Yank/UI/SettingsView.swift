import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

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
}
