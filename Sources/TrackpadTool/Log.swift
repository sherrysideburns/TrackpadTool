import AppKit
import os

// Ready for the crash handler, which may only use crash-safe calls: a file
// descriptor, a fixed text buffer and a buffer for the stack.
private var crashFD: Int32 = -1
private let crashActivitySize = 1024
private let crashActivity: UnsafeMutablePointer<CChar> = {
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: crashActivitySize)
    p.initialize(repeating: 0, count: crashActivitySize)
    return p
}()
private let crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 64)

private func crashWrite(_ text: StaticString) {
    guard crashFD >= 0 else { return }
    text.withUTF8Buffer { _ = Darwin.write(crashFD, $0.baseAddress, $0.count) }
}

private func crashHeader(_ s: Int32) -> StaticString {
    switch s {
    case SIGABRT: return "\n[CRASH] abort\n"
    case SIGSEGV: return "\n[CRASH] bad memory access\n"
    case SIGBUS: return "\n[CRASH] bus error\n"
    case SIGILL: return "\n[CRASH] illegal instruction\n"
    case SIGTRAP: return "\n[CRASH] Swift runtime error\n"
    case SIGFPE: return "\n[CRASH] arithmetic error\n"
    default: return "\n[CRASH] signal\n"
    }
}

/// TrackpadTool's own log: ~/Library/Logs/TrackpadTool/TrackpadTool.log
///
/// - Everything printed to stderr ends up here too (Swift runtime errors,
///   NSLog, AppKit exception messages).
/// - Crashes (signals, uncaught exceptions) are written down before the app
///   goes, and macOS still makes its own crash report.
/// - A watchdog notes when the app stops responding (a freeze), and what
///   it was doing at the time.
/// - If the app didn't quit normally last time (crash or Force Quit), the
///   next launch says so.
enum Log {
    static let directory: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/TrackpadTool", isDirectory: true)
    static let fileURL = directory.appendingPathComponent("TrackpadTool.log")
    private static let markerURL = directory.appendingPathComponent(".running")
    private static let maxSize = 1_000_000

    /// Set at launch when the previous session ended without quitting normally.
    private(set) static var previousSessionEndedUnexpectedly = false

    private static var fd: Int32 = -1
    private static let lock = NSLock()
    private static var crumbs: [String] = []
    private static let osLog = OSLog(subsystem: "com.local.TrackpadTool", category: "app")

    // MARK: Start and stop

    static func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rotateIfNeeded()
        fd = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            // Swift runtime errors, NSLog and AppKit messages go to stderr.
            dup2(fd, STDERR_FILENO)
        }

        if let marker = try? String(contentsOf: markerURL, encoding: .utf8), marker != cleanMark {
            previousSessionEndedUnexpectedly = true
            write("WARN", "The previous session ended without quitting normally (crash, freeze or Force Quit). Last activity: \(marker.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        updateMarker("launched")

        let os = ProcessInfo.processInfo.operatingSystemVersionString
        write("INFO", "──── TrackpadTool \(AppInfo.version) started · macOS \(os) · Accessibility \(AX.isTrusted ? "allowed" : "not allowed")")

        installCrashHandlers()
        handleTermination()
        Watchdog.start()
    }

    private static let cleanMark = "quit normally"
    private static var termSource: DispatchSourceSignal?

    /// Call when quitting normally.
    static func stop() {
        info("Quit normally")
        try? cleanMark.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    /// A rebuild (pkill) or logout asks the app to stop with SIGTERM: quit
    /// properly instead of vanishing, so it isn't mistaken for a crash.
    private static func handleTermination() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            info("Asked to stop (rebuild, logout or Activity Monitor)")
            NSApp.terminate(nil)
            // If quitting gets stuck, go anyway after two seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                stop()
                exit(0)
            }
        }
        source.resume()
        termSource = source
    }

    // MARK: Writing

    static func info(_ message: String) { write("INFO", message) }
    static func warn(_ message: String) { write("WARN", message) }
    static func error(_ message: String) { write("ERROR", message) }

    /// What the app is doing; kept for freeze and crash notes.
    static func breadcrumb(_ message: String) {
        lock.lock()
        crumbs.append("\(time()) \(message)")
        if crumbs.count > 15 { crumbs.removeFirst(crumbs.count - 15) }
        // A ready-made copy for the crash handler, which can't build text.
        let text = "Recent activity: " + crumbs.suffix(5).joined(separator: " → ") + "\n"
        _ = text.withCString { strncpy(crashActivity, $0, crashActivitySize - 1) }
        crashActivity[crashActivitySize - 1] = 0
        lock.unlock()
        write("INFO", message)
        updateMarker(message)
    }

    static var recentActivity: String {
        lock.lock(); defer { lock.unlock() }
        return crumbs.suffix(5).joined(separator: " → ")
    }

    private static let writeLock = NSLock()
    private static var writesSinceCheck = 0

    private static func write(_ level: String, _ message: String) {
        os_log("%{public}@", log: osLog, type: level == "ERROR" ? .error : .default, message)
        let line = "\(timestamp()) [\(level)] \(message)\n"
        writeLock.lock(); defer { writeLock.unlock() }
        guard fd >= 0 else { return }
        line.utf8CString.withUnsafeBufferPointer { buf in
            _ = Darwin.write(fd, buf.baseAddress, buf.count - 1)
        }
        writesSinceCheck += 1
        if writesSinceCheck >= 200 {
            writesSinceCheck = 0
            rotateWhileRunning()
        }
    }

    /// Over the size limit: keep the current log as the old one and start a
    /// new file (checked every 200 lines, so a long session can't grow it forever).
    private static func rotateWhileRunning() {
        var info = stat()
        guard fstat(fd, &info) == 0, Int(info.st_size) > maxSize else { return }
        let old = directory.appendingPathComponent("TrackpadTool.old.log")
        unlink(old.path)
        rename(fileURL.path, old.path)
        let fresh = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fresh >= 0 else { return }
        dup2(fresh, STDERR_FILENO)
        close(fd)
        fd = fresh
        crashFD = fresh
    }

    private static let markerQueue = DispatchQueue(label: "TrackpadTool.log-marker", qos: .utility)

    private static func updateMarker(_ activity: String) {
        let text = "\(timestamp()) \(activity)"
        markerQueue.async { try? text.write(to: markerURL, atomically: false, encoding: .utf8) }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func timestamp() -> String {
        stampFormatter.string(from: Date())
    }

    private static func time() -> String {
        timeFormatter.string(from: Date())
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > maxSize else { return }
        let old = directory.appendingPathComponent("TrackpadTool.old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }

    // MARK: Reading (for Settings)

    /// The last lines of the log, newest last.
    static func tail(lines: Int = 300) -> String {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    static func clear() {
        if fd >= 0 { ftruncate(fd, 0) }
        info("Log cleared")
    }

    // MARK: Crashes

    private static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            Log.write("CRASH", "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))")
        }
        crashFD = fd
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                // Only crash-safe calls here: no text building, no locks, no
                // memory allocation. Write what we know, then let macOS crash
                // the app as usual so it also makes its own crash report.
                crashWrite(crashHeader(s))
                if crashFD >= 0 {
                    _ = Darwin.write(crashFD, crashActivity, strlen(crashActivity))
                    let n = backtrace(crashFrames, 64)
                    backtrace_symbols_fd(crashFrames, n, crashFD)
                }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }


    fileprivate static func writeHang(_ message: String) { write("FREEZE", message) }
}

/// Notices when the main thread stops responding for a few seconds.
private enum Watchdog {
    private static let lock = NSLock()
    // Uptime, not the wall clock: it doesn't jump on sleep or clock changes.
    private static var lastPong = ProcessInfo.processInfo.systemUptime
    private static var reportedSince: TimeInterval?

    static func start() {
        let thread = Thread {
            while true {
                DispatchQueue.main.async {
                    lock.lock(); lastPong = ProcessInfo.processInfo.systemUptime; lock.unlock()
                }
                Thread.sleep(forTimeInterval: 1)
                lock.lock()
                let now = ProcessInfo.processInfo.systemUptime
                let silent = now - lastPong
                let reported = reportedSince
                lock.unlock()
                if silent > 4, reported == nil {
                    lock.lock(); reportedSince = now - silent; lock.unlock()
                    Log.writeHang("Not responding for \(Int(silent)) s. Recent activity: \(Log.recentActivity)")
                } else if silent < 2, let since = reported {
                    lock.lock(); reportedSince = nil; lock.unlock()
                    Log.writeHang("Responding again after \(String(format: "%.1f", now - since)) s")
                }
            }
        }
        thread.name = "TrackpadTool watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }
}
