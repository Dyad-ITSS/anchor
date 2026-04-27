import Foundation
import ServiceManagement

@MainActor
final class HelperManager: ObservableObject {
    static let shared = HelperManager()
    private let service = SMAppService.loginItem(identifier: "com.yourname.anchor.AnchorHelper")

    @Published private(set) var isRegistered: Bool = false

    private init() {
        isRegistered = service.status == .enabled
    }

    func registerIfNeeded() {
        guard service.status != .enabled else { isRegistered = true; return }
        do {
            try service.register()
            isRegistered = true
        } catch {
            print("HelperManager: register failed: \(error)")
        }
    }

    func unregister() {
        do {
            try service.unregister()
            isRegistered = false
        } catch {
            print("HelperManager: unregister failed: \(error)")
        }
    }
}
