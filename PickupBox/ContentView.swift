import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = PickupStore.shared
    @State private var location = LocationService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var exportDocument = PickupBackupDocument()
    @State private var alertText = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.items) { item in
                    PickupRow(item: item, hasSpot: location.spot(for: item.stationName) != nil) {
                        // 点按只会「标记已取」，已取的记录点按无效，
                        // 避免误触把已取的又变回未取。
                        if !item.isPicked {
                            store.togglePicked(item)
                        }
                    }
                    .contextMenu {
                        Button {
                            remember(item.stationName)
                        } label: {
                            Label("记住这个位置", systemImage: "mappin.and.ellipse")
                        }

                        if location.spot(for: item.stationName) != nil {
                            Button(role: .destructive) {
                                location.removeSpot(for: item.stationName)
                                show("已移除这个取件点")
                            } label: {
                                Label("移除取件点", systemImage: "mappin.slash")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.remove(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }

                        if item.isPicked {
                            Button {
                                store.togglePicked(item)
                            } label: {
                                Label("撤销标记", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("取件夹")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            prepareExport()
                        } label: {
                            Label("导出备份", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            isImporting = true
                        } label: {
                            Label("导入备份", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if store.items.isEmpty {
                    ContentUnavailableView(
                        "还没有取件码",
                        systemImage: "shippingbox",
                        description: Text("收到取件短信后会自动出现在这里")
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    store.load()
                }
            }
            .task {
                Notifier.requestAuthorization()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFileName()
            ) { result in
                switch result {
                case .success:
                    show("已导出")
                case .failure(let error):
                    show("导出失败：\(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .alert("提示", isPresented: $showAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(alertText)
            }
        }
    }

    private func prepareExport() {
        guard !store.items.isEmpty else {
            show("还没有数据可以导出")
            return
        }
        exportDocument = PickupBackupDocument(data: store.backupData())
        isExporting = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                let added = try store.merge(data)
                show("导入成功：新增 \(added) 条，现在共 \(store.items.count) 条")
            } catch {
                show("导入失败：这个文件不是有效的备份")
            }

        case .failure(let error):
            show("导入取消：\(error.localizedDescription)")
        }
    }

    private func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "PickupBox-backup-\(formatter.string(from: .now))"
    }

    private func remember(_ name: String) {
        Task {
            if let message = await location.captureCurrentLocation(for: name) {
                show(message)
            } else {
                show("已记住「\(name)」的位置，以后走到附近会提醒你")
            }
        }
    }

    private func show(_ text: String) {
        alertText = text
        showAlert = true
    }
}

struct PickupRow: View {
    let item: PickupItem
    var hasSpot: Bool = false
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.code)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .strikethrough(item.isPicked)
                        .foregroundStyle(item.isPicked ? Color.secondary : Color.primary)

                    Text(item.stationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                trailingStatus
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .opacity(item.isPicked ? 0.55 : 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(item.source.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())

            if hasSpot {
                Image(systemName: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Text(item.receivedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if item.isPicked {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        } else if let expireAt = item.expireAt {
            CountdownView(expireAt: expireAt, isEstimated: item.expireIsEstimated)
        }
    }
}

/// 右上角的倒计时。用 TimelineView 定时重算颜色，
/// 数字本身由 Text(timerInterval:) 自己每秒刷新。
struct CountdownView: View {
    let expireAt: Date
    let isEstimated: Bool

    /// 分档阈值，想改节奏就动这两个数
    private let safeThreshold: TimeInterval = 12 * 3600    // 12 小时以上：绿
    private let warnThreshold: TimeInterval = 2 * 3600     // 2 小时以上：橙，以下：红

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let remaining = expireAt.timeIntervalSince(context.date)

            VStack(alignment: .trailing, spacing: 3) {
                Text(label(for: remaining))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint(for: remaining).opacity(0.85))

                if remaining > 0 {
                    Text(timerInterval: min(context.date, expireAt)...expireAt, countsDown: true)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint(for: remaining))
                } else {
                    Text("已超时")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if isEstimated, remaining > 0 {
                    Text("估算")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func label(for remaining: TimeInterval) -> String {
        if remaining <= 0 { return "已过期" }
        if remaining < warnThreshold { return "紧急" }
        return "剩余"
    }

    private func tint(for remaining: TimeInterval) -> Color {
        if remaining <= 0 { return .secondary }
        if remaining >= safeThreshold { return .green }
        if remaining >= warnThreshold { return .orange }
        return .red
    }
}

#Preview {
    ContentView()
}
