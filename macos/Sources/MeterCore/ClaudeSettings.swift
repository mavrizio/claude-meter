import Foundation

/// Reads and edits the `statusLine` entry of Claude Code's ~/.claude/settings.json.
public enum ClaudeSettings {
    public enum Status: Equatable, Sendable {
        case missing                 // no statusLine (or no settings file)
        case ours                    // points to this app's helper
        case oursOutdated(String)    // an older claude-meter (Python script, app moved...)
        case other(String)           // someone else's status line
        case unreadable              // settings.json is not valid JSON: never touch it
    }

    public enum SettingsError: LocalizedError {
        case unreadable
        public var errorDescription: String? {
            "~/.claude/settings.json non e' un JSON valido: correggilo a mano, Claude Meter non lo modifica."
        }
    }

    public static func command(helper: String) -> String { "\"\(helper)\"" }

    public static func status(helper: String, url: URL = MeterPaths.claudeSettings) -> Status {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        guard let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String else { return .missing }
        if cmd == command(helper: helper) { return .ours }
        if cmd.contains("claude-meter") { return .oursOutdated(cmd) }
        return .other(cmd)
    }

    /// Points statusLine at `helper`. Makes a timestamped backup first. Returns the backup URL, if any.
    @discardableResult
    public static func install(helper: String, url: URL = MeterPaths.claudeSettings, now: Date = Date()) throws -> URL? {
        let target = url.resolvingSymlinksInPath()
        var obj: [String: Any] = [:]
        var backup: URL?
        if let data = try? Data(contentsOf: target) {
            guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw SettingsError.unreadable
            }
            obj = o
            backup = try makeBackup(of: target, data: data, now: now)
        }
        obj["statusLine"] = ["type": "command", "command": command(helper: helper), "padding": 0] as [String: Any]
        try write(obj, to: target)
        return backup
    }

    /// Removes statusLine only if it belongs to claude-meter.
    @discardableResult
    public static func uninstall(url: URL = MeterPaths.claudeSettings, now: Date = Date()) throws -> Bool {
        let target = url.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target) else { return false }
        guard var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SettingsError.unreadable
        }
        guard let sl = obj["statusLine"] as? [String: Any], let cmd = sl["command"] as? String,
              cmd.contains("claude-meter") else { return false }
        try makeBackup(of: target, data: data, now: now)
        obj.removeValue(forKey: "statusLine")
        try write(obj, to: target)
        return true
    }

    @discardableResult
    private static func makeBackup(of url: URL, data: Data, now: Date) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let b = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".bak-claude-meter-" + f.string(from: now))
        try data.write(to: b)
        return b
    }

    private static func write(_ obj: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
