import Foundation

/// 小组件只关心展示用的几个字段，其余字段解码时自动忽略。
/// 这样它和主 App 共用同一份 pickups.json，却不需要共享类型定义。
struct WidgetPickup: Decodable, Identifiable {
    let id: UUID
    let code: String
    let stationName: String
    let expireAt: Date?
    let isPicked: Bool

    init(id: UUID, code: String, stationName: String, expireAt: Date?, isPicked: Bool) {
        self.id = id
        self.code = code
        self.stationName = stationName
        self.expireAt = expireAt
        self.isPicked = isPicked
    }
}

enum WidgetStore {
    static let appGroupID = "group.io.github.nolan621.PickupBox"

    /// 读出所有还没取的包裹，最急的排最前
    static func loadActive() -> [WidgetPickup] {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return []
        }

        let url = base.appendingPathComponent("pickups.json")
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WidgetPickup].self, from: data) else {
            return []
        }

        return items
            .filter { !$0.isPicked }
            .sorted { ($0.expireAt ?? .distantFuture) < ($1.expireAt ?? .distantFuture) }
    }
}
