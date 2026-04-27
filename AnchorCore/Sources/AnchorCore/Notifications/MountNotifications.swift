import Foundation

public enum MountNotifications {
    // TODO: Replace com.yourname.anchor with the real bundle ID before shipping
    /// Posted by AnchorHelper when any share's MountState changes.
    public static let stateChanged = "com.yourname.anchor.mountStateChanged"

    /// Posted by AnchorApp when config is updated (signals helper to reload).
    public static let configUpdated = "com.yourname.anchor.configUpdated"

    // MARK: - Posting (helper side)

    /// Encodes the MountEvent as JSON and posts via DistributedNotificationCenter.
    public static func postStateChanged(_ event: MountEvent) {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(stateChanged),
            object: json,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    // MARK: - Observing (app side)

    /// Returns a token. Caller must hold onto it — releasing it unregisters the observer.
    @discardableResult
    public static func observeStateChanged(handler: @escaping (MountEvent) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(stateChanged),
            object: nil,
            queue: .main
        ) { note in
            guard let json = note.object as? String,
                  let data = json.data(using: .utf8),
                  let event = try? JSONDecoder().decode(MountEvent.self, from: data) else {
                return
            }
            handler(event)
        }
    }

    public static func postConfigUpdated() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(configUpdated),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    @discardableResult
    public static func observeConfigUpdated(handler: @escaping () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(configUpdated),
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
