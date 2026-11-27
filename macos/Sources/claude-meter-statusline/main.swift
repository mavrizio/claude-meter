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
