import Foundation

/// 取件点类型
enum PickupSource: String, Codable, CaseIterable, Sendable {
    case fengchao
    case station
    case unknown

    var displayName: String {
        switch self {
        case .fengchao:
            return "丰巢"
        case .station:
            return "驿站"
        case .unknown:
            return "其他"
        }
    }
}

/// 一条待取件记录
struct PickupItem: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var code: String
    var stationName: String
    var source: PickupSource
    var rawText: String
    var receivedAt: Date = .now
    var isPicked: Bool = false

    /// 到期时间。nil 表示不知道（比如老数据）
    var expireAt: Date?
    /// true 表示这是按来源估算的兜底时间，不是短信里写的
    var expireIsEstimated: Bool = false
}

extension PickupItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, code, stationName, source, rawText, receivedAt, isPicked, expireAt, expireIsEstimated
    }

    /// 手写解码，是为了兼容没有 expireAt 字段的旧数据
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        stationName = try c.decode(String.self, forKey: .stationName)
        source = try c.decodeIfPresent(PickupSource.self, forKey: .source) ?? .unknown
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText) ?? ""
        receivedAt = try c.decodeIfPresent(Date.self, forKey: .receivedAt) ?? .now
        isPicked = try c.decodeIfPresent(Bool.self, forKey: .isPicked) ?? false
        expireAt = try c.decodeIfPresent(Date.self, forKey: .expireAt)
        expireIsEstimated = try c.decodeIfPresent(Bool.self, forKey: .expireIsEstimated) ?? false
    }
}

extension PickupItem {
    var isExpired: Bool {
        guard !isPicked, let expireAt else { return false }
        return expireAt <= .now
    }

    /// 纯文本的剩余时间，通知里用
    func remainingDescription(now: Date = .now) -> String {
        if isPicked { return "已取" }
        guard let expireAt else { return "无期限" }
        let seconds = expireAt.timeIntervalSince(now)
        if seconds <= 0 { return "已超时" }
        let hours = seconds / 3600
        if hours >= 24 { return "剩 \(Int(hours / 24)) 天" }
        if hours >= 1 { return "剩 \(Int(hours)) 小时" }
        return "剩 \(max(1, Int(seconds / 60))) 分钟"
    }
}
