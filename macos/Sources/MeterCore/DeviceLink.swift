import Foundation

/// Keeps a USB connection to the display on a background thread.
///
/// The board resets when the port is opened and then says `{"t":"hello","fw":...}`; it repeats
/// the hello every 5 s while it has no data. We only talk to a port after it said hello, so other
/// USB-serial gadgets on the Mac are left alone (a port that stays silent is skipped for a minute).
public final class DeviceLink: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case searching
        case probing(port: String)
        case connected(port: String, firmware: String)
        case paused
    }

    /// Called on the main queue.
    public var onStatus: ((Status) -> Void)?

    private let lock = NSLock()
    private var message: DeviceMessage?
    private var isPaused = false
    private var lastStatus: Status?
    private var thread: Thread?

    public init() {}

    public func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in self?.run() }
        t.name = "claude-meter.serial"
        t.qualityOfService = .utility
        thread = t
        t.start()
    }

    public func setMessage(_ m: DeviceMessage) { locked { message = m } }

    public var paused: Bool {
        get { locked { isPaused } }
        set { locked { isPaused = newValue } }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func report(_ s: Status) {
        let changed: Bool = locked {
            guard lastStatus != s else { return false }
            lastStatus = s
            return true
        }
        if changed { DispatchQueue.main.async { self.onStatus?(s) } }
    }

    // MARK: loop

    private enum SessionEnd { case openFailed, silent, ended }

    private func run() {
        var lastGood: String?
        var skipUntil: [String: Date] = [:]
        while true {
            if paused {
                report(.paused)
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            var ports = SerialPort.candidates().filter { (skipUntil[$0] ?? .distantPast) < Date() }
            if let g = lastGood, let i = ports.firstIndex(of: g) { ports.swapAt(0, i) }
            if ports.isEmpty {
                report(.searching)
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            for p in ports where !paused {
                report(.probing(port: p))
                switch session(p) {
                case .openFailed: skipUntil[p] = Date().addingTimeInterval(10)
                case .silent: skipUntil[p] = Date().addingTimeInterval(60)
                case .ended: lastGood = p
                }
            }
            report(.searching)
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func session(_ path: String) -> SessionEnd {
        guard let port = try? SerialPort(path: path) else { return .openFailed }
        defer { port.close() }

        var buf: [UInt8] = []
        var firmware: String?
        let helloDeadline = Date().addingTimeInterval(10)
        var lastSent = Date.distantPast
        var lastKey: String?

        while !paused {
            guard let bytes = try? port.read(timeout: 0.2) else { return firmware == nil ? .silent : .ended }
            buf += bytes
            while let nl = buf.firstIndex(of: 10) {
                let line = Data(buf[..<nl])
                buf.removeSubrange(...nl)
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      obj["t"] as? String == "hello" else { continue }
                firmware = obj["fw"] as? String ?? "?"
                lastSent = .distantPast // board (re)booted: send right away
                report(.connected(port: path, firmware: firmware!))
            }
            if buf.count > 4096 { buf.removeAll() }

            guard firmware != nil else {
                if Date() > helloDeadline { return .silent }
                continue
            }
            guard let m = locked({ message }) else { continue }
            if m.key != lastKey || Date().timeIntervalSince(lastSent) >= 2 {
                do { try port.write(m.line) } catch { return .ended }
                lastSent = Date()
                lastKey = m.key
            }
        }
        return .ended
    }
}
