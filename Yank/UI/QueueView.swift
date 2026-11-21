import SwiftUI

struct QueueView: View {
    @EnvironmentObject var manager: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            Header(title: L("nav_downloads"))
            if manager.jobs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray").font(.system(size: 44)).foregroundStyle(Brand.gradient)
                    Text(L("empty_queue")).font(.headline)
                    Text(L("empty_queue_hint")).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(32).frame(maxWidth: .infinity).background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        HStack {
                            Button(L("clear_finished")) { manager.clearFinished() }
                            Spacer()
                            Button(L("cancel_all"), role: .destructive) { manager.cancelAll() }.disabled(manager.activeCount == 0)
                        }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                    }
                    ForEach(manager.jobs) { job in
                        JobRow(job: job)
                            .swipeActions {
                                Button(L("remove"), role: .destructive) { manager.remove(job.id) } 
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct JobRow: View {
    @EnvironmentObject var manager: DownloadManager
    let job: DownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Thumb(url: job.thumbnail)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(L(job.state.titleKey) + (job.viaServer ? " · " + L("via_server") : "")).font(.caption.weight(.semibold)).foregroundStyle(stateColor)
                }
            }
            if job.state == .downloading || job.state == .serverPreparing || job.state == .processing || job.state == .exporting {
                ProgressView(value: job.progress, total: 100).tint(Brand.magenta)
                if job.state == .downloading || job.state == .serverPreparing { detail }
            }
            if job.state == .completed {
                HStack {
                    Text(Fmt.bytes(job.totalBytes) + (job.savedToPhotos ? " · " + L("photos_saved") : " · " + L("files_saved")))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let url = manager.fileURL(job) {
                        ShareLink(item: url) { Label(L("share"), systemImage: "square.and.arrow.up") }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            if let e = job.error, job.state == .failed {
                Text(e).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            HStack {
                if job.state.isActive { Button(L("cancel"), role: .destructive) { manager.cancel(job.id) } }
                if job.state == .failed || job.state == .canceled { Button(L("retry")) { manager.retry(job.id) } }
            }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch job.state {
        case .completed: return .green
        case .failed: return .red
        case .canceled: return .secondary
        default: return Brand.violet
        }
    }

    private var detail: some View {
        var parts = [LF("progress_detail", Fmt.bytes(job.downloadedBytes), Fmt.bytes(job.totalBytes))]
        if job.speedBytesPerSec > 0 { parts.append(LF("speed_value", Fmt.bytes(job.speedBytesPerSec))) }
        if job.etaSeconds >= 0 { parts.append(LF("eta_value", Fmt.duration(Int(job.etaSeconds)))) }
        return Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
    }
}
