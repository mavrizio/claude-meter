import Foundation
import MeterCore

/// Fake, animated data to try the app and the display without Claude Code (same as meterd.py --demo).
enum DemoData {
    static func state(start: Date, now: Date) -> UsageState {
        let t = now.timeIntervalSince(start)
        let t0 = Int(start.timeIntervalSince1970)
        let fh = 5 + 93 * (0.5 - 0.5 * cos(t / 12))
        return UsageState(
            updatedAt: now.timeIntervalSince1970 - (Int(t / 10) % 2 == 1 ? 0 : 60),
            model: "Opus 5.5",
            contextPct: min(99, 8 + t * 0.8),
            costUsd: 0.42 + t * 0.013,
            linesAdded: 156 + Int(t),
            linesRemoved: 23 + Int(t / 3),
            fiveHour: UsageWindow(pct: fh, resetsAt: t0 + 2 * 3600 + 14 * 60),
            sevenDay: UsageWindow(pct: 41.2, resetsAt: t0 + 3 * 86400 + 4 * 3600))
    }
}
