import Darwin
import Foundation

public enum SerialError: Error {
    case open(Int32)
    case config(Int32)
    case io(Int32)
}

/// Minimal raw 115200 8N1 serial port on top of POSIX termios.
public final class SerialPort {
    public let path: String
    private var fd: Int32 = -1

    public init(path: String) throws {
        self.path = path
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.open(errno) }
        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { let e = errno; close(); throw SerialError.config(e) }
        cfmakeraw(&t)
        cfsetispeed(&t, speed_t(B115200))
        cfsetospeed(&t, speed_t(B115200))
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(CRTSCTS)
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { let e = errno; close(); throw SerialError.config(e) }
        tcflush(fd, TCIOFLUSH)
        // Exclusive access: other processes (a second app instance, pio upload, meterd.py) get EBUSY
        // instead of silently sharing — and resetting — the board.
        guard ioctl(fd, SerialPort.TIOCEXCL) == 0 else { let e = errno; close(); throw SerialError.open(e) }
    }

    static let TIOCEXCL: UInt = 0x2000_740D // _IO('t', 13), not imported into Swift

    deinit { close() }

    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Waits up to `timeout` for data. Returns [] when nothing arrived; throws when the device went away.
    public func read(timeout: TimeInterval) throws -> [UInt8] {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let r = poll(&pfd, 1, Int32(timeout * 1000))
        if r < 0 {
            if errno == EINTR { return [] }
            throw SerialError.io(errno)
        }
        if r == 0 { return [] }
        if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { throw SerialError.io(EIO) }
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(fd, &buf, buf.count)
        if n < 0 {
            if errno == EAGAIN || errno == EINTR { return [] }
            throw SerialError.io(errno)
        }
        if n == 0 { throw SerialError.io(EIO) } // readable but empty = hang-up
        return Array(buf[0..<n])
    }

    public func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        var off = 0, retries = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + off, bytes.count - off) }
            if n < 0 {
                if errno == EAGAIN, retries < 200 { retries += 1; usleep(2000); continue }
                throw SerialError.io(errno)
            }
            off += n
        }
    }

    // MARK: discovery

    /// USB-serial ports that may be the display, best first.
    public static func candidates() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return rank(names).map { "/dev/" + $0 }
    }

    /// The same CH340 shows up twice when the WCH driver is installed (cu.wchusbserialXXXX and
    /// cu.usbserial-XXXX): keep only the WCH one so we never open the board twice.
    static func rank(_ names: [String]) -> [String] {
        let prefixes = ["cu.wchusbserial", "cu.usbserial", "cu.SLAB_USBtoUART"]
        var result: [String] = []
        for p in prefixes { result += names.filter { $0.hasPrefix(p) }.sorted() }
        let wchIDs = Set(result.filter { $0.hasPrefix("cu.wchusbserial") }.map { $0.dropFirst("cu.wchusbserial".count) })
        return result.filter { name in
            guard name.hasPrefix("cu.usbserial-") else { return true }
            return !wchIDs.contains(name.dropFirst("cu.usbserial-".count))
        }
    }
}
