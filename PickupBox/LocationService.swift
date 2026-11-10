import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    private(set) var spots: [PickupSpot] = []
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<CLLocation, Error>?
    private let maxRegionCount = 20

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("spots.json")
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        loadSpots()
        registerAllSpots()
    }

    // MARK: - 查询

    func spot(for name: String) -> PickupSpot? {
        spots.first { $0.name == name }
    }

    // MARK: - 记录取件点

    /// 把当前位置记成这个取件点。返回 nil 表示成功，否则是要显示给用户的提示。
    func captureCurrentLocation(for name: String) async -> String? {
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return "已弹出定位权限请求，允许之后再点一次"

        case .denied, .restricted:
            return "定位权限被拒绝，去 设置 → 隐私与安全性 → 定位服务 打开"

        case .authorizedWhenInUse, .authorizedAlways:
            break

        @unknown default:
            return "定位状态异常"
        }

        do {
            let location = try await currentLocation()
            upsert(
                PickupSpot(
                    name: name,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            )

            // 想做到“App 没打开也能提醒”，需要 Always 权限
            if status == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            return nil
        } catch {
            return "拿不到当前位置，去空旷一点的地方再试"
        }
    }

    func removeSpot(for name: String) {
        guard let index = spots.firstIndex(where: { $0.name == name }) else { return }
        let spot = spots[index]
        manager.stopMonitoring(for: region(for: spot))
        spots.remove(at: index)
        saveSpots()
    }

    // MARK: - 内部

    private func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            pendingLocation = continuation
            manager.requestLocation()
        }
    }

    private func upsert(_ spot: PickupSpot) {
        if let index = spots.firstIndex(where: { $0.name == spot.name }) {
            var updated = spot
            updated.id = spots[index].id
            spots[index] = updated
        } else {
            spots.append(spot)
        }
        saveSpots()
        registerAllSpots()
    }

    private func region(for spot: PickupSpot) -> CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
            radius: spot.radius,
            identifier: spot.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        return region
    }

    private func registerAllSpots() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for spot in spots.prefix(maxRegionCount) {
            manager.startMonitoring(for: region(for: spot))
        }
    }

    /// 进入某个取件点：把最急的一条取件码弹出来
    private func handleEnter(region: CLRegion) {
        guard let spot = spots.first(where: { $0.id.uuidString == region.identifier }) else { return }

        let pending = PickupStore.shared.items.filter { !$0.isPicked && $0.stationName == spot.name }
        guard let urgent = pending.min(by: { ($0.expireAt ?? .distantFuture) < ($1.expireAt ?? .distantFuture) }) else {
            return
        }

        let extra = pending.count > 1 ? "，共 \(pending.count) 件待取" : ""
        Notifier.post(title: "到取件点了：\(urgent.code)", body: "\(spot.name)\(extra)")
    }

    private func loadSpots() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([PickupSpot].self, from: data)
        else {
            spots = []
            return
        }
        spots = decoded
    }

    private func saveSpots() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(spots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways {
            registerAllSpots()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        pendingLocation?.resume(returning: location)
        pendingLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        pendingLocation?.resume(throwing: error)
        pendingLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleEnter(region: region)
    }
}
