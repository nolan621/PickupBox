import Foundation
import Observation
import WidgetKit

/// 本地存储：一个 JSON 文件，够小、够稳、没有迁移烦恼。
/// 后面想换成 SwiftData，只需要替换这个类的内部实现，界面不用动。
@MainActor
@Observable
final class PickupStore {
    static let shared = PickupStore()

    /// 和小组件共享数据用的 App Group
    static let appGroupID = "group.io.github.nolan621.PickupBox"
    /// 必须和小组件里 Widget.kind 保持一致
    static let widgetKind = "PickupWidget"

    private(set) var items: [PickupItem] = []

    /// 旧版本存放的位置，用来做一次性迁移
    private var legacyFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pickups.json")
    }

    /// 现在的位置：App Group 容器，App 和小组件都能读
    private var fileURL: URL {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("pickups.json")
    }

    init() {
        migrateLegacyFileIfNeeded()
        load()
    }

    /// 把 Documents 里的老数据搬到 App Group 容器，只搬一次
    private func migrateLegacyFileIfNeeded() {
        let manager = FileManager.default
        guard fileURL != legacyFileURL else { return }
        guard !manager.fileExists(atPath: fileURL.path),
              manager.fileExists(atPath: legacyFileURL.path) else { return }
        // 用 copy 不用 move，万一出问题旧数据还在
        try? manager.copyItem(at: legacyFileURL, to: fileURL)
    }

    func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([PickupItem].self, from: data)
        else {
            items = []
            return
        }
        items = sorted(decoded)
        Notifier.rescheduleAll(items)
    }

    /// 同一个取件码重复推送时不重复添加
    @discardableResult
    func add(
        code: String,
        stationName: String,
        source: PickupSource,
        rawText: String,
        expireAt: Date?,
        expireIsEstimated: Bool
    ) -> PickupItem {
        if let existing = items.first(where: { $0.code == code && !$0.isPicked }) {
            return existing
        }

        var item = PickupItem(code: code, stationName: stationName, source: source, rawText: rawText)
        item.expireAt = expireAt
        item.expireIsEstimated = expireIsEstimated

        items.insert(item, at: 0)
        items = sorted(items)
        save()
        Notifier.scheduleExpiryReminder(for: item)
        return item
    }

    func togglePicked(_ item: PickupItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].isPicked.toggle()
        let updated = items[index]

        if updated.isPicked {
            Notifier.cancelExpiryReminder(for: updated)
        } else {
            Notifier.scheduleExpiryReminder(for: updated)
        }

        items = sorted(items)
        save()
    }

    func remove(_ item: PickupItem) {
        Notifier.cancelExpiryReminder(for: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.compactMap { items.indices.contains($0) ? items[$0] : nil }
        removed.forEach { Notifier.cancelExpiryReminder(for: $0) }

        for index in offsets.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
        save()
    }

    // MARK: - 备份

    /// 备份内容就是 pickups.json 本身，导出的文件也能直接当数据文件用
    func backupData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(items)) ?? Data()
    }

    /// 合并导入：同一个 id 以本地为准（避免把“已取”状态覆盖回去），
    /// 但本地缺到期时间的，用备份里的补上。返回新增条数。
    @discardableResult
    func merge(_ data: Data) throws -> Int {
        let incoming = try JSONDecoder().decode([PickupItem].self, from: data)

        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var added = 0

        for item in incoming {
            if var existing = byID[item.id] {
                if existing.expireAt == nil, let expire = item.expireAt {
                    existing.expireAt = expire
                    existing.expireIsEstimated = item.expireIsEstimated
                    byID[item.id] = existing
                }
            } else {
                byID[item.id] = item
                added += 1
            }
        }

        items = sorted(Array(byID.values))
        save()
        Notifier.rescheduleAll(items)
        return added
    }

    /// 未取的排前面；都有到期时间就按最早到期排
    private func sorted(_ list: [PickupItem]) -> [PickupItem] {
        list.sorted { lhs, rhs in
            if lhs.isPicked != rhs.isPicked { return !lhs.isPicked }

            let left = lhs.expireAt ?? .distantFuture
            let right = rhs.expireAt ?? .distantFuture
            if left != right { return left < right }

            return lhs.receivedAt > rhs.receivedAt
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)

        // 数据一变就让小组件立刻重读，不用等它的 30 分钟时间线
        refreshWidget()
    }

    /// 主动请求小组件重新加载。App Intent 在后台写入数据后，这一句是关键。
    func refreshWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
}
