import Foundation
import AnchorCore

@MainActor
final class HelperApp {
    private let configStore: ConfigStore
    private let mountEngine = MountEngine()
    private let watcher = NetworkWatcher()
    private var configObserver: NSObjectProtocol?
    private var isPro: Bool = false

    init() throws {
        configStore = try ConfigStore()  // Production init — uses App Group container
    }

    func run() async {
        // 1. Load Pro status from Keychain on start
        isPro = ProKeychain.isProUnlocked()

        // 2. Initial mount pass
        await reloadAndMount()

        // 3. Observe config changes posted by AnchorApp
        configObserver = MountNotifications.observeConfigUpdated { [weak self] in
            Task { await self?.reloadAndMount() }
        }

        // 4. React to network path changes (zero-poll, kernel-notified)
        for await _ in watcher.pathUpdates {
            // Debounce — wait 2s for network to settle after interface change
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await reloadAndMount()
        }
    }

    private func reloadAndMount() async {
        do {
            isPro = ProKeychain.isProUnlocked()
            let config = try await configStore.load()
            await mountEngine.processShares(config, isPro: isPro)
        } catch {
            // Config unreadable — do nothing, try again on next network event
        }
    }
}
