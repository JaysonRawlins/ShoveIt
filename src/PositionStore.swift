import Cocoa

final class PositionStore {
    private let defaults: UserDefaults
    private let key = "notificationPosition"
    private var observation: NSKeyValueObservation?

    private(set) var position: NotificationPosition

    var onChange: ((NotificationPosition) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Migrate from old per-display format if needed
        if defaults.string(forKey: key) == nil,
           let dict = defaults.dictionary(forKey: "displayPositions") as? [String: String] {
            // Use the main display's position or the first one found
            let mainID = String(CGMainDisplayID())
            if let raw = dict[mainID] ?? dict.values.first,
               let pos = NotificationPosition(rawValue: raw) {
                defaults.set(pos.rawValue, forKey: key)
            }
            defaults.removeObject(forKey: "displayPositions")
            defaults.removeObject(forKey: "selectedDisplayID")
        }

        if let raw = defaults.string(forKey: key),
           let pos = NotificationPosition(rawValue: raw) {
            position = pos
        } else {
            position = .topRight
        }

        // Watch for external changes (e.g. `defaults write`)
        observation = defaults.observe(\.notificationPosition, options: [.new]) { [weak self] _, change in
            guard let self,
                  let raw = change.newValue as? String ?? self.defaults.string(forKey: self.key),
                  let pos = NotificationPosition(rawValue: raw),
                  pos != self.position else { return }
            self.position = pos
            self.onChange?(pos)
        }
    }

    func setPosition(_ position: NotificationPosition) {
        self.position = position
        defaults.set(position.rawValue, forKey: key)
    }
}

// KVO-compatible key path for UserDefaults observation
extension UserDefaults {
    @objc dynamic var notificationPosition: String? {
        string(forKey: "notificationPosition")
    }
}
