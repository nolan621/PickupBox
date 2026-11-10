import Foundation

struct ParsedPickup: Equatable, Sendable {
    var code: String
    var stationName: String
    var source: PickupSource
}

/// 从短信原文里提取「取件码 + 取件点 + 到期时间」。
/// 遇到没见过的文案，往对应的正则/后缀数组里加一条就行。
enum PickupParser {

    /// “取件码”前面常见的引导词
    private static let keywords = ["取件码", "取货码", "提货码", "取件号", "取件密码", "凭码"]

    /// 取件码可能的形状，按优先级从具体到宽泛
    private static let codePatterns = [
        // 字母打头的分段码：F-2-44646、A-12、D-123
        "(?<![0-9A-Za-z])([A-Za-z](?:[-－]\\d{1,5}){1,3})(?![0-9A-Za-z])",
        // 货架式：1-2-34、1-1-1111
        "(?<![0-9A-Za-z])(\\d{1,2}[-－]\\d{1,2}[-－]\\d{1,4})(?![0-9A-Za-z])",
        // 字母开头：D-123、A12
        "(?<![0-9A-Za-z])([A-Za-z][-－]?\\d{2,4})(?![0-9A-Za-z])",
        // 纯数字：4~8 位，前后断言用来排除手机号和运单号
        "(?<![0-9])(\\d{4,8})(?![0-9])"
    ]

    /// 取件点名称的结尾词。越长的放前面，同一位置时优先匹配更长的。
    private static let stationSuffixes = [
        "丰巢智能柜", "丰巢柜", "丰巢", "智能柜", "快递柜",
        "菜鸟驿站", "驿站", "快递超市",
        "兔喜生活超市", "兔喜生活", "兔喜", "蜜罐智能柜", "蜜罐",
        "服务站", "服务点", "代收点"
    ]

    /// 名称前面的定位词，从最后一个往后截，剩下的就是地点名
    private static let stationBoundaries = [
        "已存放至", "已放至", "已放入", "已送达", "已到达", "已送到", "已送至",
        "存放至", "放至", "放入", "送达", "到达", "送到", "送至", "已到", "至", "到"
    ]

    // MARK: - 入口

    static func parse(_ text: String) -> ParsedPickup? {
        let normalized = text.replacingOccurrences(of: "\u{3000}", with: " ")
        guard let code = extractCode(from: normalized) else { return nil }
        let source = detectSource(in: normalized)
        let station = extractStation(from: normalized) ?? defaultStation(for: source)
        return ParsedPickup(code: code, stationName: station, source: source)
    }

    // MARK: - 取件码

    static func extractCode(from text: String) -> String? {
        let nsText = text as NSString

        for keyword in keywords {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.length > 0 {
                let found = nsText.range(of: keyword, options: [], range: searchRange)
                if found.location == NSNotFound { break }

                let tailStart = found.upperBound
                let tailLength = min(30, nsText.length - tailStart)
                if tailLength > 0 {
                    let tail = nsText.substring(with: NSRange(location: tailStart, length: tailLength))
                    if let code = firstCode(in: tail) { return code }
                }

                let nextStart = found.upperBound
                searchRange = NSRange(location: nextStart, length: nsText.length - nextStart)
            }
        }
        return nil
    }

    private static func firstCode(in tail: String) -> String? {
        let nsTail = tail as NSString
        let range = NSRange(location: 0, length: nsTail.length)

        for pattern in codePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: tail, options: [], range: range) else { continue }

            let raw = nsTail.substring(with: match.range(at: 1))
            let code = raw
                .replacingOccurrences(of: "－", with: "-")
                .trimmingCharacters(in: .whitespaces)
            if !code.isEmpty { return code }
        }
        return nil
    }

    // MARK: - 取件点

    static func detectSource(in text: String) -> PickupSource {
        if text.contains("丰巢") { return .fengchao }
        if text.contains("驿站") || text.contains("兔喜") || text.contains("蜜罐")
            || text.contains("快递超市") || text.contains("服务站")
            || text.contains("服务点") || text.contains("代收点") {
            return .station
        }
        if text.contains("智能柜") || text.contains("快递柜") { return .fengchao }
        return .unknown
    }

    static func extractStation(from text: String) -> String? {
        let body = stripSignature(from: text)
        let nsBody = body as NSString
        guard nsBody.length > 0 else { return nil }

        // 找到最早出现的取件点后缀；同一位置取更长的那个
        var hitLocation = NSNotFound
        var hitSuffix = ""
        for suffix in stationSuffixes {
            let found = nsBody.range(of: suffix)
            guard found.location != NSNotFound else { continue }

            if hitLocation == NSNotFound
                || found.location < hitLocation
                || (found.location == hitLocation && suffix.count > hitSuffix.count) {
                hitLocation = found.location
                hitSuffix = suffix
            }
        }
        guard hitLocation != NSNotFound else { return nil }

        // 向前回看最多 20 个字，再从最后一个定位词往后截
        let windowStart = max(0, hitLocation - 20)
        let windowEnd = hitLocation + (hitSuffix as NSString).length
        let window = nsBody.substring(with: NSRange(location: windowStart, length: windowEnd - windowStart))

        let name = trimAtLastBoundary(window)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? nil : name
    }

    /// 从最后一个定位词（至/到/送达/存放至…）之后开始截取
    private static func trimAtLastBoundary(_ text: String) -> String {
        let nsText = text as NSString
        var cut = 0

        for marker in stationBoundaries {
            let found = nsText.range(of: marker, options: .backwards)
            guard found.location != NSNotFound else { continue }
            cut = max(cut, found.location + found.length)
        }

        guard cut > 0, cut < nsText.length else { return text }
        return nsText.substring(from: cut)
    }

    /// 去掉短信开头的【丰巢】【菜鸟驿站】这类签名，否则会被当成取件点名称
    private static func stripSignature(from text: String) -> String {
        text.replacingOccurrences(of: "【[^】]*】", with: "", options: .regularExpression)
    }

    private static func defaultStation(for source: PickupSource) -> String {
        switch source {
        case .fengchao:
            return "丰巢智能柜"
        case .station:
            return "驿站"
        case .unknown:
            return "未知取件点"
        }
    }

    // MARK: - 到期时间

    /// 解析短信里写的取件时限。解析不出来就按来源估算，并把 estimated 标记为 true。
    static func parseExpiry(
        in text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (date: Date, estimated: Bool) {
        let normalized = normalizeDigits(text)

        // 48小时内 / 24 小时之内
        if let hours = firstInt(in: normalized, pattern: "(\\d{1,3})\\s*个?小时") {
            return (now.addingTimeInterval(Double(hours) * 3600), false)
        }

        // 3天内 / 3日内
        if let days = firstInt(in: normalized, pattern: "(\\d{1,2})\\s*[天日]内") {
            return (now.addingTimeInterval(Double(days) * 86400), false)
        }

        // 11月13日（默认按当天 23:59 算）
        if let (month, day) = monthDay(in: normalized) {
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = month
            comps.day = day
            comps.hour = 23
            comps.minute = 59

            if let date = calendar.date(from: comps) {
                // 跨年的情况，例如 12 月的短信里写 1 月
                if date < now.addingTimeInterval(-86400 * 31),
                   let nextYear = calendar.date(byAdding: .year, value: 1, to: date) {
                    return (nextYear, false)
                }
                return (date, false)
            }
        }

        // 今日18点前 / 明天10点
        if let (dayOffset, hour, minute) = dayTime(in: normalized) {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            if let base = calendar.date(from: comps),
               let date = calendar.date(byAdding: .day, value: dayOffset, to: base) {
                return (date, false)
            }
        }

        return defaultExpiry(for: detectSource(in: text), now: now)
    }

    /// 短信里完全没提时限时的兜底值。数字可以按你的实际情况改。
    private static func defaultExpiry(for source: PickupSource, now: Date) -> (Date, Bool) {
        let hours: Double
        switch source {
        case .fengchao:
            hours = 18      // 丰巢一般 18 小时左右开始计费
        case .station:
            hours = 72      // 驿站一般 3 天
        case .unknown:
            hours = 48
        }
        return (now.addingTimeInterval(hours * 3600), true)
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }

    private static func monthDay(in text: String) -> (Int, Int)? {
        let pattern = "(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let month = Int(ns.substring(with: match.range(at: 1))),
              let day = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return (month, day)
    }

    private static func dayTime(in text: String) -> (Int, Int, Int)? {
        let pattern = "(今日|今天|明日|明天|后天)\\s*(\\d{1,2})\\s*[点时]\\s*(\\d{1,2})?\\s*分?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }

        let word = ns.substring(with: match.range(at: 1))
        guard let hour = Int(ns.substring(with: match.range(at: 2))) else { return nil }

        var minute = 0
        if match.range(at: 3).location != NSNotFound,
           let value = Int(ns.substring(with: match.range(at: 3))) {
            minute = value
        }

        let offset: Int
        switch word {
        case "今日", "今天": offset = 0
        case "明日", "明天": offset = 1
        default: offset = 2
        }
        return (offset, hour, minute)
    }

    /// 全角数字转半角，短信里偶尔会出现
    private static func normalizeDigits(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if let scalar = character.unicodeScalars.first,
               scalar.value >= 0xFF10, scalar.value <= 0xFF19,
               let ascii = UnicodeScalar(scalar.value - 0xFF10 + 0x30) {
                result.unicodeScalars.append(ascii)
            } else {
                result.append(character)
            }
        }
        return result
    }
}
