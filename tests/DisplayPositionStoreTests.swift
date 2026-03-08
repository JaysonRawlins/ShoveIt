import Cocoa

func runDisplayPositionStoreTests() {
    print("\nRunning DisplayPositionStore tests...")
    testDefaultPosition()
    testSetAndGetPosition()
    testMultipleDisplays()
    testPersistence()
    testSelectDisplay()
}

func testDefaultPosition() {
    print("  testDefaultPosition")
    let suiteName = "test.ShoveIt.DisplayPositionStore.default"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = DisplayPositionStore(defaults: defaults)
    assertEqual(store.position(for: 1), NotificationPosition.topRight, "default should be topRight")
    assertEqual(store.position(for: 999), NotificationPosition.topRight, "unknown display should be topRight")
}

func testSetAndGetPosition() {
    print("  testSetAndGetPosition")
    let suiteName = "test.ShoveIt.DisplayPositionStore.setget"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = DisplayPositionStore(defaults: defaults)
    store.setPosition(.topMiddle, for: 1)
    assertEqual(store.position(for: 1), NotificationPosition.topMiddle)

    store.setPosition(.bottomLeft, for: 1)
    assertEqual(store.position(for: 1), NotificationPosition.bottomLeft)
}

func testMultipleDisplays() {
    print("  testMultipleDisplays")
    let suiteName = "test.ShoveIt.DisplayPositionStore.multi"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = DisplayPositionStore(defaults: defaults)
    store.setPosition(.topLeft, for: 1)
    store.setPosition(.bottomRight, for: 2)
    store.setPosition(.deadCenter, for: 3)

    assertEqual(store.position(for: 1), NotificationPosition.topLeft)
    assertEqual(store.position(for: 2), NotificationPosition.bottomRight)
    assertEqual(store.position(for: 3), NotificationPosition.deadCenter)
}

func testPersistence() {
    print("  testPersistence")
    let suiteName = "test.ShoveIt.DisplayPositionStore.persist"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store1 = DisplayPositionStore(defaults: defaults)
    store1.setPosition(.middleLeft, for: 42)

    let store2 = DisplayPositionStore(defaults: defaults)
    assertEqual(store2.position(for: 42), NotificationPosition.middleLeft, "position should persist")
}

func testSelectDisplay() {
    print("  testSelectDisplay")
    let suiteName = "test.ShoveIt.DisplayPositionStore.select"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = DisplayPositionStore(defaults: defaults)
    store.selectDisplay(99)
    assertEqual(store.selectedDisplayID, CGDirectDisplayID(99))

    // Verify persistence
    let store2 = DisplayPositionStore(defaults: defaults)
    assertEqual(store2.selectedDisplayID, CGDirectDisplayID(99))
}
