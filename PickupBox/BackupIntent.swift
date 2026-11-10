import AppIntents
import Foundation
import UniformTypeIdentifiers

/// 把当前取件记录导出成 JSON 文件，交给快捷指令去保存。
/// 配合「快捷指令 → 自动化 → 每天定时」就能实现全自动备份。
struct BackupPickupsIntent: AppIntent {
    static let title: LocalizedStringResource = "取件夹备份"
    static let description = IntentDescription("生成一份取件记录的 JSON 备份文件，供快捷指令保存")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let data = PickupStore.shared.backupData()
        let file = IntentFile(data: data, filename: backupFileName(), type: .json)
        return .result(value: file, dialog: "已生成备份，共 \(PickupStore.shared.items.count) 条")
    }

    private func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "PickupBox-backup-\(formatter.string(from: .now)).json"
    }
}
