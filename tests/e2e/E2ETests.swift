import ApplicationServices
import Cocoa
import Foundation

/// E2E tests that validate notification positioning by:
/// 1. Setting a position in UserDefaults
/// 2. Launching ShoveIt
/// 3. Sending a real notification
/// 4. Reading the banner's AX position
/// 5. Comparing against expected coordinates
///
/// Requirements:
/// - Accessibility permission granted for both ShoveIt.app and this test binary
/// - Run locally (not in CI — requires a display and notification rendering)

private let ncBundleID = "com.apple.notificationcenterui"
private let bannerSubroles = [
    "AXNotificationCenterBanner",
    "AXNotificationCenterAlert",
    "AXNotificationCenterNotification",
    "AXNotificationCenterBannerWindow",
]

private var e2eTestCount = 0
private var e2eFailCount = 0

private func e2eAssert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    e2eTestCount += 1
    if !condition {
        e2eFailCount += 1
        print("  FAIL (\(file):\(line)): \(msg)")
    }
}

// MARK: - AX Helpers

private func getPosition(of element: AXUIElement) -> CGPoint? {
    var positionValue: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
    guard let posVal = positionValue, AXValueGetType(posVal as! AXValue) == .cgPoint else { return nil }
    var position = CGPoint.zero
    AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
    return position
}

private func getSize(of element: AXUIElement) -> CGSize? {
    var sizeValue: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    guard let sizeVal = sizeValue, AXValueGetType(sizeVal as! AXValue) == .cgSize else { return nil }
    var size = CGSize.zero
    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
    return size
}

private func findBanner(root: AXUIElement) -> AXUIElement? {
    var subroleRef: AnyObject?
    if AXUIElementCopyAttributeValue(root, kAXSubroleAttribute as CFString, &subroleRef) == .success {
        if let subrole = subroleRef as? String, bannerSubroles.contains(subrole) {
            return root
        }
    }

    var childrenRef: AnyObject?
    guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return nil }

    for child in children {
        if let found = findBanner(root: child) { return found }
    }
    return nil
}

// MARK: - Test Infrastructure

private func sendNotification(_ message: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", "display notification \"\(message)\" with title \"ShoveIt E2E\""]
    try? task.run()
    task.waitUntilExit()
}

/// Wait for a banner to appear and stabilize, then return its position and size.
private func waitForBanner(timeout: TimeInterval = 5) -> (pos: CGPoint, size: CGSize)? {
    guard let pid = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == ncBundleID
    })?.processIdentifier else { return nil }

    let app = AXUIElementCreateApplication(pid)
    let deadline = Date().addingTimeInterval(timeout)
    var lastPos: CGPoint?
    var stableCount = 0

    while Date() < deadline {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            Thread.sleep(forTimeInterval: 0.1)
            continue
        }

        for window in windows {
            var subroleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, subrole == "AXSystemDialog" {
                if let banner = findBanner(root: window),
                   let pos = getPosition(of: banner),
                   let size = getSize(of: banner) {
                    if let last = lastPos, abs(pos.x - last.x) < 2 && abs(pos.y - last.y) < 2 {
                        stableCount += 1
                        if stableCount >= 5 {
                            return (pos, size)
                        }
                    } else {
                        stableCount = 0
                    }
                    lastPos = pos
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
}

/// Wait for the banner to dismiss.
private func waitForDismiss(timeout: TimeInterval = 8) {
    guard let pid = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == ncBundleID
    })?.processIdentifier else { return }

    let app = AXUIElementCreateApplication(pid)
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }

        var foundBanner = false
        for window in windows {
            var subroleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success,
               let subrole = subroleRef as? String, subrole == "AXSystemDialog" {
                if findBanner(root: window) != nil {
                    foundBanner = true
                }
            }
        }
        if !foundBanner { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
}

private func testPosition(_ position: NotificationPosition, screen: NSScreen) {
    print("  Testing \(position.displayName)...")

    // Set position via ShoveIt's defaults domain
    let task0 = Process()
    task0.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    task0.arguments = ["write", "com.jjrawlins.ShoveIt", "notificationPosition", position.rawValue]
    try? task0.run()
    task0.waitUntilExit()

    // Pause for ShoveIt to pick up the KVO change
    Thread.sleep(forTimeInterval: 0.5)

    // Send notification
    sendNotification("E2E \(position.displayName)")

    // Wait for banner to appear and be repositioned by ShoveIt
    // ShoveIt needs ~300ms to detect + stabilize, then we need stable readings
    Thread.sleep(forTimeInterval: 0.5)

    guard let result = waitForBanner(timeout: 6) else {
        e2eTestCount += 1
        e2eFailCount += 1
        print("  FAIL: No banner found for \(position.displayName)")
        waitForDismiss()
        return
    }

    // Calculate expected position
    let expected = NotificationGeometry.bannerTargetPosition(
        for: position,
        bannerPos: result.pos, // For X on right positions and Y on top positions, expected == actual
        notifSize: result.size,
        screenFrame: screen.frame,
        visibleFrame: screen.visibleFrame,
        paddingAboveDock: 30
    )

    let tolerance: CGFloat = 20

    // For positions that don't change X (right) or Y (top), we can't validate those axes
    // since expected == actual by definition. Validate the axes that should change.
    switch position {
    case .topRight:
        // No change expected — this is the default, ShoveIt skips it
        break
    case .topLeft, .topMiddle:
        e2eAssert(abs(result.pos.x - expected.x) < tolerance,
                  "\(position.displayName) X: got \(result.pos.x), expected \(expected.x)")
    case .bottomLeft, .bottomMiddle, .bottomRight:
        e2eAssert(abs(result.pos.y - expected.y) < tolerance,
                  "\(position.displayName) Y: got \(result.pos.y), expected \(expected.y)")
        if position != .bottomRight {
            e2eAssert(abs(result.pos.x - expected.x) < tolerance,
                      "\(position.displayName) X: got \(result.pos.x), expected \(expected.x)")
        }
    case .middleLeft, .deadCenter, .middleRight:
        e2eAssert(abs(result.pos.y - expected.y) < tolerance,
                  "\(position.displayName) Y: got \(result.pos.y), expected \(expected.y)")
        if position != .middleRight {
            e2eAssert(abs(result.pos.x - expected.x) < tolerance,
                      "\(position.displayName) X: got \(result.pos.x), expected \(expected.x)")
        }
    }

    print("    Position: (\(result.pos.x), \(result.pos.y)), Expected: (\(expected.x), \(expected.y))")

    // Wait for notification to dismiss before next test
    waitForDismiss()
    Thread.sleep(forTimeInterval: 0.5)
}

// MARK: - Main

@main
enum E2ETestRunner {
    static func main() {
        print("ShoveIt E2E Tests")
        print("=================\n")

        // Check accessibility
        guard AXIsProcessTrusted() else {
            print("ERROR: This test binary needs accessibility permission.")
            print("Add it in System Settings > Privacy & Security > Accessibility")
            exit(1)
        }

        // Check ShoveIt is running
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "com.jjrawlins.ShoveIt"
        }) else {
            print("ERROR: ShoveIt.app must be running. Launch it first: make run")
            exit(1)
        }

        guard let screen = NSScreen.main else {
            print("ERROR: No screen detected")
            exit(1)
        }

        print("Screen: \(screen.frame.width)x\(screen.frame.height)")
        print("Visible: \(screen.visibleFrame)")
        print("")

        // Test all non-default positions
        let positions: [NotificationPosition] = [
            .topMiddle, .topLeft,
            .middleLeft, .deadCenter, .middleRight,
            .bottomLeft, .bottomMiddle, .bottomRight,
        ]

        for position in positions {
            testPosition(position, screen: screen)
        }

        // Restore default
        let restoreTask = Process()
        restoreTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        restoreTask.arguments = ["write", "com.jjrawlins.ShoveIt", "notificationPosition", "topRight"]
        try? restoreTask.run()
        restoreTask.waitUntilExit()

        print("")
        if e2eFailCount > 0 {
            print("\(e2eFailCount)/\(e2eTestCount) E2E assertions FAILED")
            exit(1)
        } else {
            print("All \(e2eTestCount) E2E assertions passed.")
        }
    }
}
