import Foundation

/// 구독한 채널 목록. 새 영상은 앱이 열려 있을 때 확인한다(iOS 는 꺼진 앱이 마음대로 받게 두지 않는다).
@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var subs: [Subscription]
    @Published var checking = false

    private static let file = "subscriptions.json"
    private static let lastCheckKey = "subs.lastCheck"

    init() { subs = Disk.load(Self.file, as: [Subscription].self) ?? [] }

    private func persist() { Disk.save(subs, Self.file) }

    func contains(_ channelId: String) -> Bool { subs.contains { $0.channelId == channelId } }

    func add(_ s: Subscription) {
        guard !contains(s.channelId) else { return }
        subs.append(s); persist()
    }

    func remove(_ channelId: String) { subs.removeAll { $0.channelId == channelId }; persist() }

    func edit(_ channelId: String, _ f: (inout Subscription) -> Void) {
        guard let i = subs.firstIndex(where: { $0.channelId == channelId }) else { return }
        f(&subs[i]); persist()
    }

    /// 입력(채널 링크, @핸들, 영상 링크)으로 구독을 추가한다. 이미 올라와 있던 영상은 "본 것"으로 친다.
    func subscribe(input: String) async throws -> Subscription {
        guard let kind = InputParser.channelInput(input) else { throw YankError.invalidURL }
        let channelId: String
        switch kind {
        case .channelId(let id): channelId = id
        case .handleURL(let u): channelId = try await YouTube.resolveChannel(url: u)
        case .video(let v):
            guard let id = try await YouTube.player(id: v).channelId else { throw YankError.invalidURL }
            channelId = id
        }
        if contains(channelId) { throw SubscribeError.already }
        let listing = try await YouTube.channel(id: channelId)
        let sub = Subscription(channelId: channelId, name: listing.name,
                               seenIds: listing.videos.map(\.id), lastCheckedAt: Date())
        add(sub)
        return sub
    }

    enum SubscribeError: Error { case already }

    /// 모든 구독을 돌며 새 영상을 대기열에 넣는다. 넣은 개수를 돌려준다.
    @discardableResult
    func checkAll(manager: DownloadManager, format: DownloadFormat, maxPerRun: Int = 5) async -> Int {
        guard !checking else { return 0 }
        checking = true
        defer { checking = false; UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey) }
        var queued = 0
        for sub in subs where sub.enabled {
            do {
                let listing = try await YouTube.channel(id: sub.channelId)
                let fresh = pickNewEntries(listing.videos, seenIds: sub.seenIds) { $0.id }
                let take = Array(fresh.prefix(maxPerRun))
                for v in take.reversed() { manager.enqueue(url: v.url, format: format, title: v.title, thumbnail: v.thumbnail, uploader: v.channel) }
                queued += take.count
                edit(sub.channelId) {
                    $0.seenIds = Array((fresh.map(\.id) + $0.seenIds).uniqued().prefix(Subscription.maxSeen))
                    $0.lastCheckedAt = Date(); $0.lastError = nil
                    if !take.isEmpty { $0.lastNewAt = Date() }
                    $0.totalDownloaded += take.count
                }
            } catch {
                edit(sub.channelId) { $0.lastCheckedAt = Date(); $0.lastError = String(error.localizedDescription.suffix(120)) }
            }
        }
        return queued
    }

    /// 마지막 확인 후 [hours] 시간이 지났는지.
    func isStale(hours: Double = 1) -> Bool {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        return Date().timeIntervalSince1970 - last > hours * 3600
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
