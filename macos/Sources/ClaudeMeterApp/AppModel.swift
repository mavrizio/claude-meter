import Foundation
import MeterCore
import Observation
import ServiceManagement

/// App state. Everything here runs on the main thread (timer + main-queue callbacks).
@Observable
final class AppModel {
    static let shared = AppModel(live: !Snapshot.requested)

    private(set) var state: UsageState?
    private(set) var now = Date()
    private(set) var link: DeviceLink.Status = .searching
    private(set) var setup: ClaudeSettings.Status = .missing
    private(set) var launchAtLogin = false
    var notice: String?

    var paused = false { didSet { device.paused = paused } }
    var demo = false { didSet { if !demo { stateMTime = nil } ; tick() } }
    var showPercentInMenuBar: Bool = UserDefaults.standard.object(forKey: "showPercent") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPercentInMenuBar, forKey: "showPercent") }
    }

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private let device = DeviceLink()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stateMTime: Date?
    @ObservationIgnored private let demoStart = Date()
    @ObservationIgnored private var activity: NSObjectProtocol?

    /// The statusLine helper sits next to the app executable (Contents/MacOS, or .build/debug in dev).
    static var helperPath: String {
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return exe.deletingLastPathComponent().appendingPathComponent("claude-meter-statusline").path
    }

    /// `live: false` = no USB, no timer: used by `--snapshot` to render the panel with demo data.
    init(live: Bool = true) {
        self.live = live
        guard live else {
            demo = true
            setup = .ours
            link = .connected(port: "/dev/cu.usbserial-demo", firmware: "0.1.0")
            return
        }
        // A menu bar app is a prime App Nap candidate: keep the 1 s refresh punctual.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                         reason: "Aggiornamento del display claude-meter")
        device.onStatus = { [weak self] s in
            NSLog("claude-meter link: %@", String(describing: s))
            self?.link = s
        }
        device.start()
        refreshSetup()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        tick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: refresh

    func tick() {
        now = Date()
        if demo {
            state = DemoData.state(start: demoStart, now: now)
        } else {
            reloadStateIfChanged()
        }
        device.setMessage(DeviceMessage.build(state: state, now: now))
    }

    private func reloadStateIfChanged() {
        let url = MeterPaths.stateFile
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard mtime != stateMTime else { return }
        stateMTime = mtime
        state = mtime == nil ? nil : UsageState.load(from: url)
    }

    func refreshSetup() {
        guard live else { return }
        setup = ClaudeSettings.status(helper: Self.helperPath)
    }

    // MARK: actions

    func configureClaudeCode() {
        do {
            let backup = try ClaudeSettings.install(helper: Self.helperPath)
            notice = "Fatto. Le sessioni di Claude Code gia' aperte vanno riavviate."
                + (backup.map { "\nBackup: \($0.lastPathComponent)" } ?? "")
        } catch {
            notice = error.localizedDescription
        }
        refreshSetup()
    }

    func removeClaudeCodeConfiguration() {
        do {
            let removed = try ClaudeSettings.uninstall()
            notice = removed ? "Barra di stato rimossa da Claude Code." : "Nessuna configurazione di Claude Meter da rimuovere."
        } catch {
            notice = error.localizedDescription
        }
        refreshSetup()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notice = "Avvio al login non disponibile: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: derived

    var menuBarSymbol: String {
        let worst = [state?.fiveHour, state?.sevenDay].compactMap { $0 }.filter { $0.isValid(at: now) }.map(\.pct).max() ?? 0
        switch worst {
        case ..<34: return "gauge.with.dots.needle.0percent"
        case ..<67: return "gauge.with.dots.needle.33percent"
        case ..<90: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }
}
