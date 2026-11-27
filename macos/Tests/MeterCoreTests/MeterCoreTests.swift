import XCTest
@testable import MeterCore

final class MeterCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func payload(fh: Double? = 23.5, fhReset: Int = 1_800_007_000) -> [String: Any] {
        var p: [String: Any] = [
            "model": ["display_name": "Opus"],
            "cost": ["total_cost_usd": 0.42, "total_lines_added": 10, "total_lines_removed": 2],
            "context_window": ["used_percentage": 12],
        ]
        if let fh {
            p["rate_limits"] = [
                "five_hour": ["used_percentage": fh, "resets_at": fhReset],
                "seven_day": ["used_percentage": 81, "resets_at": 1_800_300_000],
            ]
        }
        return p
    }

    func testParsesPayload() {
        let s = UsageState.from(payload: payload(), previous: nil, now: now)
        XCTAssertEqual(s.fiveHour, UsageWindow(pct: 23.5, resetsAt: 1_800_007_000))
        XCTAssertEqual(s.sevenDay?.pct, 81)
        XCTAssertEqual(s.model, "Opus")
        XCTAssertEqual(s.contextPct, 12)
        XCTAssertEqual(s.linesAdded, 10)
    }

    func testKeepsPreviousLimitsWhenMissing() {
        let prev = UsageState.from(payload: payload(), previous: nil, now: now)
        let s = UsageState.from(payload: payload(fh: nil), previous: prev, now: now.addingTimeInterval(60))
        XCTAssertEqual(s.fiveHour, prev.fiveHour)
    }

    func testDropsExpiredPreviousLimits() {
        let prev = UsageState.from(payload: payload(fhReset: 1_800_000_100), previous: nil, now: now)
        let s = UsageState.from(payload: payload(fh: nil), previous: prev, now: now.addingTimeInterval(200))
        XCTAssertNil(s.fiveHour)
        XCTAssertNotNil(s.sevenDay)
    }

    func testReadsPythonStateFile() throws {
        let json = #"{"updated_at": 1795792875.46, "session_id": null, "model": "Opus", "context_pct": null, "cost_usd": null, "lines_added": null, "lines_removed": null, "five_hour": {"pct": 23.5, "resets_at": 1795799875}, "seven_day": null}"#
        let s = try JSONDecoder().decode(UsageState.self, from: Data(json.utf8))
        XCTAssertEqual(s.fiveHour?.pct, 23.5)
        XCTAssertNil(s.sevenDay)
    }

    func testDeviceMessage() {
        let s = UsageState.from(payload: payload(), previous: nil, now: now)
        let m = DeviceMessage.build(state: s, now: now, tzOffset: 3600)
        XCTAssertEqual(m.line, #"{"t":"u","now":1800000000,"tz":3600,"ok":true,"fh":[23.5,1800007000],"sd":[81.0,1800300000],"ctx":12,"cost":0.42,"la":10,"lr":2,"m":"Opus","age":0}"# + "\n")
        let later = DeviceMessage.build(state: s, now: now.addingTimeInterval(5), tzOffset: 3600)
        XCTAssertEqual(m.key, later.key, "time fields must not change the key")
        XCTAssertEqual(DeviceMessage.build(state: nil, now: now, tzOffset: 0).line,
                       #"{"t":"u","now":1800000000,"tz":0,"ok":false}"# + "\n")
    }

    func testPortRankingDropsWchTwin() {
        let names = ["cu.Bluetooth-Incoming-Port", "cu.usbserial-11240", "cu.wchusbserial11240", "cu.usbserial-0001", "tty.usbserial-11240"]
        XCTAssertEqual(SerialPort.rank(names), ["cu.wchusbserial11240", "cu.usbserial-0001"])
    }

    func testRemainingFormat() {
        XCTAssertEqual(MeterFormat.remaining(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(MeterFormat.remaining(3 * 86400 + 4 * 3600 + 5), "3g 4h")
        XCTAssertEqual(MeterFormat.remaining(30), "<1m")
        XCTAssertEqual(MeterFormat.remaining(-1), "ora")
    }

    func testSettingsInstallAndUninstall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"model":"opus","statusLine":{"type":"command","command":"~/my.sh"}}"#.utf8).write(to: url)

        let helper = "/Applications/Claude Meter.app/Contents/MacOS/claude-meter-statusline"
        XCTAssertEqual(ClaudeSettings.status(helper: helper, url: url), .other("~/my.sh"))
        let backup = try ClaudeSettings.install(helper: helper, url: url, now: now)
        XCTAssertNotNil(backup)
        XCTAssertEqual(ClaudeSettings.status(helper: helper, url: url), .ours)
        XCTAssertEqual(ClaudeSettings.status(helper: "/elsewhere/claude-meter-statusline", url: url),
                       .oursOutdated("\"\(helper)\""))

        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "opus", "other settings must survive")

        XCTAssertTrue(try ClaudeSettings.uninstall(url: url, now: now.addingTimeInterval(1)))
        XCTAssertEqual(ClaudeSettings.status(helper: helper, url: url), .missing)
    }

    func testUnreadableSettingsAreNeverTouched() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("{ // comment\n }".utf8)
        try original.write(to: url)
        XCTAssertEqual(ClaudeSettings.status(helper: "x", url: url), .unreadable)
        XCTAssertThrowsError(try ClaudeSettings.install(helper: "x", url: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    // MARK: account usage (experimental source)

    let usageJSON = """
    {"five_hour":{"utilization":44.0,"resets_at":"2026-11-27T20:00:00.050625+00:00","limit_dollars":null},
     "seven_day":{"utilization":16.0,"resets_at":"2026-12-02T16:00:00+00:00"},
     "seven_day_opus":null,"extra_usage":{"is_enabled":false}}
    """

    func testParsesAccountUsage() throws {
        let a = try AccountUsage.parse(Data(usageJSON.utf8), fetchedAt: now)
        XCTAssertEqual(a.fiveHour, UsageWindow(pct: 44, resetsAt: 1_795_809_600)) // 20:00:00.05 rounds down
        XCTAssertEqual(a.sevenDay, UsageWindow(pct: 16, resetsAt: 1_796_227_200))
    }

    func testAccountWindowWithoutResetIsAbsent() throws {
        let json = #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":null}"#
        let a = try AccountUsage.parse(Data(json.utf8), fetchedAt: now)
        XCTAssertNil(a.fiveHour)
        XCTAssertNil(a.sevenDay)
        XCTAssertThrowsError(try AccountUsage.parse(Data("[]".utf8), fetchedAt: now))
    }

    func testParsesClaudeCodeToken() {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1800000600000}}"#
        let t = ClaudeCodeToken.parse(Data(json.utf8))
        XCTAssertEqual(t?.accessToken, "tok")
        XCTAssertEqual(t?.isUsable(at: now), true)
        XCTAssertEqual(t?.isUsable(at: now.addingTimeInterval(590)), false) // < 60 s left
        XCTAssertNil(ClaudeCodeToken.parse(Data(#"{"claudeAiOauth":{}}"#.utf8)))
    }

    func testCombinedPrefersFreshAccountWindows() {
        let file = UsageState.from(payload: payload(), previous: nil, now: now)
        let acc = AccountUsage(fiveHour: UsageWindow(pct: 50, resetsAt: 1_800_007_000), sevenDay: nil, fetchedAt: now)
        let s = UsageState.combined(file: file, account: acc, now: now.addingTimeInterval(60))
        XCTAssertEqual(s?.fiveHour?.pct, 50)
        XCTAssertNil(s?.sevenDay)           // the account is authoritative while fresh
        XCTAssertEqual(s?.model, "Opus")    // everything else stays from Claude Code
        XCTAssertEqual(s?.updatedAt, file.updatedAt)

        let stale = UsageState.combined(file: file, account: acc, now: now.addingTimeInterval(11 * 60))
        XCTAssertEqual(stale, file)

        let onlyAccount = UsageState.combined(file: nil, account: acc, now: now)
        XCTAssertEqual(onlyAccount?.fiveHour?.pct, 50)
        XCTAssertEqual(onlyAccount?.updatedAt, 0) // no fake "Claude is active" on the display
    }
}
