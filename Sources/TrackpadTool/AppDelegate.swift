import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var retryTimer: Timer?
    private let popover = NSPopover()
    private let status = StatusWatcher.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        applyDockPolicy()

        // Menu bar icon: click for the gesture dropdown.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarImage()
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let panel = NSHostingController(
            rootView: MenuBarPanel(status: status, openSettings: { [weak self] in self?.openSettings() })
                .environmentObject(SettingsStore.shared)
        )
        panel.sizingOptions = .preferredContentSize   // the dropdown grows and shrinks with its list
        popover.contentViewController = panel

        AppRecency.shared.start()
        updateStatusIcon()
        GestureEngine.shared.reconfigure()

        // Trackpads stop sending touches after sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                GestureEngine.shared.restartAfterWake()
            }
        }

        // The click watcher can only start once Accessibility is allowed; retry until then.
        // When Accessibility is allowed again after being taken away, the
        // old watcher no longer receives events: make a new one.
        var wasTrusted = AX.isTrusted
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            let trusted = AX.isTrusted
            if trusted && (!wasTrusted || GestureEngine.shared.clickTapFailed) {
                Log.info("Accessibility allowed: restarting the click watcher")
                GestureEngine.shared.restartClickWatcher()
            }
            wasTrusted = trusted
        }

        if SettingsStore.shared.isFirstLaunch {
            showWelcome(firstLaunch: true)
        } else if !AX.isTrusted {
            openSettings()
        }
    }

    /// The first-launch window: Accessibility, then how to start.
    func showWelcome(firstLaunch: Bool = false) {
        welcomeWindow?.close()
        welcomeWindow = nil
        do {
            let view = WelcomeView(status: status, choosesSetup: firstLaunch) { [weak self] setup in
                if let setup = setup {
                    SettingsStore.shared.settings = setup.settings
                    Log.info("First launch: started with \(setup.title)")
                }
                self?.welcomeWindow?.close()
                self?.welcomeWindow = nil
                if firstLaunch {
                    NavigationModel.shared.pane = .gestures
                    self?.openSettings()
                }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = "Welcome to TrackpadTool"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            welcomeWindow = window
        }
        status.watch("welcome", true)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    /// Clicking the Dock icon opens the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Double-clicking a .tpt file: open Settings › Profiles with the import review.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "tpt" }) else { return }
        DispatchQueue.main.async {
            NavigationModel.shared.pane = .profiles
            self.openSettings()
            ProfileManager.shared.beginImport(url)
        }
    }

    /// Dock icon only when "Also show icon in Dock" is on; otherwise menu bar only.
    /// The three-finger hand, drawn as a template so it follows the menu
    /// bar's light or dark look.
    static func menuBarImage() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "TrackpadTool"
            return image
        }
        return NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "TrackpadTool")
    }

    /// Dimmed while gestures are paused.
    func updateStatusIcon() {
        statusItem.button?.appearsDisabled = !SettingsStore.shared.settings.enabled
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(SettingsStore.shared.settings.showInDock ? .regular : .accessory)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            Log.breadcrumb("Opened the menu bar dropdown")
            NSApp.activate(ignoringOtherApps: true)
            status.watch("dropdown", true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func openSettings() {
        Log.breadcrumb("Opened Settings")
        if popover.isShown { popover.performClose(nil) }
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(SettingsStore.shared)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "TrackpadTool"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: view)
            window.setContentSize(NSSize(width: 900, height: 700))
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        status.watch("settings", true)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === settingsWindow { status.watch("settings", false) }
            if window === welcomeWindow { status.watch("welcome", false) }
        }
        DispatchQueue.main.async { self.applyDockPolicy() }
    }

    func popoverDidClose(_ notification: Notification) {
        status.watch("dropdown", false)
    }

    @objc func toggleGestures() {
        SettingsStore.shared.settings.enabled.toggle()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Menu bar (shown while the app is in the Dock)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About TrackpadTool", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide TrackpadTool", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit TrackpadTool", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V")
            .keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // Find (tags are NSFindPanelAction values: 1 = show, 2 = next).
        let find = editMenu.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = 1
        let findNext = editMenu.addItem(withTitle: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g")
        findNext.tag = 2
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
