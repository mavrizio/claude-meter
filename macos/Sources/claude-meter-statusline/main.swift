// Claude Code statusLine command (inside Claude Meter.app/Contents/MacOS/).
// Reads the JSON payload on stdin, updates ~/.claude-meter/state.json for the app,
// prints a compact coloured status line for the terminal.
import Foundation
import MeterCore

let input = FileHandle.standardInput.readDataToEndOfFile()
let payload = ((try? JSONSerialization.jsonObject(with: input)) as? [String: Any]) ?? [:]
let now = Date()
let state = UsageState.from(payload: payload, previous: UsageState.load(), now: now)
try? state.save()
print(MeterFormat.statusLine(state, now: now))

// Diagnostics: one line per call in ~/.claude-meter/statusline.log (which session, were limits included).
// Kept small: rewritten from scratch when it passes 256 KB.
let log = MeterPaths.stateDir.appendingPathComponent("statusline.log")
let rl = payload["rate_limits"] as? [String: Any]
func pct(_ k: String) -> String {
    ((rl?[k] as? [String: Any])?["used_percentage"] as? NSNumber).map { "\($0)" } ?? "-"
}
let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withInternetDateTime])
let line = "\(stamp) session=\(payload["session_id"] as? String ?? "?") version=\(payload["version"] as? String ?? "?") "
    + "5h=\(pct("five_hour")) 7d=\(pct("seven_day"))\n"
if let size = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? Int, size < 256 * 1024,
   let h = try? FileHandle(forWritingTo: log) {
    h.seekToEndOfFile()
    h.write(Data(line.utf8))
    try? h.close()
} else {
    try? Data(line.utf8).write(to: log)
}
