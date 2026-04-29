import Foundation
import UserNotifications
import AnchorCore

@MainActor
final class HelperApp {
    private let configStore: ConfigStore
    private let mountEngine = MountEngine()
    private let watcher = NetworkWatcher()
    private var configObserver: NSObjectProtocol?
    private var healthObserver: NSObjectProtocol?
    private var isPro: Bool = false
    private var previousStates: [UUID: MountState] = [:]

    init() {
        configStore = ConfigStore()
    }

    func run() async {
        // 1. Load Pro status from Keychain on start
        isPro = ProKeychain.isProUnlocked()

        // 2. Begin observing share health transitions (Pro only, but wired always)
        observeHealthNotifications()

        // 3. Initial mount pass
        await reloadAndMount()

        // 4. Observe config changes posted by AnchorApp
        configObserver = MountNotifications.observeConfigUpdated { [weak self] in
            Task { await self?.reloadAndMount() }
        }

        // 5. React to network path changes (zero-poll, kernel-notified)
        for await _ in watcher.pathUpdates {
            // Debounce — wait 2s for network to settle after interface change
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await reloadAndMount()
        }
    }

    private func reloadAndMount() async {
        do {
            isPro = ProKeychain.isProUnlocked()
            _ = VPNDetector.detect()  // writes detected VPN to shared UserDefaults
            let config = try await configStore.load()
            await mountEngine.processShares(config, isPro: isPro)
        } catch {
            // Config unreadable — do nothing, try again on next network event
        }
    }

    // MARK: - Health Notifications

    private func observeHealthNotifications() {
        healthObserver = MountNotifications.observeStateChanged { [weak self] event in
            guard let self else { return }
            let prev = self.previousStates[event.shareID]
            self.previousStates[event.shareID] = event.state

            guard self.isPro else { return }  // health notifications are Pro only

            if prev == .mounted && event.state == .unreachable {
                self.postSystemNotification(
                    title: "Share Disconnected",
                    body: "A share went offline. Anchor will reconnect automatically."
                )
            } else if prev == .unreachable && event.state == .mounted {
                self.postSystemNotification(
                    title: "Share Reconnected",
                    body: "Your share is back online."
                )
            }
        }
    }

    private func postSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
