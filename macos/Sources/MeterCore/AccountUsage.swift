import Foundation

// Optional, experimental data source: the account-wide usage that Claude Code's `/usage` and
// claude.ai's Usage page show. It comes from an undocumented Anthropic endpoint, authenticated with
// Claude Code's own OAuth token, and it includes chat/Desktop/phone usage that the statusLine never
// sees. Off by default; the user opts in from the panel.
//
// Rules (see CLAUDE.md): read the token, never refresh it (refreshing rotates it and would log
// Claude Code out), never log or store it, send it only to api.anthropic.com.

/// Limits fetched from the account.
public struct AccountUsage: Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var fetchedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fetchedAt = fetchedAt
    }

    /// `{"five_hour":{"utilization":44.0,"resets_at":"2026-11-27T20:00:00.050625+00:00",...},"seven_day":{...},...}`
    /// A window with no reset time (nothing used yet) is reported as absent, like the statusLine does.
    public static func parse(_ data: Data, fetchedAt: Date) throws -> AccountUsage {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AccountUsageError.badResponse
        }
        return AccountUsage(fiveHour: window(obj["five_hour"]), sevenDay: window(obj["seven_day"]),
                            fetchedAt: fetchedAt)
    }

    static func window(_ v: Any?) -> UsageWindow? {
        guard let w = v as? [String: Any],
              let pct = UsageState.number(w["utilization"]),
              let s = w["resets_at"] as? String,
              let reset = parseDate(s) else { return nil }
        return UsageWindow(pct: pct, resetsAt: Int(reset.timeIntervalSince1970.rounded()))
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

public enum AccountUsageError: Error, Equatable {
    case noCredentials     // Claude Code is not installed or not logged in
    case tokenExpired      // Claude Code refreshes it next time it runs
    case unauthorized      // 401/403
    case rateLimited       // 429
    case http(Int)
    case network(String)
    case badResponse

    /// Short Italian text for the panel.
    public var message: String {
        switch self {
        case .noCredentials: return "Claude Code non risulta collegato a un account su questo Mac."
        case .tokenExpired: return "Accesso di Claude Code scaduto: si rinnova la prossima volta che usi Claude Code."
        case .unauthorized: return "Accesso rifiutato: apri Claude Code per rinnovarlo."
        case .rateLimited: return "Troppe richieste: riprovo fra qualche minuto."
        case let .http(code): return "Il servizio ha risposto con errore \(code)."
        case .network: return "Servizio non raggiungibile (rete?)."
        case .badResponse: return "Risposta inattesa: il servizio potrebbe essere cambiato."
        }
    }
}

/// Claude Code's OAuth access token, as stored in the login keychain.
public struct ClaudeCodeToken: Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public func isUsable(at now: Date) -> Bool {
        guard let e = expiresAt else { return true }
        return e.timeIntervalSince(now) > 60
    }

    /// `{"claudeAiOauth":{"accessToken":"…","expiresAt":<ms>,…}}`
    public static func parse(_ data: Data) -> ClaudeCodeToken? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let o = obj["claudeAiOauth"] as? [String: Any],
              let t = o["accessToken"] as? String, !t.isEmpty else { return nil }
        let exp = UsageState.number(o["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCodeToken(accessToken: t, expiresAt: exp)
    }

    /// Reads the keychain item through /usr/bin/security, the same tool Claude Code uses to write it:
    /// the item's access list already trusts it, so there is no keychain prompt, and the grant does
    /// not get lost each time Claude Code rewrites the item with a refreshed token.
    public static func readFromKeychain() -> ClaudeCodeToken? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return parse(data)
    }
}

public enum AccountUsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// One request. Blocking parts (keychain) run on the caller's thread: call it off the main thread.
    public static func fetch(now: Date = Date(), session: URLSession = .shared) async throws -> AccountUsage {
        guard let token = ClaudeCodeToken.readFromKeychain() else { throw AccountUsageError.noCredentials }
        guard token.isUsable(at: now) else { throw AccountUsageError.tokenExpired }

        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("claude-meter/\(MeterVersion.marketing)", forHTTPHeaderField: "User-Agent")

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch {
            throw AccountUsageError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw AccountUsageError.badResponse }
        switch http.statusCode {
        case 200: return try AccountUsage.parse(data, fetchedAt: Date())
        case 401, 403: throw AccountUsageError.unauthorized
        case 429: throw AccountUsageError.rateLimited
        default: throw AccountUsageError.http(http.statusCode)
        }
    }
}

public extension UsageState {
    /// What the display shows: the statusLine state, with the two windows taken from the account
    /// while that data is fresh. Model, context, cost, lines and "last activity" stay from Claude Code.
    static func combined(file: UsageState?, account: AccountUsage?, now: Date,
                         maxAge: TimeInterval = 10 * 60) -> UsageState? {
        guard let a = account, now.timeIntervalSince(a.fetchedAt) <= maxAge else { return file }
        var s = file ?? UsageState(updatedAt: 0)
        s.fiveHour = a.fiveHour
        s.sevenDay = a.sevenDay
        return s
    }
}
