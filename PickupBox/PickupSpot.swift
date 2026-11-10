import Foundation

/// 一个取件点的地理位置。第一次站在柜机前记一次，以后就不用管了。
struct PickupSpot: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    /// 触发半径（米）。太大容易在家就误触发，150 米是个折中值。
    var radius: Double = 150
    var createdAt: Date = .now
}
