import SwiftUI

struct HomeView: View {
    @EnvironmentObject var manager: DownloadManager
    @EnvironmentObject var settings: AppSettings
    var goQueue: () -> Void

    @State private var input = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var kind: InputKind { InputParser.classify(input) }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Yank", subtitle: L("url_hint"))
            ScrollView {
                VStack(spacing: 14) {
                    inputCard
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if searching { ProgressView(L("searching")).padding(.top, 8) }
                    if !results.isEmpty { resultList }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var inputCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack {
                    TextField(L("url_hint"), text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).focused($focused)
                        .onSubmit(go)
                    if input.isEmpty {
                        Button(L("paste")) { if let s = UIPasteboard.general.string { input = s } }
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Button { input = ""; results = []; message = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.accessibilityLabel(L("clear"))
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(DownloadFormat.allCases) { f in
                        Chip(title: L(f.titleKey), selected: settings.defaultFormat == f) { settings.defaultFormat = f }
                    } }
                }

                Button(action: go) {
                    if case .query = kind { Text(L("search")) } else { Text(L("download")) }
                }
                .buttonStyle(GradientButtonStyle(enabled: kind != .empty))
                .disabled(kind == .empty)
            }
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("search_results")).font(.headline)
                Spacer()
                Button(L("clear_results")) { results = [] }.font(.subheadline)
            }
            ForEach(results) { r in
                Card {
                    HStack(spacing: 12) {
                        Thumb(url: r.thumbnail)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text([r.channel, r.durationSeconds > 0 ? Fmt.duration(r.durationSeconds) : nil].compactMap { $0 }.joined(separator: "  "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let v = r.viewText { Text(v).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        Button {
                            add(url: r.url, title: r.title, thumb: r.thumbnail, uploader: r.channel)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill").font(.system(size: 30)).foregroundStyle(Brand.gradient)
                        }.accessibilityLabel(L("download"))
                    }
                }
            }
        }
    }

    private func go() {
        focused = false; message = nil
        switch kind {
        case .empty: break
        case .badURL: message = L("invalid_url")
        case .video: add(url: input.trimmingCharacters(in: .whitespacesAndNewlines))
        case .query(let q): runSearch(q)
        }
    }

    private func add(url: String, title: String? = nil, thumb: String? = nil, uploader: String? = nil) {
        manager.enqueue(url: url, format: settings.defaultFormat, title: title, thumbnail: thumb, uploader: uploader)
        manager.toast = L("queued_toast")
        if title == nil { input = "" }
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        searching = true; results = []
        searchTask = Task {
            do {
                let r = try await YouTube.search(q)
                guard !Task.isCancelled else { return }
                results = r
                if r.isEmpty { message = L("search_empty") }
            } catch { if !Task.isCancelled { message = LF("search_failed", error.localizedDescription) } }
            searching = false
        }
    }
}
