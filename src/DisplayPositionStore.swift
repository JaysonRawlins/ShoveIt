import Cocoa

final class DisplayPositionStore {
    private let defaults: UserDefaults
    private let positionsKey = "displayPositions"
    private let selectedDisplayKey = "selectedDisplayID"

    private(set) var positions: [CGDirectDisplayID: NotificationPosition] = [:]
    private(set) var selectedDisplayID: CGDirectDisplayID

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let dict = defaults.dictionary(forKey: positionsKey) as? [String: String] {
            for (key, value) in dict {
                if let id = UInt32(key), let pos = NotificationPosition(rawValue: value) {
                    positions[id] = pos
                }
            }
        }

        let savedID = defaults.integer(forKey: selectedDisplayKey)
        if savedID != 0 {
            selectedDisplayID = CGDirectDisplayID(savedID)
        } else {
            selectedDisplayID = CGMainDisplayID()
        }
    }

    func position(for displayID: CGDirectDisplayID) -> NotificationPosition {
        positions[displayID] ?? .topRight
    }

    func setPosition(_ position: NotificationPosition, for displayID: CGDirectDisplayID) {
        positions[displayID] = position
        persist()
    }

    func selectDisplay(_ displayID: CGDirectDisplayID) {
        selectedDisplayID = displayID
        defaults.set(Int(displayID), forKey: selectedDisplayKey)
    }

    func pruneDisconnectedDisplays() {
        let connected = Set(Self.connectedDisplayIDs)
        let before = positions.count
        positions = positions.filter { connected.contains($0.key) }
        if positions.count != before {
            persist()
        }
        if !connected.contains(selectedDisplayID) {
            selectedDisplayID = CGMainDisplayID()
            defaults.set(Int(selectedDisplayID), forKey: selectedDisplayKey)
        }
    }

    private func persist() {
        var dict: [String: String] = [:]
        for (id, pos) in positions {
            dict[String(id)] = pos.rawValue
        }
        defaults.set(dict, forKey: positionsKey)
    }

    // MARK: - Static helpers

    static var connectedDisplayIDs: [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        return displays
    }

    static func displayName(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if screen.displayID == displayID {
                return screen.localizedName
            }
        }
        return "Display \(displayID)"
    }

    static var isMultiDisplay: Bool {
        NSScreen.screens.count > 1
    }
}
