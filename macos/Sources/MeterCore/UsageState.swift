import Foundation

public enum MeterPaths {
    /// Honours $HOME like the Python tools do (homeDirectoryForCurrentUser ignores it), so tests and
    /// tools can point everything at a scratch folder.
    public static var home: URL {
        if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty { return URL(fileURLWithPath: h) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    public static var stateDir: URL { home.appendingPathComponent(".claude-meter") }
    public static var stateFile: URL { stateDir.appendingPathComponent("state.json") }
    public static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
}

/// One rate-limit window (5-hour session or 7-day week).
public struct UsageWindow: Codable, Equatable, Sendable {
    public var pct: Double      // 0...100
    public var resetsAt: Int    // unix epoch seconds

    enum CodingKeys: String, CodingKey {
        case pct
        case resetsAt = "resets_at"
    }

    public init(pct: Double, resetsAt: Int) {
        self.pct = pct
        self.resetsAt = resetsAt
    }

    public func remaining(at now: Date) -> Int { resetsAt - Int(now.timeIntervalSince1970) }
    public func isValid(at now: Date) -> Bool { remaining(at: now) > 0 }

    /// Fraction of the window already elapsed (0...1): where usage "should" be at an even pace.
    public func pace(at now: Date, windowLength: Int) -> Double {
        let f = 1 - Double(remaining(at: now)) / Double(windowLength)
        return min(max(f, 0), 1)
    }

    public static let fiveHourLength = 5 * 3600
    public static let sevenDayLength = 7 * 86400
}

/// What we know about Claude usage. Same JSON layout as host/statusline.py writes,
/// so the Python tools and the app can share ~/.claude-meter/state.json.
public struct UsageState: Codable, Equatable, Sendable {
    public var updatedAt: Double
    public var sessionId: String?
    public var model: String?
    public var contextPct: Double?
    public var costUsd: Double?
    public var linesAdded: Int?
    public var linesRemoved: Int?
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case sessionId = "session_id"
        case model
        case contextPct = "context_pct"
        case costUsd = "cost_usd"
        case linesAdded = "lines_added"
        case linesRemoved = "lines_removed"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    public init(updatedAt: Double, sessionId: String? = nil, model: String? = nil, contextPct: Double? = nil,
                costUsd: Double? = nil, linesAdded: Int? = nil, linesRemoved: Int? = nil,
                fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil) {
        self.updatedAt = updatedAt
        self.sessionId = sessionId
        self.model = model
        self.contextPct = contextPct
        self.costUsd = costUsd
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }

    // MARK: persistence

    public static func load(from url: URL = MeterPaths.stateFile) -> UsageState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageState.self, from: data)
    }

    public func save(to url: URL = MeterPaths.stateFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    // MARK: from Claude Code's statusLine payload

    /// Builds the state from the JSON Claude Code pipes to the statusLine command.
    /// Rate limits are account-wide, and a fresh session reports none until its first API
    /// response: in that case the previous windows are kept while still valid.
    public static func from(payload p: [String: Any], previous: UsageState?, now: Date) -> UsageState {
        let rl = p["rate_limits"] as? [String: Any]
        let cost = p["cost"] as? [String: Any] ?? [:]
        let ctx = p["context_window"] as? [String: Any] ?? [:]
        let model = p["model"] as? [String: Any]

        var s = UsageState(
            updatedAt: now.timeIntervalSince1970,
            sessionId: p["session_id"] as? String,
            model: model?["display_name"] as? String,
            contextPct: number(ctx["used_percentage"]),
            costUsd: number(cost["total_cost_usd"]),
            linesAdded: number(cost["total_lines_added"]).map { Int($0) },
            linesRemoved: number(cost["total_lines_removed"]).map { Int($0) },
            fiveHour: window(rl, "five_hour"),
            sevenDay: window(rl, "seven_day"))

        if s.fiveHour == nil, let old = previous?.fiveHour, old.isValid(at: now) { s.fiveHour = old }
        if s.sevenDay == nil, let old = previous?.sevenDay, old.isValid(at: now) { s.sevenDay = old }
        return s
    }

    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    static func window(_ rl: [String: Any]?, _ key: String) -> UsageWindow? {
        guard let w = rl?[key] as? [String: Any],
              let p = number(w["used_percentage"]),
              let r = number(w["resets_at"]) else { return nil }
        return UsageWindow(pct: p, resetsAt: Int(r))
    }
}
