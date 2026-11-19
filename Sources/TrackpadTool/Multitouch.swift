import Foundation
import AppKit

/// Reads raw finger positions from the trackpad through Apple's private
/// MultitouchSupport framework (the same approach BetterTouchTool and
/// similar tools use). The framework is loaded at runtime, so nothing here
/// needs special build flags.

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterCallbackFn = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void

struct TouchPoint {
    let id: Int32
    let x: Float   // 0 = left edge, 1 = right edge
    let y: Float   // 0 = bottom edge, 1 = top edge
    /// How hard the finger presses (Force Touch trackpads; units are the
    /// trackpad's own, so only compare readings with each other).
    var pressure: Float = 0
    /// Contact size, for diagnostics.
    var size: Float = 0
}

/// Size and field offsets of one finger record ("MTTouch") in a frame.
private enum MTTouchLayout {
    static let stride = 96
    static let identifier = 16
    static let state = 20
    static let normalizedX = 32
    static let normalizedY = 36
    static let size = 48       // "zTotal"
    static let pressure = 52
}

private typealias MTDeviceGetFamilyIDFn = @convention(c) (MTDeviceRef?, UnsafeMutablePointer<Int32>?) -> Int32

private let contactCallback: MTContactCallback = { device, data, count, timestamp, _ in
    var points: [TouchPoint] = []
    if let data = data, count > 0 {
        points.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let base = data.advanced(by: i * MTTouchLayout.stride)
            let state = base.load(fromByteOffset: MTTouchLayout.state, as: Int32.self)
            // 4 = finger landing, 5 = finger touching
            guard state == 4 || state == 5 else { continue }
            points.append(TouchPoint(
                id: base.load(fromByteOffset: MTTouchLayout.identifier, as: Int32.self),
                x: base.load(fromByteOffset: MTTouchLayout.normalizedX, as: Float.self),
                y: base.load(fromByteOffset: MTTouchLayout.normalizedY, as: Float.self),
                pressure: base.load(fromByteOffset: MTTouchLayout.pressure, as: Float.self),
                size: base.load(fromByteOffset: MTTouchLayout.size, as: Float.self)
            ))
        }
    }
    MultitouchReader.shared.deliver(points, from: device, timestamp: timestamp)
    return 0
}

final class MultitouchReader {
    static let shared = MultitouchReader()

    /// Below this pressure a touch isn't pressing like a click (a click on a
    /// Force Touch trackpad reads about 90–130; a resting finger far less).
    static let clickPressureFloor: Float = 40

    private var handle: UnsafeMutableRawPointer?
    private var createList: MTDeviceCreateListFn?
    private var register: MTRegisterCallbackFn?
    private var unregister: MTRegisterCallbackFn?
    private var startDevice: MTDeviceStartFn?
    private var stopDevice: MTDeviceStopFn?
    private var familyID: MTDeviceGetFamilyIDFn?

    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    /// How many devices macOS listed last time (trackpads and others).
    private var listedCount = 0
    private var lastLoggedCount = -1
    private(set) var isRunning = false
    var deviceCount: Int { devices.count }
    /// Listening was asked for (even if no trackpad is connected yet).
    private var wanted = false
    private var lastDeviceCheck: TimeInterval = 0
    private let deliverLock = NSLock()

    // Guarded by `lock` (written on the framework's thread, read anywhere):
    private let lock = NSLock()
    private var _onFrame: (([TouchPoint], Double) -> Void)?
    private var _onForceFrame: (([TouchPoint]) -> Void)?
    /// Latest fingers per trackpad, with when that trackpad last reported.
    private var perDevice: [UInt: (points: [TouchPoint], at: TimeInterval)] = [:]
    /// Each trackpad's number, so finger ids from two trackpads never clash.
    private var deviceNumber: [UInt: Int32] = [:]
    private var _points: [TouchPoint] = []
    /// When each finger first touched (seconds, the framework's clock).
    private var _started: [Int32: Double] = [:]
    /// The framework's clock at the latest frame.
    private var _frameTime: Double = 0
    /// When the last frame arrived (seconds since boot, our clock).
    private var _lastFrame: TimeInterval = 0

    /// Called on the framework's own thread for every touch frame.
    var onFrame: (([TouchPoint], Double) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onFrame }
        set { lock.lock(); _onFrame = newValue; lock.unlock() }
    }

    /// Also called for every frame, for force-press detection.
    var onForceFrame: (([TouchPoint]) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onForceFrame }
        set { lock.lock(); _onForceFrame = newValue; lock.unlock() }
    }

    /// A finger on the trackpad and when it landed.
    struct LiveTouch {
        let point: TouchPoint
        let started: Double
    }

    /// Fingers on the trackpad right now, with when each landed. Empty if the
    /// trackpad has gone quiet, so old data never counts.
    var currentTouches: [LiveTouch] {
        lock.lock(); defer { lock.unlock() }
        guard ProcessInfo.processInfo.systemUptime - _lastFrame < 0.3 else { return [] }
        return _points.map { LiveTouch(point: $0, started: _started[$0.id] ?? 0) }
    }

    /// The framework's clock at the latest frame (same clock as `LiveTouch.started`).
    var frameTime: Double {
        lock.lock(); defer { lock.unlock() }
        return _frameTime
    }

    private init() {}

    private func loadFramework() -> Bool {
        if handle != nil { return true }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let h = dlopen(path, RTLD_NOW) else {
            Log.error("Could not load MultitouchSupport")
            return false
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        createList = sym("MTDeviceCreateList", MTDeviceCreateListFn.self)
        register = sym("MTRegisterContactFrameCallback", MTRegisterCallbackFn.self)
        unregister = sym("MTUnregisterContactFrameCallback", MTRegisterCallbackFn.self)
        startDevice = sym("MTDeviceStart", MTDeviceStartFn.self)
        stopDevice = sym("MTDeviceStop", MTDeviceStopFn.self)
        familyID = sym("MTDeviceGetFamilyID", MTDeviceGetFamilyIDFn.self)

        guard createList != nil, register != nil, startDevice != nil else {
            Log.error("MultitouchSupport functions missing")
            return false
        }
        handle = h
        return true
    }

    /// Magic Mice report touches too; their family ids are 112–127.
    /// Built-in and Magic Trackpads are below 112 or from 128 up.
    private func isMouse(_ device: MTDeviceRef) -> (mouse: Bool, family: Int32) {
        guard let familyID = familyID else { return (false, -1) }
        var family: Int32 = 0
        _ = familyID(device, &family)
        return ((112...127).contains(family), family)
    }

    @discardableResult
    func start() -> Bool {
        wanted = true
        if isRunning { return true }
        guard loadFramework(), let createList = createList, let register = register, let startDevice = startDevice else {
            return false
        }
        guard let list = createList()?.takeRetainedValue() else { return false }
        deviceList = list
        devices = []
        listedCount = CFArrayGetCount(list)
        var skipped: [Int32] = []
        for i in 0..<listedCount {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            let kind = isMouse(device)
            if kind.mouse { skipped.append(kind.family); continue }
            register(device, contactCallback)
            startDevice(device, 0)
            lock.lock(); deviceNumber[UInt(bitPattern: device)] = Int32(devices.count); lock.unlock()
            devices.append(device)
        }
        isRunning = !devices.isEmpty
        if devices.count != lastLoggedCount {
            lastLoggedCount = devices.count
            Log.info("Listening to \(devices.count) trackpad(s)" + (skipped.isEmpty ? "" : "; skipped \(skipped.count) mouse device(s) (family \(skipped.map(String.init).joined(separator: ", ")))"))
        }
        return isRunning
    }

    func stop() {
        wanted = false
        guard isRunning else { return }
        for device in devices {
            unregister?(device, contactCallback)
            stopDevice?(device)
        }
        devices = []
        deviceList = nil
        isRunning = false
        lock.lock(); _points = []; _started = [:]; perDevice = [:]; deviceNumber = [:]; lock.unlock()
    }

    /// Devices stop sending frames after sleep; start them again. Also
    /// works when no trackpad was there before (it may be now).
    func restart() {
        guard wanted else { return }
        stop()
        start()
    }

    /// A trackpad connected or removed since we started: start over with
    /// the new list. Checked often while waiting for a first trackpad,
    /// otherwise every 10 s.
    func refreshDevicesIfNeeded() {
        guard wanted, let createList = createList else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if isRunning && now - lastDeviceCheck < 10 { return }
        lastDeviceCheck = now
        guard let list = createList()?.takeRetainedValue() else { return }
        if CFArrayGetCount(list) != listedCount || !isRunning { restart() }
    }

    /// Number of fingers on the trackpad right now (0 if it has gone quiet).
    var touchCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - _lastFrame < 0.3 ? _points.count : 0
    }

    fileprivate func deliver(_ raw: [TouchPoint], from device: MTDeviceRef?, timestamp: Double) {
        // Each trackpad sends frames on its own thread: handle one whole
        // frame at a time, in order, so the recognizer never runs twice at once.
        deliverLock.lock(); defer { deliverLock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let key = device.map { UInt(bitPattern: $0) } ?? 0
        lock.lock()
        let number = deviceNumber[key] ?? 0
        // Give each trackpad its own range of finger ids.
        let points = number == 0 ? raw : raw.map {
            TouchPoint(id: $0.id + number * 1000, x: $0.x, y: $0.y, pressure: $0.pressure, size: $0.size)
        }
        perDevice[key] = (points, now)
        // All trackpads' fingers together; a quiet trackpad's empty frames
        // no longer wipe out the fingers on the other one.
        var merged: [TouchPoint] = []
        for (_, entry) in perDevice where now - entry.at < 0.3 { merged += entry.points }
        _points = merged
        _lastFrame = now
        _frameTime = timestamp
        var started: [Int32: Double] = [:]
        for p in merged { started[p.id] = _started[p.id] ?? timestamp }
        _started = started
        let frame = _onFrame, force = _onForceFrame
        lock.unlock()
        frame?(merged, timestamp)
        force?(merged)
    }
}
