import SwiftUI
import WidgetKit

struct PickupEntry: TimelineEntry {
    let date: Date
    let items: [WidgetPickup]

    var urgent: WidgetPickup? { items.first }
}

extension PickupEntry {
    static let sample = PickupEntry(
        date: .now,
        items: [
            WidgetPickup(
                id: UUID(),
                code: "1-2-34",
                stationName: "阳光小区东门菜鸟驿站",
                expireAt: .now.addingTimeInterval(5 * 3600),
                isPicked: false
            ),
            WidgetPickup(
                id: UUID(),
                code: "D-123",
                stationName: "朝阳路丰巢智能柜",
                expireAt: .now.addingTimeInterval(20 * 3600),
                isPicked: false
            ),
        ]
    )

    static let empty = PickupEntry(date: .now, items: [])

    /// 待取件数量
    var count: Int { items.count }

    /// 只让数字承担紧急程度：最急的那一条决定颜色
    var urgencyTint: Color {
        guard let expireAt = items.first?.expireAt else { return .secondary }
        let remaining = expireAt.timeIntervalSinceNow
        if remaining <= 0 { return .red }
        if remaining >= 12 * 3600 { return .green }
        if remaining >= 2 * 3600 { return .orange }
        return .red
    }

    /// 去重后的取件点列表，按紧急程度排序
    var stationList: String {
        var seen = Set<String>()
        let unique = items
            .map(\.stationName)
            .filter { seen.insert($0).inserted }
        return unique.joined(separator: "、")
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PickupEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (PickupEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(PickupEntry(date: .now, items: WidgetStore.loadActive()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PickupEntry>) -> Void) {
        let items = WidgetStore.loadActive()
        let entry = PickupEntry(date: .now, items: items)

        // 常规 30 分钟刷一次；如果最近一条快到期了，就在到期后立刻再刷一次
        var next = Date().addingTimeInterval(30 * 60)
        if let expiry = items.first?.expireAt, expiry > .now {
            next = min(next, expiry.addingTimeInterval(60))
        }

        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 视图

struct PickupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PickupEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenView(entry: entry)
        case .systemMedium:
            MediumView(entry: entry)
        default:
            SmallView(entry: entry)
        }
    }
}

struct SmallView: View {
    let entry: PickupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                    .font(.caption2)
                Text("待取")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.count)")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.urgencyTint)
                Text("件")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if entry.count == 0 {
                Text("暂无待取")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(entry.stationList)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumView: View {
    let entry: PickupEntry

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption2)
                    Text("待取")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(entry.count)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.urgencyTint)
                    Text("件")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
            }

            VStack(alignment: .leading, spacing: 7) {
                if entry.count == 0 {
                    Text("暂无待取")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entry.items.prefix(3)) { item in
                        Text(item.stationName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct LockScreenView: View {
    let entry: PickupEntry

    var body: some View {
        HStack(spacing: 10) {
            Text("\(entry.count)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(entry.urgencyTint)

            VStack(alignment: .leading, spacing: 2) {
                Text("件待取")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if entry.count == 0 {
                    Text("暂无待取")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.stationList)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 组件声明

struct PickupWidget: Widget {
    let kind = "PickupWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PickupWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("待取件数")
        .description("显示还有几件快递待取、分别在哪里。数字颜色代表最急一件的紧急程度。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
