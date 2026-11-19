import AppKit

/// Connects the trackpad reader, the gesture recognizer and the actions.
/// It only listens to the trackpad, clicks or force presses while at least
/// one gesture of that kind is set to something other than "macOS default".
final class GestureEngine {
    static let shared = GestureEngine()

    private let recognizer = GestureRecognizer()
    private let clickTap = ClickTap()
    private var switcherSession = false

    private var store: SettingsStore { SettingsStore.shared }

    /// A copy of what the click watcher needs, readable from its own thread.
    private let tapState = TapSnapshot()
    private var frontObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    private init() {
        recognizer.onEvent = { event in
            DispatchQueue.main.async { GestureEngine.shared.handle(event) }
        }
        let r = recognizer
        MultitouchReader.shared.onFrame = { points, timestamp in
            r.process(points, timestamp: timestamp)
        }
        // These run on the click watcher's thread: they only read tapState.
        let state = tapState
        clickTap.actionForClick = { touches in
            GestureEngine.clickAction(touches, state.read())
        }
        clickTap.actionForForcePress = {
            GestureEngine.action(for: .forcePress, state.read())
        }
        clickTap.forceThreshold = { clickPressure in
            let s = state.read().settings
            if s.forceStrength == .matchMac, let calibrated = s.forceCalibration, calibrated > 0 {
                return calibrated
            }
            return clickPressure * s.forceStrength.ratio
        }

        // Keep the copy current: the app in front, and whether Stage Manager
        // is on. The same timer notices trackpads connected later.
        tapState.update(frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        frontObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.tapState.update(frontApp: app?.bundleIdentifier)
        }
        tapState.update(stageOn: StageManager.isOn)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.tapState.update(stageOn: StageManager.isOn)
            MultitouchReader.shared.refreshDevicesIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        clickTap.run = { action in
            GestureEngine.shared.perform(action)
        }
        HotKeyCenter.shared.run = { action, shortcut in
            GestureEngine.shared.perform(action, label: "Shortcut \(shortcut.display)")
        }
        LaunchPlacer.shared.start()
    }

    /// Call whenever settings change.
    func reconfigure() {
        tapState.update(settings: store.settings)
        HotKeyCenter.shared.update(store.settings.keyShortcuts, enabled: store.settings.enabled)
        var needsTouch = false, needsClicks = false, needsForce = false
        var swipes3 = false, swipes4 = false
        if store.settings.enabled {
            for g in Gesture.allCases where store.isUsed(g) {
                if g == .forcePress {
                    // Force press is read from the trackpad's pressure data.
                    needsForce = true
                    needsTouch = true
                } else {
                    needsTouch = true
                    if g.isClick { needsClicks = true }
                    if g.isMultiFingerSwipe {
                        if g.group == .threeFingers { swipes3 = true }
                        if g.group == .fourFingers { swipes4 = true }
                    }
                }
            }
        }
        let enabled = store.settings.enabled
        recognizer.detectTipTap = enabled && (store.isUsed(.tipTapLeft) || store.isUsed(.tipTapRight))
        recognizer.detectEdges = enabled && [Gesture.edgeLeft, .edgeRight, .edgeTop, .edgeBottom].contains { store.isUsed($0) }

        if needsTouch {
            MultitouchReader.shared.start()
        } else {
            endSwitcherSession()
            MultitouchReader.shared.stop()
        }
        clickTap.configure(clicks: needsClicks, forcePress: needsForce,
                           blockScroll: (three: swipes3, four: swipes4))
    }

    func restartAfterWake() {
        endSwitcherSession()
        MultitouchReader.shared.restart()
        clickTap.restart()
    }

    /// Accessibility was just allowed (again): the click watcher has to be
    /// created anew, even if an old one still exists.
    func restartClickWatcher() {
        clickTap.forceRestart()
        reconfigure()
    }

    /// A switcher left open when the trackpad reader stops mid-swipe.
    private func endSwitcherSession() {
        if switcherSession {
            switcherSession = false
            WindowSwitcher.shared.commit()
        }
    }

    var isListening: Bool { MultitouchReader.shared.isRunning }
    var clickTapFailed: Bool { clickTap.failed }

    // MARK: Running actions

    /// The action for a gesture in the app that's in front, or nil for "macOS default".
    private func config(for gesture: Gesture) -> ActionConfig? {
        guard store.settings.enabled else { return nil }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let c = store.effectiveConfig(for: gesture, app: app)
        return c.kind == .macDefault ? nil : c
    }

    /// Runs an action, or explains why it can't.
    private func perform(_ config: ActionConfig, gesture: Gesture? = nil, label: String? = nil) {
        Log.breadcrumb("\(label ?? "Gesture \(gesture?.fullTitle ?? "click")") → \(config.kind.title)")
        if !AX.isTrusted && !config.kind.worksWithoutAccessibility {
            GlassHUD.shared.show(symbol: "lock", text: "Allow Accessibility for TrackpadTool in System Settings")
            return
        }
        if config.kind.isSwitcher, let g = gesture, g.isMultiFingerSwipe {
            switcherSession = true
            WindowSwitcher.shared.begin(direction: g.direction,
                                        mode: config.kind == .stageSwitcher ? .apps : .windows)
        } else {
            ActionRunner.shared.run(config)
        }
    }

    private func handle(_ event: GestureRecognizer.Event) {
        switch event {
        case .trigger(let gesture):
            if let c = config(for: gesture) { perform(c, gesture: gesture) }
        case .step(let direction):
            if switcherSession { WindowSwitcher.shared.step(direction) }
        case .ended:
            if switcherSession {
                switcherSession = false
                WindowSwitcher.shared.commit()
            }
        }
    }

    // MARK: Click watcher side (any thread; uses the snapshot only)

    /// The action for a gesture, or nil for "macOS default".
    fileprivate static func action(for gesture: Gesture, _ snap: TapSnapshot.Values) -> ActionConfig? {
        let s = snap.settings
        guard s.enabled else { return nil }
        let c = s.resolve(gesture, app: snap.frontApp, stage: s.stageSetEnabled && snap.stageOn)
        return c.kind == .macDefault ? nil : c
    }

    /// Which click gesture a physical click is, from the fingers on the trackpad.
    /// Fingers that had been resting well before the others landed (over
    /// 1.5 s) don't count, so a normal click with a resting thumb stays a
    /// normal click, while three fingers placed at a relaxed pace still count.
    fileprivate static func clickAction(_ touches: [MultitouchReader.LiveTouch], _ snap: TapSnapshot.Values) -> ActionConfig? {
        guard let newest = touches.map({ $0.started }).max() else { return nil }
        let landedTogether = touches.filter { newest - $0.started < 1.5 }
        let gesture: Gesture?
        switch landedTogether.count {
        case 3: gesture = .threeClick
        case 4: gesture = .fourClick
        case 1 where touches.count == 1 && isPhysicalPress(touches[0]):
            gesture = corner(landedTogether[0].point, snap.settings)
        default: gesture = nil
        }
        guard let g = gesture else { return nil }
        return action(for: g, snap)
    }

    /// A one-finger click only counts as a corner click if that finger made
    /// it: it just landed (a tap), or it presses like a click. A thumb
    /// resting in a corner while you click an external mouse doesn't count.
    private static func isPhysicalPress(_ t: MultitouchReader.LiveTouch) -> Bool {
        let age = MultitouchReader.shared.frameTime - t.started
        return age < 0.35 || t.point.pressure >= MultitouchReader.clickPressureFloor
    }

    /// Which corner a one-finger click landed in, using each corner's size
    /// (Settings › Gestures › Corner clicks). y: 0 = bottom edge, 1 = top edge.
    private static func corner(_ p: TouchPoint, _ s: Settings) -> Gesture? {
        for c in Corner.allCases {
            let size = s.cornerSize(c)
            guard size != .off else { continue }
            let inX = c.isLeft ? p.x < size.width : p.x > 1 - size.width
            let inY = c.isTop ? p.y > 1 - size.height : p.y < size.height
            if inX && inY { return c.gesture }
        }
        return nil
    }
}

/// What the click watcher needs to pick an action, copied from the main
/// thread whenever it changes, so the watcher never touches live settings.
final class TapSnapshot {
    struct Values {
        var settings: Settings
        var frontApp: String?
        var stageOn: Bool
    }

    private let lock = NSLock()
    private var values = Values(settings: .windowsStyle, frontApp: nil, stageOn: false)

    func read() -> Values {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    func update(settings: Settings) { lock.lock(); values.settings = settings; lock.unlock() }
    func update(frontApp: String?) { lock.lock(); values.frontApp = frontApp; lock.unlock() }
    func update(stageOn: Bool) { lock.lock(); values.stageOn = stageOn; lock.unlock() }
}

/// Watches trackpad clicks (3/4-finger clicks, corner clicks) and force
/// presses, so they can run an action instead. Needs Accessibility permission.
///
/// A click that matches a gesture is held back until you let go. If you
/// start dragging instead, the press is handed back to macOS untouched,
/// so click-and-drag always works.
///
/// It runs on its own thread, so clicks anywhere on the Mac never wait for
/// TrackpadTool's main thread (and macOS doesn't switch the watcher off
/// when the app is busy). Its state is guarded by `stateLock`.
final class ClickTap {
    /// The watcher's own thread and run loop, started once.
    private static let thread = TapThread()
    private let stateLock = NSRecursiveLock()

    var actionForClick: (([MultitouchReader.LiveTouch]) -> ActionConfig?)?
    var actionForForcePress: (() -> ActionConfig?)?
    var run: ((ActionConfig) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchClicks = false
    private var watchForce = false
    /// Finger counts whose swipes are set: their scrolling is held back so
    /// the page doesn't scroll before the swipe's action runs.
    private var blockScroll3 = false
    private var blockScroll4 = false
    /// Scrolling is being held back until every finger has lifted.
    private var scrollBlocked = false
    /// Momentum after a held-back swipe is dropped until this time.
    private var dropMomentumUntil: CFAbsoluteTime = 0
    private var forceFired = false
    private(set) var failed = false

    /// The press being held back, and the action it would run on release.
    private var heldDown: CGEvent?
    private var heldAction: ActionConfig?

    /// Which routes have delivered force-press events (logged once each).
    private var seenRoutes = Set<String>()

    // Force press from the trackpad's own pressure readings, checked on
    // every trackpad frame (not a timer, so it reacts as soon as possible).
    // The pressure to reach is set when the click happens: the pressure at
    // which macOS gives its force-click buzz (calibrated), or a multiple of
    // the pressure of the click itself.
    var forceThreshold: (_ clickPressure: Float) -> Float = { $0 * 1.8 }
    private let forceLock = NSLock()
    // Guarded by forceLock (written on the main thread, read on the trackpad's thread):
    private var forceWatching = false
    private var forceTriggered = false
    private var forceBaseline: Float = 0
    private var forceLimit: Float = 0
    private var forcePeak: Float = 0
    private var sizeBaseline: Float = 0
    private var sizePeak: Float = 0
    // Main thread only:
    private var reportedNoPressure = false

    /// Marks events we re-send, so the watcher lets them through.
    private static let replayMark: Int64 = 0x5450_5454

    // Event types without a CGEventType case.
    private static let quickLookType: UInt32 = 33   // NSEvent.EventType.quickLook
    private static let pressureType: UInt32 = 34    // NSEvent.EventType.pressure

    func configure(clicks: Bool, forcePress: Bool, blockScroll: (three: Bool, four: Bool)) {
        let wanted = clicks || forcePress || blockScroll.three || blockScroll.four
        stateLock.lock(); defer { stateLock.unlock() }
        if clicks == watchClicks && forcePress == watchForce && blockScroll.three == blockScroll3
            && blockScroll.four == blockScroll4 && (tap != nil) == wanted { return }
        stop()
        watchClicks = clicks
        watchForce = forcePress
        blockScroll3 = blockScroll.three
        blockScroll4 = blockScroll.four
        if wanted { start() }
    }

    func restart() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard tap != nil else { return }
        stop()
        start()
    }

    /// Starts over whether or not a watcher exists (after Accessibility
    /// was granted again, an old tap no longer receives anything).
    func forceRestart() {
        stateLock.lock(); defer { stateLock.unlock() }
        let wanted = watchClicks || watchForce || blockScroll3 || blockScroll4
        stop()
        if wanted { start() }
    }

    private func start() {
        guard tap == nil else { return }
        var mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                 | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
                 | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
        if blockScroll3 || blockScroll4 {
            mask |= (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        }
        if watchForce {
            mask |= (CGEventMask(1) << CGEventMask(Self.quickLookType))
                  | (CGEventMask(1) << CGEventMask(Self.pressureType))
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<ClickTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            // Warn once until it works again (this is retried every few seconds).
            if !failed { Log.warn("Click watcher not allowed yet (Accessibility permission needed)") }
            failed = true
            return
        }
        failed = false
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        source = src
        CFRunLoopAddSource(Self.thread.runLoop, src, .commonModes)
        CFRunLoopWakeUp(Self.thread.runLoop)
        CGEvent.tapEnable(tap: t, enable: true)
        if watchForce {
            MultitouchReader.shared.onForceFrame = { [weak self] points in self?.forceFrame(points) }
            Log.info("Watching force presses")
        }
    }

    /// A click happened: note its pressure and what a force press needs.
    private func beginForceWatch() {
        let touches = MultitouchReader.shared.currentTouches
        forceLock.lock(); defer { forceLock.unlock() }
        forceWatching = false
        // Only a real press: tap-and-drag starts with a light touch, and a
        // threshold based on that would trigger mid-drag.
        guard touches.count == 1, touches[0].point.pressure >= MultitouchReader.clickPressureFloor else { return }
        let p = touches[0].point
        forceBaseline = p.pressure
        forcePeak = p.pressure
        sizeBaseline = p.size
        sizePeak = p.size
        forceLimit = forceThreshold(p.pressure)
        forceTriggered = false
        forceWatching = true
    }

    /// Every trackpad frame (on the trackpad's own thread).
    private func forceFrame(_ points: [TouchPoint]) {
        forceLock.lock()
        guard forceWatching, points.count == 1 else { forceLock.unlock(); return }
        let p = points[0]
        forcePeak = max(forcePeak, p.pressure)
        sizePeak = max(sizePeak, p.size)
        var fire = false
        if !forceTriggered, forceLimit > 0, p.pressure >= forceLimit {
            forceTriggered = true
            fire = true
        }
        forceLock.unlock()
        if fire {
            DispatchQueue.main.async { [weak self] in self?.fireForcePress(via: "trackpad pressure") }
        }
    }

    /// The click ended; warns once if this trackpad gives no pressure readings.
    private func endForceWatch(log: Bool) {
        forceLock.lock()
        let was = forceWatching
        forceWatching = false
        let base = forceBaseline, peak = forcePeak
        forceLock.unlock()
        guard was, log else { return }
        if base <= 0 && peak <= 0 {
            if !reportedNoPressure {
                reportedNoPressure = true
                Log.warn("Force press: this trackpad gives no pressure readings")
            }
            return
        }
    }

    /// Runs the force-press action once per press, whichever route sees it first.
    @discardableResult
    private func fireForcePress(via route: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !forceFired, !ForceCalibration.isActive, let action = actionForForcePress?() else { return false }
        forceFired = true
        Log.breadcrumb("Force press caught by \(route)")
        DispatchQueue.main.async { [weak self] in self?.run?(action) }
        return true
    }

    private func saw(_ route: String) {
        if seenRoutes.insert(route).inserted { Log.info("Force press: receiving \(route) events") }
    }

    private func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(Self.thread.runLoop, s, .commonModes) }
        tap = nil
        source = nil
        MultitouchReader.shared.onForceFrame = nil
        forceLock.lock(); forceWatching = false; forceLock.unlock()
        heldDown = nil
        heldAction = nil
        forceFired = false
        scrollBlocked = false
    }

    /// Trackpad scrolling while three or four fingers are down is the start
    /// of a swipe, not a scroll: it's held back until all fingers lift (and
    /// the momentum after it too). Scrolling that had already started gets
    /// one "scroll ended" so apps don't keep bouncing.
    private func filterScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        // Only trackpad-style (continuous) scrolling; a mouse wheel is left alone.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return pass }
        let fingers = MultitouchReader.shared.touchCount
        let momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0

        if scrollBlocked {
            let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            let newScroll = phase == 1 || phase == 128   // began / may begin
            if fingers == 0 {
                scrollBlocked = false
                dropMomentumUntil = CFAbsoluteTimeGetCurrent() + 1.5
            } else if newScroll && fingers < 3 {
                // A fresh two-finger scroll after the swipe: let it through.
                scrollBlocked = false
                dropMomentumUntil = 0
            } else {
                return nil
            }
        }
        if momentum && CFAbsoluteTimeGetCurrent() < dropMomentumUntil { return nil }
        if !momentum { dropMomentumUntil = 0 }

        let swipeFingers = (fingers == 3 && blockScroll3) || (fingers >= 4 && blockScroll4)
        guard swipeFingers else { return pass }
        scrollBlocked = true
        // If a scroll was under way, end it cleanly instead of cutting it off.
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        if phase == 1 || phase == 2 {   // began or changed
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)   // ended
            for f in [CGEventField.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                      .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2] {
                event.setIntegerValueField(f, value: 0)
            }
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            return pass
        }
        return nil
    }

    /// Sends the held-back press (and the event that ended the wait) on to macOS.
    private func replay(_ events: [CGEvent]) {
        for e in events {
            guard let copy = e.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: Self.replayMark)
            copy.post(tap: .cgSessionEventTap)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        stateLock.lock(); defer { stateLock.unlock() }
        let pass = Unmanaged.passUnretained(event)
        let raw = type.rawValue

        if raw == CGEventType.tapDisabledByTimeout.rawValue || raw == CGEventType.tapDisabledByUserInput.rawValue {
            // macOS paused the watcher. Its mouse-up went straight to the app,
            // so a press we were holding back is dropped (re-sending it now
            // would leave the button stuck down).
            if heldDown != nil {
                heldDown = nil
                heldAction = nil
                Log.warn("Click watcher was paused by macOS; a held click was dropped")
            }
            forceFired = false
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }

        // Force press: act on the deep click (stage 2) and keep Look Up from
        // appearing. Three routes, whichever comes first: the pressure event
        // here, the Look Up event macOS sends on a force click, or the
        // pressure monitor (see start()).
        if raw == Self.pressureType {
            saw("pressure (event tap)")
            if forceFired { return nil }
            guard watchForce, let ns = NSEvent(cgEvent: event), ns.stage >= 2 else { return pass }
            return fireForcePress(via: "pressure event") ? nil : pass
        }
        if raw == Self.quickLookType {
            saw("Look Up (event tap)")
            if forceFired { return nil }
            return fireForcePress(via: "Look Up event") ? nil : pass
        }

        // Our own re-sent events go straight through.
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMark { return pass }

        if raw == CGEventType.scrollWheel.rawValue {
            return (blockScroll3 || blockScroll4) ? filterScroll(event) : pass
        }

        if raw == CGEventType.leftMouseDown.rawValue && watchForce {
            beginForceWatch()
        }
        if raw == CGEventType.leftMouseDown.rawValue && watchClicks {
            heldDown = nil
            heldAction = nil
            if let action = actionForClick?(MultitouchReader.shared.currentTouches) {
                // Hold the press back until we know it isn't the start of a drag.
                heldDown = event.copy()
                heldAction = action
                return nil
            }
        }
        if raw == CGEventType.leftMouseDragged.rawValue, let down = heldDown {
            // Moving more than a few points = a drag: give macOS the press after all.
            let dx = event.location.x - down.location.x, dy = event.location.y - down.location.y
            if dx * dx + dy * dy > 16 {
                heldDown = nil
                heldAction = nil
                replay([down, event])
                return nil
            }
            return nil
        }
        if raw == CGEventType.leftMouseUp.rawValue {
            endForceWatch(log: true)
            forceFired = false
            if heldDown != nil, let action = heldAction {
                // Released without dragging: it was the gesture.
                heldDown = nil
                heldAction = nil
                DispatchQueue.main.async { [weak self] in self?.run?(action) }
                return nil
            }
        }
        return pass
    }
}

/// A thread with a run loop that lives as long as the app, for the click
/// watcher's events.
final class TapThread {
    let runLoop: CFRunLoop

    init() {
        var loop: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            // A far-off timer keeps the run loop running while it has no events.
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1e9, 1e9, 0, 0) { _ in }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), keepAlive, .commonModes)
            ready.signal()
            while true { CFRunLoopRun() }
        }
        thread.name = "TrackpadTool click watcher"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoop = loop!
    }
}
