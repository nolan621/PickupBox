import AppIntents
import Foundation

/// 快捷指令调用的入口：把短信原文传进来，解析、保存、发通知。
/// `openAppWhenRun = false` 表示后台静默执行，不会把你从别的 App 里拽出来。
struct AddPickupIntent: AppIntent {
    static let title: LocalizedStringResource = "添加取件码"
    static let description = IntentDescription("从短信内容中提取取件码，保存到取件夹")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "短信内容", description: "把整条短信原文传进来就行")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("从 \(\.$text) 提取取件码")
    }

    // 整个 perform 都跑在主线程上：解析是纯计算，存储和通知本来也都要求主线程。
    // 这样正文里直接写同步代码，不用到处 await MainActor.run。
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let parsed = PickupParser.parse(text) else {
            return .result(dialog: "没识别出取件码")
        }

        let expiry = PickupParser.parseExpiry(in: text)

        let item = PickupStore.shared.add(
            code: parsed.code,
            stationName: parsed.stationName,
            source: parsed.source,
            rawText: text,
            expireAt: expiry.date,
            expireIsEstimated: expiry.estimated
        )

        Notifier.post(title: "取件码 \(parsed.code)", body: item.stationName)

        let suffix = expiry.estimated ? "（时限为估算）" : ""
        return .result(dialog: "已保存：\(parsed.code) · \(item.remainingDescription())\(suffix)")
    }
}
