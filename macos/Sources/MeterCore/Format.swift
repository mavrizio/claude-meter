import Foundation

public enum MeterFormat {
    /// "3g 4h", "2h 14m", "14m", "<1m", "ora". `compact` drops the spaces ("2h14m").
    public static func remaining(_ seconds: Int, compact: Bool = false) -> String {
        let sp = compact ? "" : " "
        if seconds <= 0 { return "ora" }
        if seconds >= 86400 { return "\(seconds / 86400)g\(sp)\(seconds % 86400 / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h\(sp)" + String(format: "%02dm", seconds % 3600 / 60) }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "<1m"
    }

    /// The line Claude Code shows under the prompt (ANSI colours).
    public static func statusLine(_ s: UsageState, now: Date) -> String {
        func color(_ pct: Double) -> String { pct < 50 ? "\u{1B}[32m" : pct < 80 ? "\u{1B}[33m" : "\u{1B}[31m" }
        let dim = "\u{1B}[2m", reset = "\u{1B}[0m"
        var parts: [String] = []
        if let m = s.model { parts.append("\(dim)\(m)\(reset)") }
        for (w, label) in [(s.fiveHour, "5h"), (s.sevenDay, "7d")] {
            guard let w else { continue }
            let rem = remaining(w.remaining(at: now), compact: true)
            parts.append("\(label) \(color(w.pct))\(Int(w.pct.rounded()))%\(reset) \(dim)\(rem)\(reset)")
        }
        if let c = s.contextPct { parts.append("ctx \(Int(c.rounded()))%") }
        return parts.joined(separator: "  ")
    }
}
