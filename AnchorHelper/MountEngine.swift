import Foundation
import NetFS
import AnchorCore

/// Processes all shares in a config — mounting reachable ones, unmounting unreachable ones.
final class MountEngine {
    private let session = MountSession()

    func processShares(_ config: AnchorConfig, isPro: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for share in config.activeShares {
                group.addTask { await self.processShare(share, isPro: isPro) }
            }
        }
    }

    // MARK: - Per-share logic

    private func processShare(_ share: Share, isPro: Bool) async {
        let currentState = await session.state(for: share.id)

        switch currentState {
        case .mounted:
            let (primaryUp, latencyMs) = await HostProbe.isReachable(share.host)
            if primaryUp {
                // Refresh latency on health check
                MountNotifications.postStateChanged(
                    MountEvent(shareID: share.id, state: .mounted, mountedHost: share.host, latencyMs: latencyMs)
                )
                return
            }
            // Primary is down while we're mounted.
            if isPro, let fallback = share.fallbackHost {
                let (fallbackUp, fbLatency) = await HostProbe.isReachable(fallback)
                if fallbackUp {
                    MountNotifications.postStateChanged(
                        MountEvent(shareID: share.id, state: .mounted, mountedHost: fallback, latencyMs: fbLatency)
                    )
                    return
                }
            }
            if share.unmountWhenUnreachable {
                await unmount(share)
            } else {
                await session.setState(.unreachable, for: share.id)
                MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .unreachable))
            }

        case .unmounted, .unreachable, .error:
            // Pre-flight: detect shares already mounted by any agent (launchd script, etc.)
            if isMountPoint("/Volumes/\(share.shareName)") {
                let (_, latencyMs) = await HostProbe.isReachable(share.host)
                await session.setState(.mounted, for: share.id)
                MountNotifications.postStateChanged(
                    MountEvent(shareID: share.id, state: .mounted, mountedHost: share.host, latencyMs: latencyMs)
                )
                return
            }
            let (primaryUp, _) = await HostProbe.isReachable(share.host)
            if primaryUp {
                await mount(share, usingHost: share.host)
                return
            }
            if isPro, let fallbackHost = share.fallbackHost {
                let (fallbackUp, _) = await HostProbe.isReachable(fallbackHost)
                if fallbackUp {
                    await mount(share, usingHost: fallbackHost)
                    return
                }
            }
            await session.setState(.unreachable, for: share.id)
            MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .unreachable))

        case .mounting:
            return
        }
    }

    // MARK: - Mount via NetFS

    private func mount(_ share: Share, usingHost host: String) async {
        guard let url = share.smbURL(host: host) else { return }
        await session.setState(.mounting, for: share.id)
        MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .mounting))

        let start = Date()
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            DispatchQueue.global(qos: .utility).async {
                var mountPoints: Unmanaged<CFArray>?
                let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, nil, nil, &mountPoints)
                mountPoints?.release()
                continuation.resume(returning: rc)
            }
        }
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)

        // EEXIST (17): volume already mounted at that path — treat as success.
        let newState: MountState = (result == 0 || result == EEXIST) ? .mounted : .error
        await session.setState(newState, for: share.id)
        MountNotifications.postStateChanged(
            MountEvent(shareID: share.id, state: newState,
                       mountedHost: newState == .mounted ? host : nil,
                       latencyMs: newState == .mounted ? latencyMs : nil)
        )
    }

    // MARK: - Mount point detection

    private func isMountPoint(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard let dev  = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemNumber] as? Int,
              let pDev = (try? FileManager.default.attributesOfFileSystem(forPath: parent))?[.systemNumber] as? Int
        else { return false }
        return dev != pDev
    }

    // MARK: - Unmount via diskutil

    private func unmount(_ share: Share) async {
        let volumePath = "/Volumes/\(share.shareName)"
        guard FileManager.default.fileExists(atPath: volumePath) else {
            await session.setState(.unmounted, for: share.id)
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["unmount", "force", volumePath]
        do {
            try task.run()
            task.waitUntilExit()
            let newState: MountState = task.terminationStatus == 0 ? .unmounted : .error
            await session.setState(newState, for: share.id)
            MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: newState))
        } catch {
            await session.setState(.error, for: share.id)
            MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .error))
        }
    }
}
