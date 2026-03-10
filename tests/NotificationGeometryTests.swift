import Foundation

// Lightweight test runner — no XCTest dependency needed for `make test`.

var testCount = 0
var failCount = 0

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    testCount += 1
    guard a == b else {
        failCount += 1
        print("  FAIL (\(file):\(line)): \(a) != \(b) \(msg)")
        return
    }
}

func assertApprox(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat = 0.1, _ msg: String = "", file: String = #file, line: Int = #line) {
    testCount += 1
    guard abs(a - b) <= accuracy else {
        failCount += 1
        print("  FAIL (\(file):\(line)): \(a) !~= \(b) (±\(accuracy)) \(msg)")
        return
    }
}

// --- Test data ---

let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
let visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1010)
let windowSize = CGSize(width: 1920, height: 1080)
let notifSize = CGSize(width: 350, height: 90)
let padding: CGFloat = 16.0
let paddingAboveDock: CGFloat = 30.0
let origin = CGPoint(x: 1920 - 350 - padding, y: 0)

// --- Pre-26.3 newPosition tests ---

func testInitialDataNormalPosition() {
    print("  testInitialDataNormalPosition")
    let result = NotificationGeometry.initialData(
        screenWidth: 1920, notifSize: notifSize, position: CGPoint(x: 1554, y: 0)
    )
    assertApprox(result.padding, 16.0)
    assertApprox(result.effectivePosition.x, 1554)
}

func testInitialDataOffScreenCorrection() {
    print("  testInitialDataOffScreenCorrection")
    let result = NotificationGeometry.initialData(
        screenWidth: 1920, notifSize: notifSize, position: CGPoint(x: 1800, y: 0)
    )
    assertApprox(result.padding, 16.0)
    assertApprox(result.effectivePosition.x, 1554)
}

func testTopRight() {
    print("  testTopRight")
    let pos = NotificationGeometry.newPosition(
        for: .topRight, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: screenFrame, visibleFrame: visibleFrame, paddingAboveDock: paddingAboveDock
    )
    assertApprox(pos.x, 0)
    assertApprox(pos.y, 0)
}

func testTopRightOnSecondaryDisplay() {
    print("  testTopRightOnSecondaryDisplay")
    let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let pos = NotificationGeometry.newPosition(
        for: .topRight, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: secondary, visibleFrame: secondary, paddingAboveDock: paddingAboveDock
    )
    let expectedX = secondary.maxX - notifSize.width - padding - origin.x
    assertApprox(pos.x, expectedX)
    assertApprox(pos.y, 0)
}

func testTopLeft() {
    print("  testTopLeft")
    let pos = NotificationGeometry.newPosition(
        for: .topLeft, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: screenFrame, visibleFrame: visibleFrame, paddingAboveDock: paddingAboveDock
    )
    assertApprox(pos.x, padding - origin.x)
    assertApprox(pos.y, 0)
}

func testTopMiddle() {
    print("  testTopMiddle")
    let pos = NotificationGeometry.newPosition(
        for: .topMiddle, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: screenFrame, visibleFrame: visibleFrame, paddingAboveDock: paddingAboveDock
    )
    let expectedX = (windowSize.width - notifSize.width) / 2 - origin.x
    assertApprox(pos.x, expectedX)
    assertApprox(pos.y, 0)
}

func testBottomMiddle() {
    print("  testBottomMiddle")
    let pos = NotificationGeometry.newPosition(
        for: .bottomMiddle, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: screenFrame, visibleFrame: visibleFrame, paddingAboveDock: paddingAboveDock
    )
    let dockSize = screenFrame.height - visibleFrame.height
    let expectedY = windowSize.height - notifSize.height - dockSize - paddingAboveDock
    assertApprox(pos.y, expectedY)
}

func testDeadCenter() {
    print("  testDeadCenter")
    let pos = NotificationGeometry.newPosition(
        for: .deadCenter, windowSize: windowSize, notifSize: notifSize,
        origin: origin, padding: padding,
        screenFrame: screenFrame, visibleFrame: visibleFrame, paddingAboveDock: paddingAboveDock
    )
    let dockSize = screenFrame.height - visibleFrame.height
    let expectedY = (windowSize.height - notifSize.height) / 2 - dockSize
    assertApprox(pos.y, expectedY)
}

// --- bannerTargetPosition tests (macOS 26.3+) ---

let dialogScreen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let dialogVisible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
let bannerSize = CGSize(width: 344, height: 57)
let defaultBannerPos = CGPoint(x: 2200, y: 46)

func testBannerTopLeft() {
    print("  testBannerTopLeft")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .topLeft,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    assertApprox(pos.x, 16)
    assertApprox(pos.y, 46) // same Y as original
}

func testBannerTopMiddle() {
    print("  testBannerTopMiddle")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .topMiddle,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    // (2560 - 344) / 2 = 1108
    assertApprox(pos.x, 1108)
    assertApprox(pos.y, 46)
}

func testBannerTopRight() {
    print("  testBannerTopRight")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .topRight,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    assertApprox(pos.x, dialogScreen.maxX - bannerSize.width - NotificationGeometry.horizontalPadding)
    assertApprox(pos.y, 46)
}

func testBannerBottomMiddle() {
    print("  testBannerBottomMiddle")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .bottomMiddle,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 1440 - 1410 // 30
    let expectedY: CGFloat = 1440 - 57 - dockSize - 30 // 1323
    assertApprox(pos.x, 1108)
    assertApprox(pos.y, expectedY)
}

func testBannerBottomLeft() {
    print("  testBannerBottomLeft")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .bottomLeft,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 30
    let expectedY: CGFloat = 1440 - 57 - dockSize - 30
    assertApprox(pos.x, 16)
    assertApprox(pos.y, expectedY)
}

func testBannerDeadCenter() {
    print("  testBannerDeadCenter")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .deadCenter,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 30
    let expectedY: CGFloat = (1440 - 57) / 2 - dockSize
    assertApprox(pos.x, 1108)
    assertApprox(pos.y, expectedY)
}

func testBannerMiddleLeft() {
    print("  testBannerMiddleLeft")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .middleLeft,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 30
    let expectedY: CGFloat = (1440 - 57) / 2 - dockSize
    assertApprox(pos.x, 16)
    assertApprox(pos.y, expectedY)
}

func testBannerMiddleRight() {
    print("  testBannerMiddleRight")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .middleRight,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 30
    let expectedY: CGFloat = (1440 - 57) / 2 - dockSize
    assertApprox(pos.x, dialogScreen.maxX - bannerSize.width - NotificationGeometry.horizontalPadding)
    assertApprox(pos.y, expectedY)
}

func testBannerBottomRight() {
    print("  testBannerBottomRight")
    let pos = NotificationGeometry.bannerTargetPosition(
        for: .bottomRight,
        bannerPos: defaultBannerPos, notifSize: bannerSize,
        screenFrame: dialogScreen, visibleFrame: dialogVisible, paddingAboveDock: 30
    )
    let dockSize: CGFloat = 30
    let expectedY: CGFloat = 1440 - 57 - dockSize - 30
    assertApprox(pos.x, dialogScreen.maxX - bannerSize.width - NotificationGeometry.horizontalPadding)
    assertApprox(pos.y, expectedY)
}

// --- Runner function ---

func runNotificationGeometryTests() {
    print("Running NotificationGeometry tests...")
    testInitialDataNormalPosition()
    testInitialDataOffScreenCorrection()
    testTopRight()
    testTopRightOnSecondaryDisplay()
    testTopLeft()
    testTopMiddle()
    testBottomMiddle()
    testDeadCenter()

    print("\nRunning bannerTargetPosition tests (macOS 26.3+)...")
    testBannerTopLeft()
    testBannerTopMiddle()
    testBannerTopRight()
    testBannerBottomMiddle()
    testBannerBottomLeft()
    testBannerDeadCenter()
    testBannerMiddleLeft()
    testBannerMiddleRight()
    testBannerBottomRight()
}
