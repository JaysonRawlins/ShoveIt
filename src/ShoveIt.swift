import ApplicationServices
import Cocoa
import os.log

class NotificationMover: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let notificationCenterBundleID: String = "com.apple.notificationcenterui"
    private let paddingAboveDock: CGFloat = 30
    private var axObserver: AXObserver?
    private var statusItem: NSStatusItem?
    private weak var displayDebugItem: NSMenuItem?
    private var menuRefreshTimer: Timer?
    private var isMenuBarIconHidden: Bool = UserDefaults.standard.bool(forKey: "isMenuBarIconHidden")
    private let logger: Logger = .init(subsystem: "com.jjrawlins.ShoveIt", category: "NotificationMover")
    private let debugMode: Bool = UserDefaults.standard.bool(forKey: "debugMode")
    private let launchAgentPlistPath: String = NSHomeDirectory() + "/Library/LaunchAgents/com.jjrawlins.ShoveIt.plist"

    private struct ScreenCache {
        var initialPosition: CGPoint
        var initialWindowSize: CGSize
        var initialNotifSize: CGSize
        var initialPadding: CGFloat
    }

    private struct DisplayOption {
        let id: CGDirectDisplayID
        let name: String
    }

    private var screenCaches: [CGDirectDisplayID: ScreenCache] = [:]

    private var widgetMonitorTimer: Timer?
    private var windowPollingTimer: Timer?
    private var lastWidgetWindowCount: Int = 0
    private var lastKnownWindowCount: Int = 0
    private var pollingEndTime: Date?

    // macOS 26.3+: tracks whether we've repositioned a banner in the current notification cycle
    private var bannerIsActive: Bool = false
    private var lastBannerX: CGFloat = 0
    private var bannerStableCount: Int = 0
    private var initialDialogPos: CGPoint?  // stored before first move, restored on dismiss

    private let positionStore = PositionStore()

    private func debugLog(_ message: String) {
        guard debugMode else { return }
        NSLog("[ShoveIt] %@", message)
    }

    func applicationDidFinishLaunching(_: Notification) {
        if !isMenuBarIconHidden {
            setupStatusItem()
        }
        checkAccessibilityPermissions()
        let trusted = AXIsProcessTrusted()
        debugLog("AXIsProcessTrusted: \(trusted), position: \(positionStore.position.displayName)")
        if trusted {
            setupObserver()
            moveAllNotifications()
        } else {
            debugLog("WARNING: No accessibility permission — ShoveIt cannot move notifications")
        }

        // React to external position changes (e.g. `defaults write`)
        positionStore.onChange = { [weak self] newPosition in
            self?.debugLog("Position changed externally to \(newPosition.displayName)")
            self?.bannerIsActive = false
            self?.bannerStableCount = 0
            self?.rebuildMenu()
            self?.moveAllNotifications()
        }

        // Re-position when displays change (plug/unplug monitor, resolution change)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.debugLog("Screen parameters changed — clearing caches")
            self?.screenCaches.removeAll()
            self?.coerceSelectedDisplayIfNeeded()
            self?.rebuildMenu()
            self?.moveAllNotifications()
        }

        // Stop polling on sleep, reinitialize on wake
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.debugLog("System sleeping — stopping polling")
            self?.windowPollingTimer?.invalidate()
            self?.widgetMonitorTimer?.invalidate()
        }
        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.debugLog("System woke — reinitializing")
            self?.screenCaches.removeAll()
            if AXIsProcessTrusted() {
                self?.setupObserver()
                self?.moveAllNotifications()
            }
        }
    }

    func applicationWillBecomeActive(_: Notification) {
        guard isMenuBarIconHidden else { return }
        isMenuBarIconHidden = false
        UserDefaults.standard.set(false, forKey: "isMenuBarIconHidden")
        setupStatusItem()
    }

    private func checkAccessibilityPermissions() {
        if AXIsProcessTrusted() { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.setupObserver()
                self.moveAllNotifications()
            }
        }
    }

    func setupStatusItem() {
        guard !isMenuBarIconHidden else {
            statusItem = nil
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button: NSStatusBarButton = statusItem?.button, let menuBarIcon = NSImage(named: "MenuBarIcon") {
            menuBarIcon.isTemplate = true
            button.image = menuBarIcon
        }
        statusItem?.menu = createMenu()
    }

    private func rebuildMenu() {
        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let displayMenu = NSMenu()
        let automaticItem = NSMenuItem(title: "Automatic", action: #selector(changeDisplay(_:)), keyEquivalent: "")
        automaticItem.representedObject = 0
        automaticItem.state = positionStore.selectedDisplayID == nil ? .on : .off
        displayMenu.addItem(automaticItem)

        for display in availableDisplays() {
            let item = NSMenuItem(title: display.name, action: #selector(changeDisplay(_:)), keyEquivalent: "")
            item.representedObject = Int(display.id)
            item.state = positionStore.selectedDisplayID == display.id ? .on : .off
            displayMenu.addItem(item)
        }

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        let displayDebugItem = NSMenuItem(title: activeDisplayDebugTitle(), action: nil, keyEquivalent: "")
        displayDebugItem.isEnabled = false
        menu.addItem(displayDebugItem)
        self.displayDebugItem = displayDebugItem
        menu.addItem(NSMenuItem.separator())

        let currentPosition = positionStore.position
        for position: NotificationPosition in NotificationPosition.allCases {
            let item = NSMenuItem(title: position.displayName, action: #selector(changePosition(_:)), keyEquivalent: "")
            item.representedObject = position
            item.state = position == currentPosition ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.state = FileManager.default.fileExists(atPath: launchAgentPlistPath) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(toggleMenuBarIcon(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private func activeDisplayDebugTitle() -> String {
        guard let selectedID = positionStore.selectedDisplayID else {
            return "Target Display: Automatic"
        }

        if let index = NSScreen.screens.firstIndex(where: { $0.displayID == selectedID }) {
            let screen = NSScreen.screens[index]
            let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
            return "Target Display: D\(index + 1) \(screen.localizedName) \(size) (id: \(selectedID))"
        }

        return "Target Display: Missing (id: \(selectedID)) -> Automatic"
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        refreshDisplayDebugLabel()
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.refreshDisplayDebugLabel()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    private func refreshDisplayDebugLabel() {
        displayDebugItem?.title = activeDisplayDebugTitle()
    }

    private func availableDisplays() -> [DisplayOption] {
        NSScreen.screens
            .enumerated()
            .map { index, screen in
                let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
                let name = "Display \(index + 1): \(screen.localizedName) (\(size))"
                return DisplayOption(id: screen.displayID, name: name)
            }
    }

    private func coerceSelectedDisplayIfNeeded() {
        guard let selectedID = positionStore.selectedDisplayID else { return }
        let stillExists = NSScreen.screens.contains(where: { $0.displayID == selectedID })
        if !stillExists {
            debugLog("Selected display \(selectedID) is no longer available — falling back to Automatic")
            positionStore.setSelectedDisplayID(nil)
        }
    }

    @objc private func changeDisplay(_ sender: NSMenuItem) {
        let rawID = sender.representedObject as? Int ?? 0
        let newSelection: CGDirectDisplayID? = rawID > 0 ? CGDirectDisplayID(rawID) : nil
        positionStore.setSelectedDisplayID(newSelection)
        debugLog("Display changed to \(newSelection.map(String.init) ?? "Automatic")")
        screenCaches.removeAll()
        bannerIsActive = false
        bannerStableCount = 0
        rebuildMenu()
        moveAllNotifications()
    }

    private func selectedScreen(fallback: NSScreen?) -> NSScreen? {
        if let selectedID = positionStore.selectedDisplayID,
           let selected = NSScreen.screens.first(where: { $0.displayID == selectedID }) {
            return selected
        }
        return fallback ?? NSScreen.main
    }

    @objc private func toggleMenuBarIcon(_: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon"
        alert.informativeText = "The menu bar icon will be hidden. To show it again, launch ShoveIt again."
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isMenuBarIconHidden = true
        UserDefaults.standard.set(true, forKey: "isMenuBarIconHidden")
        statusItem = nil
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let isEnabled = FileManager.default.fileExists(atPath: launchAgentPlistPath)

        if isEnabled {
            do {
                try FileManager.default.removeItem(atPath: launchAgentPlistPath)
                sender.state = .off
            } catch {
                showError("Failed to disable launch at login: \(error.localizedDescription)")
            }
        } else {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.jjrawlins.ShoveIt</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(Bundle.main.executablePath!)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            do {
                try plistContent.write(toFile: launchAgentPlistPath, atomically: true, encoding: .utf8)
                sender.state = .on
            } catch {
                showError("Failed to enable launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func changePosition(_ sender: NSMenuItem) {
        guard let position: NotificationPosition = sender.representedObject as? NotificationPosition else { return }
        positionStore.setPosition(position)
        debugLog("Position changed to \(position.displayName)")
        // Reset banner tracking so polling re-applies with new position
        bannerIsActive = false
        bannerStableCount = 0
        rebuildMenu()
        moveAllNotifications()
    }

    private func cacheInitialNotificationData(
        screen: NSScreen,
        windowSize: CGSize,
        notifSize: CGSize,
        position: CGPoint
    ) -> ScreenCache {
        let displayID = screen.displayID
        if let existing = screenCaches[displayID] { return existing }

        let screenWidth = screen.frame.width
        let (effectivePosition, padding) = NotificationGeometry.initialData(
            screenWidth: screenWidth,
            notifSize: notifSize,
            position: position
        )

        let cache = ScreenCache(
            initialPosition: effectivePosition,
            initialWindowSize: windowSize,
            initialNotifSize: notifSize,
            initialPadding: padding
        )
        screenCaches[displayID] = cache
        return cache
    }

    private func isWidgetWindow(_ window: AXUIElement) -> Bool {
        if let identifier: String = getWindowIdentifier(window), identifier.hasPrefix("widget") {
            return true
        }
        if findElementWithWidgetIdentifier(root: window) != nil {
            return true
        }
        return false
    }

    private let bannerSubroles: [String] = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXNotificationCenterNotification",
        "AXNotificationCenterBannerWindow",
    ]

    private func getSubrole(of element: AXUIElement) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// Move a notification banner. On macOS < 26.3, `window` is a per-notification window.
    /// On macOS 26.3+, `window` is the full-screen AXSystemDialog containing the banner.
    func moveNotification(_ window: AXUIElement) {
        let isSystemDialog = getSubrole(of: window) == "AXSystemDialog"

        if !isSystemDialog, isWidgetWindow(window) {
            return
        }

        guard let windowSize: CGSize = getSize(of: window) else { return }

        // Find the banner element inside the window
        let notifSize: CGSize
        let bannerPos: CGPoint
        if let found = findElementWithSubrole(root: window, targetSubroles: bannerSubroles),
           let size = getSize(of: found),
           let pos = getPosition(of: found) {
            notifSize = size
            bannerPos = pos
        } else if !isSystemDialog, let size = getSize(of: window), let pos = getPosition(of: window) {
            notifSize = size
            bannerPos = pos
        } else {
            return
        }

        let targetPosition = positionStore.position
        let sourceScreen = NotificationGeometry.screen(containing: bannerPos)
        let targetScreen = selectedScreen(fallback: sourceScreen)

        if isSystemDialog {
            // macOS 26.3+: the banner lives inside a full-screen AXSystemDialog.
            // The dialog covers the entire display where the notification appears.
            // Its position+size in AX coordinates IS the screen coordinate space,
            // which may differ from NSScreen.frame (especially when monitors are
            // rearranged or the laptop lid is closed).
            let windowPos = getPosition(of: window) ?? CGPoint.zero

            // Use the dialog's own frame as the effective screen frame.
            // Borrow dock size from an NSScreen with matching dimensions.
            let dialogFrame = CGRect(origin: windowPos, size: windowSize)
            let matchedDockHeight: CGFloat = targetScreen.map { $0.frame.height - $0.visibleFrame.height }
                ?? NSScreen.screens.first(where: {
                    abs($0.frame.width - windowSize.width) < 2 && abs($0.frame.height - windowSize.height) < 2
                }).map { $0.frame.height - $0.visibleFrame.height } ?? 0
            let targetFrame = targetScreen?.frame ?? dialogFrame
            let effectiveVisible = CGRect(
                x: targetFrame.minX,
                y: targetFrame.minY,
                width: targetFrame.width,
                height: targetFrame.height - matchedDockHeight
            )

            let target = NotificationGeometry.bannerTargetPosition(
                for: targetPosition,
                bannerPos: bannerPos,
                notifSize: notifSize,
                screenFrame: targetFrame,
                visibleFrame: effectiveVisible,
                paddingAboveDock: paddingAboveDock
            )

            // Convert banner target position to window offset
            let bannerRelX = bannerPos.x - windowPos.x
            let bannerRelY = bannerPos.y - windowPos.y
            let newWindowX = target.x - bannerRelX
            let newWindowY = target.y - bannerRelY

            if abs(newWindowX - windowPos.x) > 1 || abs(newWindowY - windowPos.y) > 1 {
                setPosition(window, x: newWindowX, y: newWindowY)
                bannerIsActive = true
                debugLog("Moved AXSystemDialog to (\(newWindowX), \(newWindowY)) for \(targetPosition.displayName), dialogFrame=\(dialogFrame)")
            }
        } else {
            // Pre-26.3: each notification is its own window
            guard let sourceScreen, let targetScreen else { return }

            let cache = cacheInitialNotificationData(
                screen: sourceScreen,
                windowSize: windowSize,
                notifSize: notifSize,
                position: bannerPos
            )

            if bannerPos != cache.initialPosition {
                setPosition(window, x: cache.initialPosition.x, y: cache.initialPosition.y)
            }

            let newPos = NotificationGeometry.newPosition(
                for: targetPosition,
                windowSize: cache.initialWindowSize,
                notifSize: cache.initialNotifSize,
                origin: cache.initialPosition,
                padding: cache.initialPadding,
                screenFrame: targetScreen.frame,
                visibleFrame: targetScreen.visibleFrame,
                paddingAboveDock: paddingAboveDock
            )

            setPosition(window, x: newPos.x, y: newPos.y)
            debugLog("Moved notification window to \(targetPosition.displayName) at (\(newPos.x), \(newPos.y))")
        }

        pollingEndTime = Date().addingTimeInterval(6.5)
    }

    private func moveAllNotifications() {
        guard let pid: pid_t = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else { return }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows: [AXUIElement] = windowsRef as? [AXUIElement]
        else { return }

        for window in windows {
            if getSubrole(of: window) == "AXSystemDialog" { continue }
            moveNotification(window)
        }
    }

    @objc func showAbout() {
        let aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow.center()
        aboutWindow.title = "About ShoveIt"
        aboutWindow.delegate = self

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 180))

        let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let copyright: String = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

        let elements: [(NSView, CGFloat)] = [
            (createIconView(), 165),
            (createLabel("ShoveIt", font: .boldSystemFont(ofSize: 16)), 110),
            (createLabel("Version \(version)"), 90),
            (createLabel("Notification position control for macOS"), 70),
            (createGitHubButton(), 40),
            (createLabel(copyright, color: .secondaryLabelColor, size: 11), 20),
        ]

        for (view, y) in elements {
            view.frame = NSRect(x: 0, y: y, width: 300, height: 20)
            if view is NSImageView {
                view.frame = NSRect(x: 100, y: y, width: 100, height: 100)
            }
            contentView.addSubview(view)
        }

        aboutWindow.contentView = contentView
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createIconView() -> NSImageView {
        let iconImageView = NSImageView()
        if let iconImage = NSImage(named: "icon") {
            iconImageView.image = iconImage
            iconImageView.imageScaling = .scaleProportionallyDown
        }
        return iconImageView
    }

    private func createLabel(_ text: String, font: NSFont = .systemFont(ofSize: 12), color: NSColor = .labelColor, size _: CGFloat = 12) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.font = font
        label.textColor = color
        return label
    }

    private func createGitHubButton() -> NSButton {
        let button = NSButton()
        button.title = "GitHub"
        button.bezelStyle = .inline
        button.isBordered = false
        button.target = self
        button.action = #selector(openGitHub)
        button.attributedTitle = NSAttributedString(string: "GitHub", attributes: [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        return button
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/JaysonRawlins/ShoveIt")!)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func setupObserver() {
        guard let pid: pid_t = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else { return }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        AXObserverCreate(pid, observerCallback, &observer)
        axObserver = observer

        let selfPtr: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer!, app, kAXWindowCreatedNotification as CFString, selfPtr)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer!), .defaultMode)

        debugLog("Observer setup complete for Notification Center (PID: \(pid))")

        lastKnownWindowCount = getNotificationWindowCount()

        widgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            self.checkForWidgetChanges()
        }

        windowPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.pollForNewWindows()
        }
    }

    private func getNotificationWindowCount() -> Int {
        guard let pid: pid_t = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else { return 0 }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return 0 }

        return windows.count
    }

    private var pollLogCount = 0

    private func pollForNewWindows() {
        guard let pid: pid_t = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else {
            if pollLogCount < 3 { debugLog("Poll: NC not running"); pollLogCount += 1 }
            return
        }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            if pollLogCount < 3 { debugLog("Poll: cannot read windows (AX denied?)"); pollLogCount += 1 }
            return
        }

        // Detect new windows (pre-26.3 path — exclude AXSystemDialog, handled below)
        let nonDialogCount = windows.filter { getSubrole(of: $0) != "AXSystemDialog" }.count
        if nonDialogCount > lastKnownWindowCount {
            moveAllNotifications()
        }
        lastKnownWindowCount = nonDialogCount

        // macOS 26.3+: detect banners inside AXSystemDialog windows
        var foundBanner = false
        for window in windows {
            if getSubrole(of: window) == "AXSystemDialog" {
                if let banner = findElementWithSubrole(root: window, targetSubroles: bannerSubroles),
                   let pos = getPosition(of: banner) {
                    foundBanner = true
                    if !bannerIsActive {
                        if abs(pos.x - lastBannerX) < 2 {
                            bannerStableCount += 1
                        } else {
                            bannerStableCount = 0
                            lastBannerX = pos.x
                        }
                        debugLog("Poll: banner at (\(pos.x), \(pos.y)), stable=\(bannerStableCount), active=\(bannerIsActive)")
                        if bannerStableCount >= 3 {
                            // Store initial dialog position before first move
                            if initialDialogPos == nil {
                                initialDialogPos = getPosition(of: window)
                            }
                            debugLog("Poll: banner stabilized — calling moveNotification")
                            moveNotification(window)
                            bannerIsActive = true
                            bannerStableCount = 0
                        }
                    }
                }
            }
        }

        // Reset when banner dismisses
        if !foundBanner && bannerIsActive {
            // Restore dialog to its initial position so the next notification
            // starts from a clean coordinate space (prevents offset compounding).
            if let initPos = initialDialogPos {
                for window in windows {
                    if getSubrole(of: window) == "AXSystemDialog" {
                        setPosition(window, x: initPos.x, y: initPos.y)
                        debugLog("Poll: banner dismissed — restored dialog to (\(initPos.x), \(initPos.y))")
                    }
                }
            }
            bannerIsActive = false
            bannerStableCount = 0
            lastBannerX = 0
            initialDialogPos = nil
        }
    }

    private func getWindowIdentifier(_ element: AXUIElement) -> String? {
        var identifierRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef) == .success else {
            return nil
        }
        return identifierRef as? String
    }

    private func checkForWidgetChanges() {
        guard let pollingEnd: Date = pollingEndTime, Date() < pollingEnd else { return }

        let hasNCUI: Bool = hasNotificationCenterUI()
        let currentNCState: Int = hasNCUI ? 1 : 0

        if lastWidgetWindowCount != currentNCState {
            if !hasNCUI {
                moveAllNotifications()
            }
        }

        lastWidgetWindowCount = currentNCState
    }

    private func hasNotificationCenterUI() -> Bool {
        guard let pid: pid_t = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier else { return false }

        let app: AXUIElement = AXUIElementCreateApplication(pid)
        return findElementWithWidgetIdentifier(root: app) != nil
    }

    private func findElementWithWidgetIdentifier(root: AXUIElement) -> AXUIElement? {
        if let identifier: String = getWindowIdentifier(root), identifier.hasPrefix("widget-local") {
            return root
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement] else { return nil }

        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithWidgetIdentifier(root: child) {
                return found
            }
        }
        return nil
    }

    func getPosition(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        guard let posVal: AnyObject = positionValue, AXValueGetType(posVal as! AXValue) == .cgPoint else {
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }

    func getSize(of element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let sizeVal: AnyObject = sizeValue, AXValueGetType(sizeVal as! AXValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return size
    }

    private func setPosition(_ element: AXUIElement, x: CGFloat, y: CGFloat) {
        var point = CGPoint(x: x, y: y)
        let value: AXValue = AXValueCreate(.cgPoint, &point)!
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func findElementWithSubrole(root: AXUIElement, targetSubroles: [String]) -> AXUIElement? {
        var subroleRef: AnyObject?
        if AXUIElementCopyAttributeValue(root, kAXSubroleAttribute as CFString, &subroleRef) == .success {
            if let subrole: String = subroleRef as? String, targetSubroles.contains(subrole) {
                return root
            }
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children: [AXUIElement] = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child: AXUIElement in children {
            if let found: AXUIElement = findElementWithSubrole(root: child, targetSubroles: targetSubroles) {
                return found
            }
        }
        return nil
    }
}

private func observerCallback(observer _: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?) {
    let mover: NotificationMover = Unmanaged<NotificationMover>.fromOpaque(context!).takeUnretainedValue()

    let notificationString: String = notification as String
    if notificationString == kAXWindowCreatedNotification as String {
        var subroleRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, subrole == "AXSystemDialog" {
            return
        }
        mover.moveNotification(element)
    }
}

@main
enum ShoveItApp {
    static func main() {
        let app: NSApplication = .shared
        let delegate: NotificationMover = .init()
        app.delegate = delegate
        app.run()
    }
}
