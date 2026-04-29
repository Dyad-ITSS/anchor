import Foundation
import ServiceManagement

@MainActor
final class HelperManager: ObservableObject {
    static let shared = HelperManager()

    private let service = SMAppService.loginItem(identifier: "com.dyad-itss.anchor.AnchorHelper")
    private var helperProcess: Process?

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
            // SMAppService requires a signed, provisioned build.
            // For unsigned dev builds, launch the helper binary directly.
            launchHelperDirectly()
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

    // MARK: - Dev build fallback

    /// Locates AnchorHelper next to the app bundle (Xcode derived data layout:
    /// .../Debug/Anchor.app alongside .../Debug/AnchorHelper) and launches it.
    /// Restarts automatically on crash with a 2-second delay.
    private func launchHelperDirectly() {
        guard helperProcess?.isRunning != true else { return }
        guard let execURL = Bundle.main.executableURL else { return }

        // Traverse: binary → MacOS → Contents → Anchor.app → Debug → AnchorHelper
        let helperURL = execURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AnchorHelper")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            print("HelperManager: AnchorHelper not found at \(helperURL.path)")
            return
        }

        let proc = Process()
        proc.executableURL = helperURL
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.helperProcess = nil
                self?.launchHelperDirectly()
            }
        }

        do {
            try proc.run()
            helperProcess = proc
            isRegistered = true
        } catch {
            print("HelperManager: direct launch failed: \(error)")
        }
    }
}
