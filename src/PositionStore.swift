import Cocoa

final class PositionStore {
    private let defaults: UserDefaults
    private let positionKey = "notificationPosition"
    private let selectedDisplayIDKey = "selectedDisplayID"
    private var observation: NSKeyValueObservation?

    private(set) var position: NotificationPosition
    private(set) var selectedDisplayID: CGDirectDisplayID?

    var onChange: ((NotificationPosition) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate from old per-display format if needed
        if defaults.string(forKey: positionKey) == nil,
           let dict = defaults.dictionary(forKey: "displayPositions") as? [String: String] {
            // Use the main display's position or the first one found
            let mainID = String(CGMainDisplayID())
            if let raw = dict[mainID] ?? dict.values.first,
               let pos = NotificationPosition(rawValue: raw) {
                defaults.set(pos.rawValue, forKey: positionKey)
            }
            defaults.removeObject(forKey: "displayPositions")
        }

        if let raw = defaults.string(forKey: positionKey),
           let pos = NotificationPosition(rawValue: raw) {
            position = pos
        } else {
            position = .topRight
        }

        let storedDisplayID = defaults.integer(forKey: selectedDisplayIDKey)
        selectedDisplayID = storedDisplayID > 0 ? CGDirectDisplayID(storedDisplayID) : nil

        // Watch for external changes (e.g. `defaults write`)
        observation = defaults.observe(\.notificationPosition, options: [.new]) { [weak self] _, change in
            guard let self,
                  let raw = change.newValue as? String ?? self.defaults.string(forKey: self.positionKey),
                  let pos = NotificationPosition(rawValue: raw),
                  pos != self.position else { return }
            self.position = pos
            self.onChange?(pos)
        }
    }

    func setPosition(_ position: NotificationPosition) {
        self.position = position
        defaults.set(position.rawValue, forKey: positionKey)
    }

    func setSelectedDisplayID(_ displayID: CGDirectDisplayID?) {
        selectedDisplayID = displayID
        if let displayID {
            defaults.set(Int(displayID), forKey: selectedDisplayIDKey)
        } else {
            defaults.removeObject(forKey: selectedDisplayIDKey)
        }
    }
}

// KVO-compatible key path for UserDefaults observation
extension UserDefaults {
    @objc dynamic var notificationPosition: String? {
        string(forKey: "notificationPosition")
    }
}
