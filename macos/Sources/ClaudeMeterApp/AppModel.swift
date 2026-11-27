import AppKit
import Foundation
import MeterCore
import Network
import Observation
import ServiceManagement

/// App state. Everything here runs on the main thread (timer + main-queue callbacks); background
/// work (account fetch) only hops back through DispatchQueue.main, hence @unchecked Sendable.
@Observable
final class AppModel: @unchecked Sendable {
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

    /// Experimental: take the 5h/7d limits from the account (see MeterCore/AccountUsage.swift).
    var useAccountUsage: Bool = UserDefaults.standard.bool(forKey: "useAccountUsage") {
        didSet {
            UserDefaults.standard.set(useAccountUsage, forKey: "useAccountUsage")
            account = nil
            accountError = nil
            nextAccountPoll = .distantPast
            tick()
        }
    }
    /// How often the account is polled (minutes); longer = fewer requests to the undocumented endpoint.
    var accountIntervalMinutes: Int = UserDefaults.standard.object(forKey: "accountIntervalMin") as? Int ?? 2 {
        didSet {
            UserDefaults.standard.set(accountIntervalMinutes, forKey: "accountIntervalMin")
            accountBackoff = accountInterval
            // apply now: next poll one interval after the last fetch
            nextAccountPoll = (account?.fetchedAt ?? .distantPast).addingTimeInterval(accountInterval)
            tick()
        }
    }
    static let accountIntervalChoices = [1, 2, 5, 10, 15, 30]
    var accountInterval: TimeInterval { TimeInterval(max(accountIntervalMinutes, 1) * 60) }
    /// Account data older than this falls back to the statusLine (a couple of missed polls).
    var accountMaxAge: TimeInterval { max(10 * 60, accountInterval * 2.5) }

    /// Last successful account fetch (nil = none yet / feature off) and last error, for the panel.
    private(set) var account: AccountUsage?
    private(set) var accountError: AccountUsageError?

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private let device = DeviceLink()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stateMTime: Date?
    @ObservationIgnored private let demoStart = Date()
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var fileState: UsageState?
    @ObservationIgnored private var nextAccountPoll = Date.distantPast
    @ObservationIgnored private var accountPolling = false
    @ObservationIgnored private var accountBackoff: TimeInterval = 120
    @ObservationIgnored private let pathMonitor = NWPathMonitor()

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
        // At login the first fetch often runs before Wi-Fi is up, and after sleep the data is stale:
        // fetch again as soon as the network comes back and right after wake.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { self?.pollAccountSoon(after: 2) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pollAccountSoon(after: 5)
        }
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
            pollAccountIfDue()
            state = UsageState.combined(file: fileState, account: useAccountUsage ? account : nil, now: now,
                                        maxAge: accountMaxAge)
        }
        device.setMessage(DeviceMessage.build(state: state, now: now))
    }

    private func reloadStateIfChanged() {
        let url = MeterPaths.stateFile
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard mtime != stateMTime else { return }
        stateMTime = mtime
        fileState = mtime == nil ? nil : UsageState.load(from: url)
    }

    /// True when the gauges currently show account data (fresh fetch, feature on).
    var showsAccountUsage: Bool {
        guard useAccountUsage, !demo, let a = account else { return false }
        return now.timeIntervalSince(a.fetchedAt) <= accountMaxAge
    }

    private func pollAccountIfDue() {
        guard live, useAccountUsage, !accountPolling, now >= nextAccountPoll else { return }
        accountPolling = true
        Task.detached {
            let result: Result<AccountUsage, AccountUsageError>
            do { result = .success(try await AccountUsageClient.fetch()) } catch let e as AccountUsageError {
                result = .failure(e)
            } catch {
                result = .failure(.network(error.localizedDescription))
            }
            DispatchQueue.main.async { [weak self] in self?.accountDidFetch(result) }
        }
    }

    /// Brings the next account fetch forward (never later than already planned).
    private func pollAccountSoon(after delay: TimeInterval) {
        guard useAccountUsage else { return }
        let fresh = account.map { Date().timeIntervalSince($0.fetchedAt) < 60 } ?? false
        guard !fresh else { return } // just fetched: no need
        nextAccountPoll = min(nextAccountPoll, Date().addingTimeInterval(delay))
    }

    private func accountDidFetch(_ result: Result<AccountUsage, AccountUsageError>) {
        accountPolling = false
        guard useAccountUsage else { return } // switched off while the request was running
        switch result {
        case let .success(a):
            account = a
            accountError = nil
            accountBackoff = accountInterval
        case let .failure(e):
            accountError = e
            NSLog("claude-meter account usage: %@", String(describing: e)) // never contains the token
        }
        nextAccountPoll = Date().addingTimeInterval(retryDelay(after: result))
        tick()
    }

    func refreshSetup() {
        guard live else { return }
        setup = ClaudeSettings.status(helper: Self.helperPath)
    }

    /// When to try again. Local problems retry soon and never escalate; only the service's own
    /// refusals back off (doubling up to 15 min), so we never hammer the endpoint.
    private func retryDelay(after result: Result<AccountUsage, AccountUsageError>) -> TimeInterval {
        switch result {
        case .success:
            return accountInterval
        case .failure(.network):
            return 30                      // offline / Wi-Fi not up yet (the path monitor may come first)
        case .failure(.tokenExpired), .failure(.noCredentials):
            return 60                      // keychain only, no request: resumes as soon as Claude Code refreshes
        case .failure:
            accountBackoff = min(accountBackoff * 2, max(15 * 60, accountInterval))
            return accountBackoff
        }
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
