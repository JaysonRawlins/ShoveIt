import Cocoa

func runPositionStoreTests() {
    print("\nRunning PositionStore tests...")
    testDefaultPosition()
    testSetAndGetPosition()
    testPersistence()
    testSelectedDisplayPersistence()
    testMigrationFromDisplayPositions()
}

func testDefaultPosition() {
    print("  testDefaultPosition")
    let suiteName = "test.ShoveIt.PositionStore.default"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = PositionStore(defaults: defaults)
    assertEqual(store.position, NotificationPosition.topRight, "default should be topRight")
}

func testSetAndGetPosition() {
    print("  testSetAndGetPosition")
    let suiteName = "test.ShoveIt.PositionStore.setget"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = PositionStore(defaults: defaults)
    store.setPosition(.topMiddle)
    assertEqual(store.position, NotificationPosition.topMiddle)

    store.setPosition(.bottomLeft)
    assertEqual(store.position, NotificationPosition.bottomLeft)
}

func testPersistence() {
    print("  testPersistence")
    let suiteName = "test.ShoveIt.PositionStore.persist"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store1 = PositionStore(defaults: defaults)
    store1.setPosition(.middleLeft)

    let store2 = PositionStore(defaults: defaults)
    assertEqual(store2.position, NotificationPosition.middleLeft, "position should persist")
}

func testMigrationFromDisplayPositions() {
    print("  testMigrationFromDisplayPositions")
    let suiteName = "test.ShoveIt.PositionStore.migrate"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    // Set up old-format data
    let mainID = String(CGMainDisplayID())
    defaults.set([mainID: "bottomMiddle"], forKey: "displayPositions")
    defaults.set(Int(CGMainDisplayID()), forKey: "selectedDisplayID")

    let store = PositionStore(defaults: defaults)
    assertEqual(store.position, NotificationPosition.bottomMiddle, "should migrate main display position")

    // Old keys should be cleaned up
    assertEqual(defaults.dictionary(forKey: "displayPositions") == nil, true, "old displayPositions should be removed")
    assertEqual(store.selectedDisplayID, CGDirectDisplayID(CGMainDisplayID()), "selected display should be preserved")
}

func testSelectedDisplayPersistence() {
    print("  testSelectedDisplayPersistence")
    let suiteName = "test.ShoveIt.PositionStore.display"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let displayID = CGDirectDisplayID(4242)
    let store1 = PositionStore(defaults: defaults)
    store1.setSelectedDisplayID(displayID)

    let store2 = PositionStore(defaults: defaults)
    assertEqual(store2.selectedDisplayID, displayID, "selected display should persist")

    store2.setSelectedDisplayID(nil)
    let store3 = PositionStore(defaults: defaults)
    assertEqual(store3.selectedDisplayID == nil, true, "selected display should clear")
}
