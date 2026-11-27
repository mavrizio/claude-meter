import Foundation

/// One NDJSON line for the display firmware (see CLAUDE.md, "Protocollo seriale").
public struct DeviceMessage: Equatable, Sendable {
    /// Full line including the trailing newline.
    public let line: String
    /// Content without the time-varying fields (now, age): used to send only on change.
    public let key: String

    public static func build(state: UsageState?, now: Date,
                             tzOffset: Int = TimeZone.current.secondsFromGMT()) -> DeviceMessage {
        var content = ["\"ok\":\(state != nil)"]
        if let s = state {
            if let w = s.fiveHour, w.isValid(at: now) { content.append("\"fh\":[\(f1(w.pct)),\(w.resetsAt)]") }
            if let w = s.sevenDay, w.isValid(at: now) { content.append("\"sd\":[\(f1(w.pct)),\(w.resetsAt)]") }
            if let c = s.contextPct { content.append("\"ctx\":\(Int(c.rounded()))") }
            if let c = s.costUsd { content.append("\"cost\":" + String(format: "%.2f", c)) }
            if let la = s.linesAdded {
                content.append("\"la\":\(la)")
                content.append("\"lr\":\(s.linesRemoved ?? 0)")
            }
            if let m = s.model, !m.isEmpty { content.append("\"m\":" + jsonString(String(m.prefix(20)))) }
        }
        let key = content.joined(separator: ",")
        let epoch = Int(now.timeIntervalSince1970)
        var all = ["\"t\":\"u\"", "\"now\":\(epoch)", "\"tz\":\(tzOffset)"] + content
        if let s = state { all.append("\"age\":\(max(0, epoch - Int(s.updatedAt)))") }
        return DeviceMessage(line: "{" + all.joined(separator: ",") + "}\n", key: key)
    }

    static func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]),
              let arr = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(arr.dropFirst().dropLast()) // strip [ ]
    }
}
