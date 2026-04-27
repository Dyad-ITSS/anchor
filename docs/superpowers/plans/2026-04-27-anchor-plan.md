# Anchor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Anchor — a macOS menu bar app that auto-mounts SMB/NFS shares with mesh VPN-aware smart routing, published on the Mac App Store as free + $9.99 Pro.

**Architecture:** Two-process model: `AnchorApp` (SwiftUI menu bar UI) + `AnchorHelper` (SMAppService login helper that does all mounting). They share config via a JSON file in an App Group container and communicate status via Darwin Distributed Notifications. No root required.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit, Network.framework, NetFS.framework, Security.framework, ServiceManagement, StoreKit 2, RevenueCat SDK. Minimum macOS 13.0 Ventura.

---

## File Map

```
anchor/
├── Anchor.xcodeproj/
├── AnchorCore/                         # Local Swift package — shared by both targets
│   ├── Package.swift
│   └── Sources/AnchorCore/
│       ├── Models/Share.swift          # Share struct (Codable, Identifiable)
│       ├── Models/AnchorConfig.swift   # AnchorConfig + profile filtering
│       ├── Models/MountState.swift     # MountState enum + MountEvent
│       ├── Config/AppGroup.swift       # App Group ID + container URL
│       ├── Config/ConfigStore.swift    # Read/write AnchorConfig JSON to App Group
│       ├── Keychain/ProKeychain.swift  # Store/read Pro entitlement token (Keychain)
│       └── Notifications/MountNotifications.swift  # Darwin notification names + helpers
├── AnchorCore/Tests/AnchorCoreTests/
│   ├── ShareTests.swift
│   ├── AnchorConfigTests.swift
│   ├── ConfigStoreTests.swift
│   └── ProKeychainTests.swift
├── AnchorApp/
│   ├── AnchorApp.swift                 # @main, hides dock icon
│   ├── AppDelegate.swift               # NSStatusItem creation
│   ├── MenuBarController.swift         # Menu construction + icon state
│   ├── HelperManager.swift             # SMAppService register/status
│   ├── Views/SettingsView.swift        # TabView (3 tabs)
│   ├── Views/SharesTabView.swift       # Share list + add/edit/remove
│   ├── Views/ShareEditSheet.swift      # Add/edit share form
│   ├── Views/ProfilesTabView.swift     # Profiles (Pro gated)
│   ├── Views/AboutTabView.swift        # Version + Pro status + restore
│   ├── Store/StoreManager.swift        # StoreKit 2 product + purchase
│   └── Store/EntitlementManager.swift  # RevenueCat + Pro state (ObservableObject)
├── AnchorHelper/
│   ├── main.swift                      # Entry point: RunLoop.main
│   ├── HelperApp.swift                 # Top-level coordinator
│   ├── NetworkWatcher.swift            # NWPathMonitor → async stream of path events
│   ├── HostProbe.swift                 # TCP port 445 reachability, 1s timeout
│   ├── MountEngine.swift               # mount/unmount via NetFS + routing logic
│   ├── MountSession.swift              # Per-share in-memory MountState tracking
│   └── VPNDetector.swift               # Tailscale/NetBird/ZeroTier detection (Pro)
└── docs/
    ├── specs/2026-04-27-anchor-design.md
    └── superpowers/plans/2026-04-27-anchor-plan.md
```

---

# Phase 1 — Core

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `Anchor.xcodeproj/` (via Xcode)
- Create: `AnchorCore/Package.swift`
- Create: `AnchorApp/Info.plist`
- Create: `AnchorHelper/Info.plist`

- [ ] **Step 1: Create the Xcode project**

  In Xcode → File → New → Project → macOS → App.
  - Product Name: `Anchor`
  - Bundle ID: `com.yourname.anchor` (replace `yourname`)
  - Language: Swift, Interface: SwiftUI
  - Uncheck "Include Tests" (we'll add them per-target manually)

- [ ] **Step 2: Add AnchorHelper target**

  File → New → Target → macOS → Command Line Tool.
  - Product Name: `AnchorHelper`
  - Language: Swift

- [ ] **Step 3: Hide the dock icon for AnchorApp**

  In `AnchorApp/Info.plist`, add:
  ```xml
  <key>LSUIElement</key>
  <true/>
  ```

- [ ] **Step 4: Create the AnchorCore local package**

  File → New → Package → save as `AnchorCore/` inside the project root.
  - Name: `AnchorCore`
  - Default library product.

  Replace generated `Package.swift` with:
  ```swift
  // swift-tools-version: 5.9
  import PackageDescription

  let package = Package(
      name: "AnchorCore",
      platforms: [.macOS(.v13)],
      products: [
          .library(name: "AnchorCore", targets: ["AnchorCore"]),
      ],
      targets: [
          .target(name: "AnchorCore", path: "Sources/AnchorCore"),
          .testTarget(name: "AnchorCoreTests", dependencies: ["AnchorCore"], path: "Tests/AnchorCoreTests"),
      ]
  )
  ```

- [ ] **Step 5: Add AnchorCore as a dependency to both targets**

  In Xcode → Project → select `Anchor` target → General → Frameworks and Libraries → `+` → Add Package → Local → select `AnchorCore/`. Repeat for `AnchorHelper` target.

- [ ] **Step 6: Configure App Group entitlement**

  In Xcode → select `Anchor` target → Signing & Capabilities → `+` → App Groups.
  Add group: `group.com.yourname.anchor`

  Repeat for `AnchorHelper` target. Both must use the same group ID.

- [ ] **Step 7: Set deployment target on all targets**

  `Anchor` target → General → Minimum Deployments → macOS 13.0
  `AnchorHelper` target → General → Minimum Deployments → macOS 13.0
  `AnchorCore` Package.swift already declares `.macOS(.v13)` ✓

- [ ] **Step 8: Create source directories and placeholder files**

  ```bash
  mkdir -p /Users/mikezieseniss/dev/anchor/AnchorCore/Sources/AnchorCore/{Models,Config,Keychain,Notifications}
  mkdir -p /Users/mikezieseniss/dev/anchor/AnchorCore/Tests/AnchorCoreTests
  mkdir -p /Users/mikezieseniss/dev/anchor/AnchorApp/{Views,Store}
  touch /Users/mikezieseniss/dev/anchor/AnchorCore/Sources/AnchorCore/Models/.gitkeep
  ```

- [ ] **Step 9: Verify the build compiles clean**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -5
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10: Initial commit**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  git init
  echo ".DS_Store\n*.xcuserstate\nxcuserdata/\n.build/\n" > .gitignore
  git add .
  git commit -m "chore: initial Xcode project scaffold — AnchorApp + AnchorHelper + AnchorCore package"
  ```

---

## Task 2: Core Data Models

**Files:**
- Create: `AnchorCore/Sources/AnchorCore/Models/Share.swift`
- Create: `AnchorCore/Sources/AnchorCore/Models/AnchorConfig.swift`
- Create: `AnchorCore/Sources/AnchorCore/Models/MountState.swift`
- Test: `AnchorCore/Tests/AnchorCoreTests/ShareTests.swift`
- Test: `AnchorCore/Tests/AnchorCoreTests/AnchorConfigTests.swift`

- [ ] **Step 1: Write failing tests for Share**

  Create `AnchorCore/Tests/AnchorCoreTests/ShareTests.swift`:
  ```swift
  import XCTest
  @testable import AnchorCore

  final class ShareTests: XCTestCase {
      func testShareDefaultsPortNil() {
          let s = Share(displayName: "NAS", host: "192.168.0.99", shareName: "data")
          XCTAssertNil(s.port)
          XCTAssertNil(s.username)
          XCTAssertNil(s.fallbackHost)
          XCTAssertTrue(s.unmountWhenUnreachable)
          XCTAssertTrue(s.profiles.isEmpty)
      }

      func testShareRoundTripsJSON() throws {
          var s = Share(displayName: "Office", host: "10.0.4.1", shareName: "Dyad Capital")
          s.username = "mike"
          s.fallbackHost = "100.64.93.215"
          s.profiles = ["office"]
          let data = try JSONEncoder().encode(s)
          let decoded = try JSONDecoder().decode(Share.self, from: data)
          XCTAssertEqual(s.id, decoded.id)
          XCTAssertEqual(s.displayName, decoded.displayName)
          XCTAssertEqual(s.host, decoded.host)
          XCTAssertEqual(s.shareName, decoded.shareName)
          XCTAssertEqual(s.username, decoded.username)
          XCTAssertEqual(s.fallbackHost, decoded.fallbackHost)
          XCTAssertEqual(s.profiles, decoded.profiles)
      }

      func testSMBURLNoUser() {
          let s = Share(displayName: "NAS", host: "192.168.0.99", shareName: "data")
          XCTAssertEqual(s.smbURL(host: s.host), URL(string: "smb://192.168.0.99/data"))
      }

      func testSMBURLWithUser() {
          var s = Share(displayName: "NAS", host: "10.0.4.250", shareName: "SCANS")
          s.username = "4tech"
          XCTAssertEqual(s.smbURL(host: s.host), URL(string: "smb://4tech@10.0.4.250/SCANS"))
      }

      func testSMBURLEncodesSpaces() {
          let s = Share(displayName: "Server", host: "10.0.4.1", shareName: "Dyad Capital")
          XCTAssertEqual(s.smbURL(host: s.host), URL(string: "smb://10.0.4.1/Dyad%20Capital"))
      }
  }
  ```

- [ ] **Step 2: Run tests — expect compile failure (Share not defined)**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|PASSED"
  ```
  Expected: compile error `cannot find type 'Share'`

- [ ] **Step 3: Implement Share.swift**

  Create `AnchorCore/Sources/AnchorCore/Models/Share.swift`:
  ```swift
  import Foundation

  public struct Share: Codable, Identifiable, Equatable {
      public var id: UUID
      public var displayName: String
      public var host: String
      public var shareName: String
      public var username: String?
      public var port: Int?
      public var unmountWhenUnreachable: Bool
      public var fallbackHost: String?
      public var profiles: Set<String>

      public init(
          id: UUID = UUID(),
          displayName: String,
          host: String,
          shareName: String,
          username: String? = nil,
          port: Int? = nil,
          unmountWhenUnreachable: Bool = true,
          fallbackHost: String? = nil,
          profiles: Set<String> = []
      ) {
          self.id = id
          self.displayName = displayName
          self.host = host
          self.shareName = shareName
          self.username = username
          self.port = port
          self.unmountWhenUnreachable = unmountWhenUnreachable
          self.fallbackHost = fallbackHost
          self.profiles = profiles
      }

      public func smbURL(host targetHost: String) -> URL? {
          let encodedShare = shareName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareName
          let userPart = username.map { "\($0)@" } ?? ""
          return URL(string: "smb://\(userPart)\(targetHost)/\(encodedShare)")
      }
  }
  ```

- [ ] **Step 4: Write failing tests for AnchorConfig**

  Create `AnchorCore/Tests/AnchorCoreTests/AnchorConfigTests.swift`:
  ```swift
  import XCTest
  @testable import AnchorCore

  final class AnchorConfigTests: XCTestCase {
      func testEmptyConfigRoundTrips() throws {
          let config = AnchorConfig()
          let data = try JSONEncoder().encode(config)
          let decoded = try JSONDecoder().decode(AnchorConfig.self, from: data)
          XCTAssertTrue(decoded.shares.isEmpty)
          XCTAssertNil(decoded.activeProfile)
          XCTAssertEqual(decoded.schemaVersion, 1)
      }

      func testSharesForProfileFiltersCorrectly() {
          var config = AnchorConfig()
          var s1 = Share(displayName: "Home NAS", host: "192.168.0.99", shareName: "data")
          s1.profiles = ["home"]
          var s2 = Share(displayName: "Office", host: "10.0.4.1", shareName: "files")
          s2.profiles = ["office"]
          let s3 = Share(displayName: "Always", host: "10.0.4.10", shareName: "media")
          // s3 has no profiles — always included
          config.shares = [s1, s2, s3]
          config.activeProfile = "home"

          let filtered = config.activeShares
          XCTAssertEqual(filtered.count, 2)
          XCTAssertTrue(filtered.contains(where: { $0.displayName == "Home NAS" }))
          XCTAssertTrue(filtered.contains(where: { $0.displayName == "Always" }))
          XCTAssertFalse(filtered.contains(where: { $0.displayName == "Office" }))
      }

      func testSharesForNilProfileReturnsAll() {
          var config = AnchorConfig()
          var s1 = Share(displayName: "A", host: "h1", shareName: "s1")
          s1.profiles = ["home"]
          config.shares = [s1]
          config.activeProfile = nil
          XCTAssertEqual(config.activeShares.count, 1)
      }
  }
  ```

- [ ] **Step 5: Implement AnchorConfig.swift and MountState.swift**

  Create `AnchorCore/Sources/AnchorCore/Models/AnchorConfig.swift`:
  ```swift
  import Foundation

  public struct AnchorConfig: Codable {
      public var shares: [Share]
      public var activeProfile: String?
      public var schemaVersion: Int

      public init(shares: [Share] = [], activeProfile: String? = nil, schemaVersion: Int = 1) {
          self.shares = shares
          self.activeProfile = activeProfile
          self.schemaVersion = schemaVersion
      }

      /// Shares active under current profile.
      /// Shares with empty profiles are always included.
      /// When activeProfile is nil, all shares are returned.
      public var activeShares: [Share] {
          guard let profile = activeProfile else { return shares }
          return shares.filter { $0.profiles.isEmpty || $0.profiles.contains(profile) }
      }
  }
  ```

  Create `AnchorCore/Sources/AnchorCore/Models/MountState.swift`:
  ```swift
  import Foundation

  public enum MountState: String, Codable, Equatable {
      case mounted
      case unmounted
      case unreachable
      case mounting
      case error
  }

  public struct MountEvent: Codable {
      public let shareID: UUID
      public let state: MountState
      public let mountedHost: String?  // which host was actually used (primary or fallback)

      public init(shareID: UUID, state: MountState, mountedHost: String? = nil) {
          self.shareID = shareID
          self.state = state
          self.mountedHost = mountedHost
      }
  }
  ```

- [ ] **Step 6: Run tests — expect all pass**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep -E "Test.*passed|FAILED|error:"
  ```
  Expected: `Test Suite 'AnchorCoreTests' passed`

- [ ] **Step 7: Commit**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  git add AnchorCore/
  git commit -m "feat: AnchorCore models — Share, AnchorConfig, MountState"
  ```

---

## Task 3: App Group Constants + ConfigStore

**Files:**
- Create: `AnchorCore/Sources/AnchorCore/Config/AppGroup.swift`
- Create: `AnchorCore/Sources/AnchorCore/Config/ConfigStore.swift`
- Test: `AnchorCore/Tests/AnchorCoreTests/ConfigStoreTests.swift`

- [ ] **Step 1: Write failing ConfigStore tests**

  Create `AnchorCore/Tests/AnchorCoreTests/ConfigStoreTests.swift`:
  ```swift
  import XCTest
  @testable import AnchorCore

  final class ConfigStoreTests: XCTestCase {
      var store: ConfigStore!
      var tempURL: URL!

      override func setUp() {
          super.setUp()
          tempURL = FileManager.default.temporaryDirectory
              .appendingPathComponent("anchor-test-\(UUID().uuidString).json")
          store = ConfigStore(fileURL: tempURL)
      }

      override func tearDown() {
          try? FileManager.default.removeItem(at: tempURL)
          super.tearDown()
      }

      func testSaveAndLoad() throws {
          var config = AnchorConfig()
          config.shares = [Share(displayName: "NAS", host: "192.168.0.99", shareName: "data")]
          try store.save(config)
          let loaded = try store.load()
          XCTAssertEqual(loaded.shares.count, 1)
          XCTAssertEqual(loaded.shares[0].displayName, "NAS")
      }

      func testLoadMissingFileReturnsDefault() throws {
          let loaded = try store.load()
          XCTAssertTrue(loaded.shares.isEmpty)
      }

      func testSaveOverwrites() throws {
          var config = AnchorConfig()
          config.shares = [Share(displayName: "A", host: "h", shareName: "s")]
          try store.save(config)
          config.shares = []
          try store.save(config)
          let loaded = try store.load()
          XCTAssertTrue(loaded.shares.isEmpty)
      }
  }
  ```

- [ ] **Step 2: Run — expect compile error**

  ```bash
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep "error:"
  ```
  Expected: `cannot find type 'ConfigStore'`

- [ ] **Step 3: Implement AppGroup.swift**

  Create `AnchorCore/Sources/AnchorCore/Config/AppGroup.swift`:
  ```swift
  import Foundation

  public enum AppGroup {
      // Must match the App Group entitlement in both targets.
      public static let id = "group.com.yourname.anchor"

      public static var containerURL: URL? {
          FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
      }

      public static var configFileURL: URL? {
          containerURL?.appendingPathComponent("config.json")
      }
  }
  ```

- [ ] **Step 4: Implement ConfigStore.swift**

  Create `AnchorCore/Sources/AnchorCore/Config/ConfigStore.swift`:
  ```swift
  import Foundation

  public final class ConfigStore {
      private let fileURL: URL
      private let encoder = JSONEncoder()
      private let decoder = JSONDecoder()

      /// Production init uses the shared App Group container.
      public convenience init() throws {
          guard let url = AppGroup.configFileURL else {
              throw ConfigStoreError.appGroupUnavailable
          }
          self.init(fileURL: url)
      }

      /// Test init with explicit file URL.
      public init(fileURL: URL) {
          self.fileURL = fileURL
          encoder.outputFormatting = .prettyPrinted
      }

      public func load() throws -> AnchorConfig {
          guard FileManager.default.fileExists(atPath: fileURL.path) else {
              return AnchorConfig()
          }
          let data = try Data(contentsOf: fileURL)
          return try decoder.decode(AnchorConfig.self, from: data)
      }

      public func save(_ config: AnchorConfig) throws {
          let data = try encoder.encode(config)
          try data.write(to: fileURL, options: .atomic)
      }
  }

  public enum ConfigStoreError: Error {
      case appGroupUnavailable
  }
  ```

- [ ] **Step 5: Run tests — expect pass**

  ```bash
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep -E "passed|FAILED"
  ```
  Expected: `Test Suite 'AnchorCoreTests' passed`

- [ ] **Step 6: Commit**

  ```bash
  git add AnchorCore/
  git commit -m "feat: ConfigStore — read/write AnchorConfig JSON to App Group container"
  ```

---

## Task 4: Mount Notifications

**Files:**
- Create: `AnchorCore/Sources/AnchorCore/Notifications/MountNotifications.swift`

- [ ] **Step 1: Implement MountNotifications.swift**

  Darwin Distributed Notifications cross process boundaries — perfect for helper → app status updates. No XCTest for notification posting (requires system integration), but the payload encoding is tested via the existing JSON tests.

  Create `AnchorCore/Sources/AnchorCore/Notifications/MountNotifications.swift`:
  ```swift
  import Foundation

  public enum MountNotifications {
      /// Posted by AnchorHelper when any share's MountState changes.
      public static let stateChanged = "com.yourname.anchor.mountStateChanged"

      /// Posted by AnchorApp when config is updated (signals helper to reload).
      public static let configUpdated = "com.yourname.anchor.configUpdated"

      // MARK: - Posting (helper side)

      public static func postStateChanged(_ event: MountEvent) {
          guard let data = try? JSONEncoder().encode(event),
                let json = String(data: data, encoding: .utf8) else { return }
          DistributedNotificationCenter.default().postNotificationName(
              NSNotification.Name(stateChanged),
              object: json,
              userInfo: nil,
              deliverImmediately: true
          )
      }

      // MARK: - Observing (app side)

      /// Returns a token. Hold onto it; releasing it unregisters the observer.
      @discardableResult
      public static func observeStateChanged(
          handler: @escaping (MountEvent) -> Void
      ) -> NSObjectProtocol {
          DistributedNotificationCenter.default().addObserver(
              forName: NSNotification.Name(stateChanged),
              object: nil,
              queue: .main
          ) { note in
              guard let json = note.object as? String,
                    let data = json.data(using: .utf8),
                    let event = try? JSONDecoder().decode(MountEvent.self, from: data)
              else { return }
              handler(event)
          }
      }

      public static func postConfigUpdated() {
          DistributedNotificationCenter.default().postNotificationName(
              NSNotification.Name(configUpdated),
              object: nil,
              deliverImmediately: true
          )
      }

      @discardableResult
      public static func observeConfigUpdated(handler: @escaping () -> Void) -> NSObjectProtocol {
          DistributedNotificationCenter.default().addObserver(
              forName: NSNotification.Name(configUpdated),
              object: nil,
              queue: .main
          ) { _ in handler() }
      }
  }
  ```

- [ ] **Step 2: Build to verify no compile errors**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add AnchorCore/
  git commit -m "feat: MountNotifications — Darwin distributed notification helpers"
  ```

---

## Task 5: HostProbe (TCP Reachability)

**Files:**
- Create: `AnchorHelper/HostProbe.swift`

- [ ] **Step 1: Implement HostProbe.swift**

  TCP port 445 check with 1s timeout. No XCTest (requires live network); manual test in Task 9.

  Create `AnchorHelper/HostProbe.swift`:
  ```swift
  import Foundation
  import Network

  /// Checks whether a host accepts TCP connections on port 445 within the given timeout.
  enum HostProbe {
      static func isReachable(_ host: String, port: UInt16 = 445, timeout: TimeInterval = 1.0) async -> Bool {
          await withCheckedContinuation { continuation in
              let connection = NWConnection(
                  host: NWEndpoint.Host(host),
                  port: NWEndpoint.Port(rawValue: port)!,
                  using: .tcp
              )
              var resolved = false
              let timer = DispatchWorkItem {
                  guard !resolved else { return }
                  resolved = true
                  connection.cancel()
                  continuation.resume(returning: false)
              }
              DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

              connection.stateUpdateHandler = { state in
                  switch state {
                  case .ready:
                      guard !resolved else { return }
                      resolved = true
                      timer.cancel()
                      connection.cancel()
                      continuation.resume(returning: true)
                  case .failed, .cancelled:
                      guard !resolved else { return }
                      resolved = true
                      timer.cancel()
                      continuation.resume(returning: false)
                  default:
                      break
                  }
              }
              connection.start(queue: .global())
          }
      }
  }
  ```

- [ ] **Step 2: Build AnchorHelper to verify no errors**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add AnchorHelper/HostProbe.swift
  git commit -m "feat: HostProbe — async TCP port 445 reachability check with 1s timeout"
  ```

---

## Task 6: NetworkWatcher

**Files:**
- Create: `AnchorHelper/NetworkWatcher.swift`

- [ ] **Step 1: Implement NetworkWatcher.swift**

  Wraps `NWPathMonitor` and publishes path-change events as an `AsyncStream`. Zero CPU overhead between events — the kernel notifies us.

  Create `AnchorHelper/NetworkWatcher.swift`:
  ```swift
  import Foundation
  import Network

  /// Emits a value whenever the network path changes (interface up/down, WiFi change, VPN connect).
  final class NetworkWatcher {
      private let monitor = NWPathMonitor()
      private let queue = DispatchQueue(label: "com.yourname.anchor.networkwatcher")

      var pathUpdates: AsyncStream<NWPath> {
          AsyncStream { continuation in
              monitor.pathUpdateHandler = { path in
                  continuation.yield(path)
              }
              continuation.onTermination = { [weak self] _ in
                  self?.monitor.cancel()
              }
              monitor.start(queue: queue)
          }
      }

      deinit {
          monitor.cancel()
      }
  }
  ```

- [ ] **Step 2: Build AnchorHelper**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add AnchorHelper/NetworkWatcher.swift
  git commit -m "feat: NetworkWatcher — NWPathMonitor as AsyncStream"
  ```

---

## Task 7: MountSession (Per-share State Tracking)

**Files:**
- Create: `AnchorHelper/MountSession.swift`

- [ ] **Step 1: Implement MountSession.swift**

  Tracks the current `MountState` for each share in memory. The helper consults this before deciding whether to mount or unmount.

  Create `AnchorHelper/MountSession.swift`:
  ```swift
  import Foundation
  import AnchorCore

  /// Thread-safe in-memory store of per-share mount states.
  final class MountSession {
      private var states: [UUID: MountState] = [:]
      private let lock = NSLock()

      func state(for shareID: UUID) -> MountState {
          lock.lock(); defer { lock.unlock() }
          return states[shareID] ?? .unmounted
      }

      func setState(_ state: MountState, for shareID: UUID) {
          lock.lock(); defer { lock.unlock() }
          states[shareID] = state
      }

      func reset() {
          lock.lock(); defer { lock.unlock() }
          states.removeAll()
      }
  }
  ```

- [ ] **Step 2: Build**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add AnchorHelper/MountSession.swift
  git commit -m "feat: MountSession — thread-safe per-share MountState store"
  ```

---

## Task 8: MountEngine (NetFS Mounting)

**Files:**
- Create: `AnchorHelper/MountEngine.swift`

- [ ] **Step 1: Implement MountEngine.swift**

  NetFS mounts the share using Keychain credentials silently. The `NetFSMountURLAsync` function is the modern API (macOS 10.7+). We call it synchronously via a semaphore since we're already in an async context.

  Create `AnchorHelper/MountEngine.swift`:
  ```swift
  import Foundation
  import NetFS
  import AnchorCore

  final class MountEngine {
      private let session = MountSession()

      /// Process all shares in config — mount reachable ones, unmount unreachable ones.
      func processShares(_ config: AnchorConfig, isPro: Bool) async {
          let shares = config.activeShares
          await withTaskGroup(of: Void.self) { group in
              for share in shares {
                  group.addTask {
                      await self.processShare(share, isPro: isPro)
                  }
              }
          }
      }

      private func processShare(_ share: Share, isPro: Bool) async {
          let currentState = session.state(for: share.id)
          let primaryUp = await HostProbe.isReachable(share.host)

          if currentState == .mounted {
              if !primaryUp {
                  let fallbackUp = isPro ? await checkFallback(share) : false
                  if !fallbackUp && share.unmountWhenUnreachable {
                      await unmount(share)
                  }
              }
              return
          }

          if primaryUp {
              await mount(share, usingHost: share.host)
              return
          }

          if isPro, let fallback = share.fallbackHost {
              let fallbackUp = await HostProbe.isReachable(fallback)
              if fallbackUp {
                  await mount(share, usingHost: fallback)
                  return
              }
          }

          if currentState != .unreachable {
              session.setState(.unreachable, for: share.id)
              MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .unreachable))
          }
      }

      private func checkFallback(_ share: Share) async -> Bool {
          guard let fallback = share.fallbackHost else { return false }
          return await HostProbe.isReachable(fallback)
      }

      private func mount(_ share: Share, usingHost host: String) async {
          guard let url = share.smbURL(host: host) else { return }
          session.setState(.mounting, for: share.id)
          MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .mounting))

          let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
              var mountPoints: NSArray?
              let rc = NetFSMountURLSync(
                  url as CFURL,
                  nil,          // mountPath — nil = /Volumes
                  nil,          // user — nil = use Keychain
                  nil,          // password — nil = use Keychain
                  nil,          // open options
                  nil,          // mount options
                  &mountPoints
              )
              continuation.resume(returning: rc)
          }

          let newState: MountState = (result == 0) ? .mounted : .error
          session.setState(newState, for: share.id)
          MountNotifications.postStateChanged(
              MountEvent(shareID: share.id, state: newState, mountedHost: newState == .mounted ? host : nil)
          )
      }

      private func unmount(_ share: Share) async {
          // Find the mounted volume path by scanning /Volumes for our share name
          let volumePath = "/Volumes/\(share.shareName)"
          guard FileManager.default.fileExists(atPath: volumePath) else {
              session.setState(.unmounted, for: share.id)
              return
          }
          let task = Process()
          task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
          task.arguments = ["unmount", "force", volumePath]
          try? task.run()
          task.waitUntilExit()
          session.setState(.unmounted, for: share.id)
          MountNotifications.postStateChanged(MountEvent(shareID: share.id, state: .unmounted))
      }
  }
  ```

  > **Note:** `NetFSMountURLSync` is the synchronous NetFS call. Import the framework by adding `NetFS.framework` to AnchorHelper's "Link Binary With Libraries" in Xcode → Build Phases.

- [ ] **Step 2: Add NetFS to AnchorHelper target**

  In Xcode → AnchorHelper target → Build Phases → Link Binary With Libraries → `+` → search `NetFS` → add `NetFS.framework`.

- [ ] **Step 3: Build**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorHelper/MountEngine.swift
  git commit -m "feat: MountEngine — NetFS mounting with primary/fallback routing"
  ```

---

## Task 9: AnchorHelper Entry Point

**Files:**
- Create: `AnchorHelper/HelperApp.swift`
- Modify: `AnchorHelper/main.swift`

- [ ] **Step 1: Implement HelperApp.swift**

  Create `AnchorHelper/HelperApp.swift`:
  ```swift
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
          configStore = try ConfigStore()
      }

      func run() async {
          // Load Pro status from Keychain on start
          isPro = ProKeychain.isProUnlocked()

          // Initial mount pass
          await reloadAndMount()

          // Observe config changes from AnchorApp
          configObserver = MountNotifications.observeConfigUpdated { [weak self] in
              Task { await self?.reloadAndMount() }
          }

          // React to network path changes
          for await _ in watcher.pathUpdates {
              // Debounce: wait 2s for network to settle after interface change
              try? await Task.sleep(nanoseconds: 2_000_000_000)
              await reloadAndMount()
          }
      }

      private func reloadAndMount() async {
          do {
              isPro = ProKeychain.isProUnlocked()
              let config = try configStore.load()
              await mountEngine.processShares(config, isPro: isPro)
          } catch {
              // Log silently — if config can't be read, do nothing
          }
      }
  }
  ```

- [ ] **Step 2: Implement main.swift**

  Replace generated content in `AnchorHelper/main.swift`:
  ```swift
  import Foundation

  let app = try! HelperApp()
  Task { await app.run() }
  RunLoop.main.run()
  ```

- [ ] **Step 3: Build AnchorHelper**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Smoke test — run helper manually**

  ```bash
  /Users/mikezieseniss/dev/anchor/build/Debug/AnchorHelper &
  sleep 3
  ls /Volumes/
  kill %1
  ```
  Expected: helper starts without crashing. Shares mount if config exists. (Config will be empty on first run — that's fine.)

- [ ] **Step 5: Commit**

  ```bash
  git add AnchorHelper/
  git commit -m "feat: AnchorHelper entry point — network-event-driven mount loop"
  ```

---

## Task 10: SMAppService Helper Registration

**Files:**
- Create: `AnchorApp/HelperManager.swift`

- [ ] **Step 1: Implement HelperManager.swift**

  `SMAppService` registers `AnchorHelper` as a login item. The helper's bundle ID must match what Xcode assigns; verify in AnchorHelper's Info.plist.

  Create `AnchorApp/HelperManager.swift`:
  ```swift
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
          guard service.status != .enabled else {
              isRegistered = true
              return
          }
          do {
              try service.register()
              isRegistered = true
          } catch {
              // Helper registration failed — log but don't crash
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
  ```

- [ ] **Step 2: Build AnchorApp**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add AnchorApp/HelperManager.swift
  git commit -m "feat: HelperManager — SMAppService login item registration"
  ```

---

## Task 11: Menu Bar App Shell

**Files:**
- Modify: `AnchorApp/AnchorApp.swift`
- Create: `AnchorApp/AppDelegate.swift`
- Create: `AnchorApp/MenuBarController.swift`

- [ ] **Step 1: Implement AnchorApp.swift**

  Replace generated `AnchorApp.swift`:
  ```swift
  import SwiftUI

  @main
  struct AnchorApp: App {
      @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

      var body: some Scene {
          Settings {
              SettingsView()
          }
      }
  }
  ```

- [ ] **Step 2: Implement AppDelegate.swift**

  Create `AnchorApp/AppDelegate.swift`:
  ```swift
  import AppKit
  import AnchorCore

  final class AppDelegate: NSObject, NSApplicationDelegate {
      var menuBarController: MenuBarController?

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)  // no dock icon
          menuBarController = MenuBarController()
          HelperManager.shared.registerIfNeeded()
      }
  }
  ```

- [ ] **Step 3: Implement MenuBarController.swift**

  Create `AnchorApp/MenuBarController.swift`:
  ```swift
  import AppKit
  import AnchorCore

  final class MenuBarController {
      private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      private var shareStates: [UUID: MountState] = [:]
      private var config: AnchorConfig = AnchorConfig()
      private var notificationObserver: NSObjectProtocol?

      init() {
          updateIcon()
          buildMenu()
          loadConfig()
          observeStateChanges()
      }

      // MARK: - Icon

      private func updateIcon() {
          let allMounted = config.activeShares.allSatisfy { shareStates[$0.id] == .mounted }
          let anyMounted = config.activeShares.contains { shareStates[$0.id] == .mounted }
          let hasShares = !config.activeShares.isEmpty

          let imageName: String
          let tint: NSColor

          if !hasShares {
              imageName = "anchor"
              tint = .secondaryLabelColor
          } else if allMounted {
              imageName = "anchor"
              tint = .controlAccentColor
          } else if anyMounted {
              imageName = "anchor"
              tint = .systemYellow
          } else {
              imageName = "anchor"
              tint = .systemRed
          }

          let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Anchor")
          image?.isTemplate = false
          statusItem.button?.image = image
          statusItem.button?.contentTintColor = tint
      }

      // MARK: - Menu

      func buildMenu() {
          let menu = NSMenu()

          for share in config.activeShares {
              let state = shareStates[share.id] ?? .unmounted
              let dot = state == .mounted ? "● " : "○ "
              let item = NSMenuItem(title: "\(dot)\(share.displayName)", action: nil, keyEquivalent: "")
              menu.addItem(item)
          }

          if !config.activeShares.isEmpty { menu.addItem(.separator()) }

          let reconnect = NSMenuItem(title: "Reconnect All", action: #selector(reconnectAll), keyEquivalent: "r")
          reconnect.target = self
          menu.addItem(reconnect)

          let settings = NSMenuItem(title: "Open Anchor Settings…", action: #selector(openSettings), keyEquivalent: ",")
          settings.target = self
          menu.addItem(settings)

          menu.addItem(.separator())
          menu.addItem(NSMenuItem(title: "Anchor \(appVersion())", action: nil, keyEquivalent: ""))

          statusItem.menu = menu
      }

      // MARK: - Actions

      @objc private func reconnectAll() {
          MountNotifications.postConfigUpdated()
      }

      @objc private func openSettings() {
          NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
          NSApp.activate(ignoringOtherApps: true)
      }

      // MARK: - Helpers

      private func loadConfig() {
          config = (try? ConfigStore().load()) ?? AnchorConfig()
          buildMenu()
          updateIcon()
      }

      private func observeStateChanges() {
          notificationObserver = MountNotifications.observeStateChanged { [weak self] event in
              self?.shareStates[event.shareID] = event.state
              self?.buildMenu()
              self?.updateIcon()
          }
      }

      private func appVersion() -> String {
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
      }
  }
  ```

- [ ] **Step 4: Build and run AnchorApp**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  open /Users/mikezieseniss/dev/anchor/build/Debug/Anchor.app
  ```
  Expected: anchor icon appears in menu bar. Click it — menu shows "Reconnect All" and "Open Anchor Settings…".

- [ ] **Step 5: Commit**

  ```bash
  git add AnchorApp/
  git commit -m "feat: menu bar shell — status icon + dropdown with mount state"
  ```

---

## Task 12: Settings UI — Shares Tab

**Files:**
- Create: `AnchorApp/Views/SettingsView.swift`
- Create: `AnchorApp/Views/SharesTabView.swift`
- Create: `AnchorApp/Views/ShareEditSheet.swift`
- Create: `AnchorApp/Views/AboutTabView.swift`

- [ ] **Step 1: Implement SettingsView.swift**

  Create `AnchorApp/Views/SettingsView.swift`:
  ```swift
  import SwiftUI

  struct SettingsView: View {
      var body: some View {
          TabView {
              SharesTabView()
                  .tabItem { Label("Shares", systemImage: "externaldrive.connected.to.line.below") }
              ProfilesTabView()
                  .tabItem { Label("Profiles", systemImage: "person.2") }
              AboutTabView()
                  .tabItem { Label("About", systemImage: "info.circle") }
          }
          .frame(width: 520, height: 380)
      }
  }
  ```

- [ ] **Step 2: Implement SharesTabView.swift**

  Create `AnchorApp/Views/SharesTabView.swift`:
  ```swift
  import SwiftUI
  import AnchorCore

  struct SharesTabView: View {
      @State private var config: AnchorConfig = (try? ConfigStore().load()) ?? AnchorConfig()
      @State private var selection: UUID?
      @State private var showingEdit = false
      @State private var editingShare: Share?

      private let freeLimit = 3

      var body: some View {
          VStack(alignment: .leading, spacing: 0) {
              List(selection: $selection) {
                  ForEach(config.shares) { share in
                      HStack {
                          Image(systemName: "externaldrive")
                          VStack(alignment: .leading) {
                              Text(share.displayName).fontWeight(.medium)
                              Text("smb://\(share.host)/\(share.shareName)")
                                  .font(.caption).foregroundColor(.secondary)
                          }
                      }
                      .tag(share.id)
                  }
              }
              .listStyle(.bordered(alternatesRowBackgrounds: true))

              Divider()

              HStack {
                  Button(action: addShare) {
                      Image(systemName: "plus")
                  }
                  .disabled(config.shares.count >= freeLimit)
                  .help(config.shares.count >= freeLimit ? "Upgrade to Pro for unlimited shares" : "Add share")

                  Button(action: removeSelected) {
                      Image(systemName: "minus")
                  }
                  .disabled(selection == nil)

                  Spacer()

                  if config.shares.count >= freeLimit {
                      Text("3/3 shares — Upgrade to Pro for more")
                          .font(.caption).foregroundColor(.secondary)
                  }
              }
              .padding(8)
          }
          .sheet(isPresented: $showingEdit) {
              ShareEditSheet(share: editingShare ?? Share(displayName: "", host: "", shareName: "")) { saved in
                  applyEdit(saved)
              }
          }
          .onTapGesture(count: 2) { editSelected() }
      }

      private func addShare() {
          editingShare = nil
          showingEdit = true
      }

      private func editSelected() {
          guard let id = selection,
                let share = config.shares.first(where: { $0.id == id }) else { return }
          editingShare = share
          showingEdit = true
      }

      private func removeSelected() {
          guard let id = selection else { return }
          config.shares.removeAll { $0.id == id }
          saveConfig()
      }

      private func applyEdit(_ share: Share) {
          if let idx = config.shares.firstIndex(where: { $0.id == share.id }) {
              config.shares[idx] = share
          } else {
              config.shares.append(share)
          }
          saveConfig()
      }

      private func saveConfig() {
          try? ConfigStore().save(config)
          MountNotifications.postConfigUpdated()
      }
  }
  ```

- [ ] **Step 3: Implement ShareEditSheet.swift**

  Create `AnchorApp/Views/ShareEditSheet.swift`:
  ```swift
  import SwiftUI
  import AnchorCore

  struct ShareEditSheet: View {
      @State private var share: Share
      @Environment(\.dismiss) private var dismiss
      let onSave: (Share) -> Void

      init(share: Share, onSave: @escaping (Share) -> Void) {
          _share = State(initialValue: share)
          self.onSave = onSave
      }

      var body: some View {
          VStack(alignment: .leading, spacing: 16) {
              Text(share.displayName.isEmpty ? "Add Share" : "Edit Share")
                  .font(.headline).padding(.bottom, 4)

              Group {
                  field("Display Name", text: $share.displayName)
                  field("Host / IP", text: $share.host)
                      .help("e.g. 192.168.0.99 or nas.local")
                  field("Share Name", text: $share.shareName)
                      .help("e.g. data (case-sensitive)")
                  field("Username (optional)", text: Binding(
                      get: { share.username ?? "" },
                      set: { share.username = $0.isEmpty ? nil : $0 }
                  ))
              }

              // Pro: Fallback host (locked in free tier)
              HStack {
                  field("VPN Fallback Host 🔒", text: Binding(
                      get: { share.fallbackHost ?? "" },
                      set: { share.fallbackHost = $0.isEmpty ? nil : $0 }
                  ))
                  .disabled(true)
                  .help("Upgrade to Pro to configure mesh VPN fallback")
              }

              Spacer()

              HStack {
                  Button("Cancel") { dismiss() }
                  Spacer()
                  Button("Save") {
                      onSave(share)
                      dismiss()
                  }
                  .disabled(share.displayName.isEmpty || share.host.isEmpty || share.shareName.isEmpty)
                  .keyboardShortcut(.defaultAction)
              }
          }
          .padding(20)
          .frame(width: 400, height: 300)
      }

      private func field(_ label: String, text: Binding<String>) -> some View {
          VStack(alignment: .leading, spacing: 4) {
              Text(label).font(.caption).foregroundColor(.secondary)
              TextField("", text: text)
                  .textFieldStyle(.roundedBorder)
          }
      }
  }
  ```

- [ ] **Step 4: Implement AboutTabView.swift**

  Create `AnchorApp/Views/AboutTabView.swift`:
  ```swift
  import SwiftUI

  struct AboutTabView: View {
      var body: some View {
          VStack(spacing: 16) {
              Image(systemName: "anchor")
                  .font(.system(size: 48))
                  .foregroundColor(.accentColor)
              Text("Anchor").font(.title).fontWeight(.semibold)
              Text("Version \(appVersion())").foregroundColor(.secondary)

              Divider().padding(.horizontal, 40)

              Text("Free — up to 3 shares")
              Button("Upgrade to Pro — $9.99") { /* Task 17 */ }
                  .buttonStyle(.borderedProminent)
              Button("Restore Purchase") { /* Task 17 */ }
                  .foregroundColor(.secondary)

              Link("View on GitHub", destination: URL(string: "https://github.com/yourusername/anchor")!)
                  .font(.caption)
          }
          .padding(24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      private func appVersion() -> String {
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
      }
  }
  ```

- [ ] **Step 5: Build and smoke-test the settings window**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  open /Users/mikezieseniss/dev/anchor/build/Debug/Anchor.app
  ```
  Expected: Click menu bar icon → "Open Anchor Settings…" → settings window opens with Shares/Profiles/About tabs. Add button adds a share. Save persists to config.

- [ ] **Step 6: Commit**

  ```bash
  git add AnchorApp/Views/
  git commit -m "feat: settings UI — shares list, add/edit sheet, about tab"
  ```

---

## Task 13: ProKeychain

**Files:**
- Create: `AnchorCore/Sources/AnchorCore/Keychain/ProKeychain.swift`
- Test: `AnchorCore/Tests/AnchorCoreTests/ProKeychainTests.swift`

- [ ] **Step 1: Write failing tests**

  Create `AnchorCore/Tests/AnchorCoreTests/ProKeychainTests.swift`:
  ```swift
  import XCTest
  @testable import AnchorCore

  final class ProKeychainTests: XCTestCase {
      override func setUp() {
          super.setUp()
          ProKeychain.clearForTesting()
      }

      func testNotUnlockedByDefault() {
          XCTAssertFalse(ProKeychain.isProUnlocked())
      }

      func testUnlockAndRead() {
          ProKeychain.unlock(token: "test-entitlement-token")
          XCTAssertTrue(ProKeychain.isProUnlocked())
      }

      func testLockRemovesToken() {
          ProKeychain.unlock(token: "test-entitlement-token")
          ProKeychain.lock()
          XCTAssertFalse(ProKeychain.isProUnlocked())
      }
  }
  ```

- [ ] **Step 2: Run — expect compile failure**

  ```bash
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep "error:"
  ```

- [ ] **Step 3: Implement ProKeychain.swift**

  Create `AnchorCore/Sources/AnchorCore/Keychain/ProKeychain.swift`:
  ```swift
  import Foundation
  import Security

  public enum ProKeychain {
      private static let service = "com.yourname.anchor.pro"
      private static let account = "entitlement"

      public static func isProUnlocked() -> Bool {
          readToken() != nil
      }

      public static func unlock(token: String) {
          let data = Data(token.utf8)
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account,
              kSecValueData: data,
              kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
          ]
          SecItemDelete(query as CFDictionary)
          SecItemAdd(query as CFDictionary, nil)
      }

      public static func lock() {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account
          ]
          SecItemDelete(query as CFDictionary)
      }

      private static func readToken() -> String? {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account,
              kSecReturnData: true,
              kSecMatchLimit: kSecMatchLimitOne
          ]
          var result: AnyObject?
          let status = SecItemCopyMatching(query as CFDictionary, &result)
          guard status == errSecSuccess,
                let data = result as? Data else { return nil }
          return String(data: data, encoding: .utf8)
      }

      /// For tests only — clears the keychain entry.
      public static func clearForTesting() {
          lock()
      }
  }
  ```

- [ ] **Step 4: Run tests — expect pass**

  ```bash
  xcodebuild test -project Anchor.xcodeproj -scheme AnchorCore -destination 'platform=macOS' 2>&1 | grep -E "passed|FAILED"
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add AnchorCore/
  git commit -m "feat: ProKeychain — ACL-protected Pro entitlement token in Keychain"
  ```

**End of Phase 1.** At this point Anchor mounts and unmounts shares, persists config, shows status in the menu bar, and has a working settings UI. The helper registers at login and survives app quit.

---

# Phase 2 — Pro Features

---

## Task 14: StoreKit 2 IAP

**Files:**
- Create: `AnchorApp/Store/StoreManager.swift`

- [ ] **Step 1: Create the IAP product in App Store Connect**

  In App Store Connect → your app → In-App Purchases → Create → Non-Consumable.
  - Reference Name: `Anchor Pro`
  - Product ID: `com.yourname.anchor.pro`
  - Price: $9.99
  - Display Name: `Anchor Pro`
  - Description: `Unlimited shares, mesh VPN routing, multi-profile support`

- [ ] **Step 2: Implement StoreManager.swift**

  Create `AnchorApp/Store/StoreManager.swift`:
  ```swift
  import StoreKit
  import AnchorCore

  @MainActor
  final class StoreManager: ObservableObject {
      static let shared = StoreManager()
      static let proProductID = "com.yourname.anchor.pro"

      @Published private(set) var proProduct: Product?
      @Published private(set) var isPurchasing = false
      @Published private(set) var purchaseError: String?

      private init() {}

      func loadProducts() async {
          do {
              let products = try await Product.products(for: [Self.proProductID])
              proProduct = products.first
          } catch {
              print("StoreManager: loadProducts failed: \(error)")
          }
      }

      func purchase() async {
          guard let product = proProduct else { return }
          isPurchasing = true
          defer { isPurchasing = false }
          do {
              let result = try await product.purchase()
              switch result {
              case .success(let verification):
                  let transaction = try verification.payloadValue
                  await transaction.finish()
                  // Entitlement confirmed — write to Keychain
                  ProKeychain.unlock(token: transaction.id.description)
                  await EntitlementManager.shared.refresh()
              case .userCancelled:
                  break
              case .pending:
                  purchaseError = "Purchase pending approval"
              @unknown default:
                  break
              }
          } catch {
              purchaseError = error.localizedDescription
          }
      }

      func restorePurchases() async {
          try? await AppStore.sync()
          await EntitlementManager.shared.refresh()
      }
  }
  ```

- [ ] **Step 3: Build**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorApp/Store/StoreManager.swift
  git commit -m "feat: StoreManager — StoreKit 2 product load + purchase flow"
  ```

---

## Task 15: EntitlementManager (RevenueCat)

**Files:**
- Create: `AnchorApp/Store/EntitlementManager.swift`

- [ ] **Step 1: Add RevenueCat SDK**

  In Xcode → File → Add Package Dependencies → enter `https://github.com/RevenueCat/purchases-ios` → Up to Next Major → `4.x.x`. Add `RevenueCat` library to `Anchor` target only (not AnchorHelper — entitlement check runs in helper via ProKeychain).

- [ ] **Step 2: Get your RevenueCat API key**

  In [app.revenuecat.com](https://app.revenuecat.com) → New Project → macOS → copy the `Public SDK Key` (starts with `appl_`).

- [ ] **Step 3: Implement EntitlementManager.swift**

  Create `AnchorApp/Store/EntitlementManager.swift`:
  ```swift
  import Foundation
  import RevenueCat
  import AnchorCore

  @MainActor
  final class EntitlementManager: ObservableObject {
      static let shared = EntitlementManager()
      static let entitlementID = "pro"

      @Published private(set) var isPro: Bool = false

      private init() {
          // Replace with your actual RevenueCat API key
          Purchases.configure(withAPIKey: "appl_YOUR_REVENUECAT_API_KEY")
          isPro = ProKeychain.isProUnlocked()
      }

      func refresh() async {
          do {
              let customerInfo = try await Purchases.shared.customerInfo()
              let entitled = customerInfo.entitlements[Self.entitlementID]?.isActive == true
              if entitled {
                  // Keep Keychain token in sync
                  ProKeychain.unlock(token: customerInfo.originalAppUserId)
              } else {
                  ProKeychain.lock()
              }
              isPro = entitled
          } catch {
              // Network unavailable — fall back to cached Keychain value
              isPro = ProKeychain.isProUnlocked()
          }
      }
  }
  ```

- [ ] **Step 4: Call refresh at app launch**

  In `AppDelegate.swift`, add to `applicationDidFinishLaunching`:
  ```swift
  Task { await EntitlementManager.shared.refresh() }
  ```

- [ ] **Step 5: Wire purchase buttons in AboutTabView**

  In `AnchorApp/Views/AboutTabView.swift`, replace the placeholder buttons:
  ```swift
  @EnvironmentObject var entitlement: EntitlementManager
  @EnvironmentObject var store: StoreManager

  // Replace the two Button stubs with:
  if entitlement.isPro {
      Label("Anchor Pro — Active", systemImage: "checkmark.seal.fill")
          .foregroundColor(.green)
  } else {
      Button(store.isPurchasing ? "Purchasing…" : "Upgrade to Pro — \(store.proProduct?.displayPrice ?? "$9.99")") {
          Task { await store.purchase() }
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.isPurchasing)

      Button("Restore Purchase") {
          Task { await store.restorePurchases() }
      }
      .foregroundColor(.secondary)
  }
  ```

  Add `.environmentObject(EntitlementManager.shared).environmentObject(StoreManager.shared)` to the `SettingsView` in `AnchorApp.swift`.

- [ ] **Step 6: Build**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add AnchorApp/Store/EntitlementManager.swift AnchorApp/
  git commit -m "feat: EntitlementManager — RevenueCat server-side Pro validation + Keychain sync"
  ```

---

## Task 16: VPN Detector

**Files:**
- Create: `AnchorHelper/VPNDetector.swift`

- [ ] **Step 1: Implement VPNDetector.swift**

  Create `AnchorHelper/VPNDetector.swift`:
  ```swift
  import Foundation
  import Network

  enum VPNKind: String {
      case tailscale = "Tailscale"
      case netbird   = "NetBird"
      case zerotier  = "ZeroTier"
      case wireguard = "WireGuard (generic)"
      case none      = "None"
  }

  enum VPNDetector {
      /// Returns the detected mesh VPN, or .none.
      static func detect() -> VPNKind {
          var ifaddrs: UnsafeMutablePointer<ifaddrs>?
          guard getifaddrs(&ifaddrs) == 0 else { return .none }
          defer { freeifaddrs(ifaddrs) }

          var ptr = ifaddrs
          while let ifa = ptr {
              defer { ptr = ifa.pointee.ifa_next }
              guard let addr = ifa.pointee.ifa_addr,
                    addr.pointee.sa_family == UInt8(AF_INET) else { continue }
              let ip = ipString(from: addr)
              let name = String(cString: ifa.pointee.ifa_name)

              if isNetBirdIP(ip) { return .netbird }
              if isTailscaleIP(ip) { return .tailscale }
              if isZeroTierIP(ip) { return .zerotier }
              if isGenericWireGuard(name: name, ip: ip) { return .wireguard }
          }
          return .none
      }

      // MARK: - IP range checks

      private static func isNetBirdIP(_ ip: String) -> Bool {
          // 100.64.0.0/10
          guard let first = ip.split(separator: ".").first,
                let octet = UInt8(first) else { return false }
          if octet != 100 { return false }
          guard let second = ip.split(separator: ".").dropFirst().first,
                let second8 = UInt8(second) else { return false }
          return (64...127).contains(second8)
      }

      private static func isTailscaleIP(_ ip: String) -> Bool {
          // 100.64.0.0/10 is also used by Tailscale, distinguished by process
          let parts = ip.split(separator: ".")
          guard parts.count == 4,
                let a = UInt8(parts[0]), let b = UInt8(parts[1]) else { return false }
          if a == 100 && (64...127).contains(b) {
              // Check for tailscaled process to distinguish from NetBird
              return isProcessRunning("com.tailscale.ipn.macos") || isProcessRunning("tailscaled")
          }
          return false
      }

      private static func isZeroTierIP(_ ip: String) -> Bool {
          // 172.22.0.0/15 (172.22.x.x and 172.23.x.x)
          let parts = ip.split(separator: ".")
          guard parts.count == 4,
                let a = UInt8(parts[0]), let b = UInt8(parts[1]) else { return false }
          return a == 172 && (22...23).contains(b)
      }

      private static func isGenericWireGuard(name: String, ip: String) -> Bool {
          guard name.hasPrefix("utun") else { return false }
          // Exclude known RFC1918 ranges used by physical LANs
          let parts = ip.split(separator: ".")
          guard let a = UInt8(parts.first ?? "") else { return false }
          return a == 10 || (a == 172) || (a == 192)
          // This is a broad heuristic — real WG detection requires checking utun interfaces
          // that aren't already claimed by Tailscale/NetBird/ZeroTier
      }

      private static func isProcessRunning(_ name: String) -> Bool {
          let task = Process()
          task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
          task.arguments = ["-f", name]
          task.standardOutput = FileHandle.nullDevice
          try? task.run()
          task.waitUntilExit()
          return task.terminationStatus == 0
      }

      private static func ipString(from addr: UnsafePointer<sockaddr>) -> String {
          var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
          let sa = UnsafeRawPointer(addr).assumingMemoryBound(to: sockaddr_in.self)
          var sin_addr = sa.pointee.sin_addr
          inet_ntop(AF_INET, &sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
          return String(cString: buffer)
      }
  }
  ```

- [ ] **Step 2: Build AnchorHelper**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 3: Surface detected VPN in SharesTabView**

  In `AnchorApp/Views/SharesTabView.swift`, add at the top of the `body` (below the List):
  ```swift
  // Show detected mesh VPN so users know smart routing is active
  // VPNDetector runs in AnchorHelper; surface its last known kind via a UserDefaults key
  // written by HelperApp. Add to HelperApp.reloadAndMount():
  //   UserDefaults(suiteName: AppGroup.id)?.set(VPNDetector.detect().rawValue, forKey: "detectedVPN")
  // Then in SharesTabView:
  if let vpn = UserDefaults(suiteName: AppGroup.id)?.string(forKey: "detectedVPN"),
     vpn != VPNKind.none.rawValue {
      Label("Connected via \(vpn)", systemImage: "network")
          .font(.caption).foregroundColor(.secondary)
          .padding(.horizontal, 8).padding(.top, 4)
  }
  ```

  In `AnchorHelper/HelperApp.swift`, add to `reloadAndMount()`:
  ```swift
  let vpn = VPNDetector.detect()
  UserDefaults(suiteName: AppGroup.id)?.set(vpn.rawValue, forKey: "detectedVPN")
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorHelper/VPNDetector.swift AnchorApp/Views/SharesTabView.swift AnchorHelper/HelperApp.swift
  git commit -m "feat: VPNDetector — detect Tailscale/NetBird/ZeroTier/WireGuard; surface in UI"
  ```

---

## Task 17: Unlock Pro in MountEngine + UI

**Files:**
- Modify: `AnchorHelper/MountEngine.swift` (already routes via fallbackHost when isPro — verify it reads ProKeychain)
- Modify: `AnchorApp/Views/ShareEditSheet.swift` (unlock fallback host field when Pro)
- Create: `AnchorApp/Views/ProfilesTabView.swift`

- [ ] **Step 1: Verify MountEngine reads isPro from ProKeychain**

  In `AnchorHelper/HelperApp.swift`, confirm `isPro = ProKeychain.isProUnlocked()` is called in `reloadAndMount()`. It already is from Task 9. No change needed.

- [ ] **Step 2: Unlock fallback host field in ShareEditSheet when Pro**

  In `AnchorApp/Views/ShareEditSheet.swift`, replace the disabled fallback host block:
  ```swift
  @EnvironmentObject var entitlement: EntitlementManager

  // Replace the locked fallback field:
  VStack(alignment: .leading, spacing: 4) {
      HStack {
          Text("VPN Fallback Host").font(.caption).foregroundColor(.secondary)
          if !entitlement.isPro {
              Image(systemName: "lock.fill").font(.caption).foregroundColor(.secondary)
          }
      }
      TextField("e.g. 100.64.93.215 or myhost.tailnet.ts.net", text: Binding(
          get: { share.fallbackHost ?? "" },
          set: { share.fallbackHost = $0.isEmpty ? nil : $0 }
      ))
      .textFieldStyle(.roundedBorder)
      .disabled(!entitlement.isPro)
      .help(entitlement.isPro ? "Mesh VPN fallback IP or hostname" : "Upgrade to Pro to enable VPN fallback")
  }
  ```

- [ ] **Step 3: Unlock share limit in SharesTabView when Pro**

  In `AnchorApp/Views/SharesTabView.swift`, add:
  ```swift
  @EnvironmentObject var entitlement: EntitlementManager

  // Change the add button disabled condition:
  .disabled(!entitlement.isPro && config.shares.count >= freeLimit)
  ```

- [ ] **Step 4: Implement ProfilesTabView.swift**

  Create `AnchorApp/Views/ProfilesTabView.swift`:
  ```swift
  import SwiftUI
  import AnchorCore

  struct ProfilesTabView: View {
      @EnvironmentObject var entitlement: EntitlementManager
      @State private var config: AnchorConfig = (try? ConfigStore().load()) ?? AnchorConfig()
      @State private var newProfileName = ""

      private var allProfiles: [String] {
          Array(Set(config.shares.flatMap { $0.profiles })).sorted()
      }

      var body: some View {
          if !entitlement.isPro {
              VStack(spacing: 12) {
                  Image(systemName: "lock.fill").font(.largeTitle).foregroundColor(.secondary)
                  Text("Profiles are a Pro feature").fontWeight(.medium)
                  Text("Organise shares into Home, Office, and Travel profiles — auto-switch based on which shares are reachable.")
                      .multilineTextAlignment(.center).foregroundColor(.secondary).font(.callout)
                      .frame(maxWidth: 300)
                  // Use @EnvironmentObject consistently — same instance injected at root
                  Button("Upgrade to Pro — $9.99") { Task { await store.purchase() } }
                      .buttonStyle(.borderedProminent)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
              VStack(alignment: .leading, spacing: 12) {
                  Text("Active Profile")
                  Picker("Active Profile", selection: $config.activeProfile) {
                      Text("All shares").tag(String?.none)
                      ForEach(allProfiles, id: \.self) { p in
                          Text(p).tag(String?.some(p))
                      }
                  }
                  .labelsHidden()
                  .onChange(of: config.activeProfile) { _ in saveConfig() }

                  Divider()

                  Text("Create Profile").fontWeight(.medium)
                  HStack {
                      TextField("Profile name", text: $newProfileName)
                          .textFieldStyle(.roundedBorder)
                      Button("Add") {
                          guard !newProfileName.isEmpty else { return }
                          // Profile exists when a share is tagged with it
                          // For now, just note — user assigns profiles in share edit
                          newProfileName = ""
                      }
                  }
                  Text("Assign profiles to shares in the Shares tab.")
                      .font(.caption).foregroundColor(.secondary)
              }
              .padding()
          }
      }

      private func saveConfig() {
          try? ConfigStore().save(config)
          MountNotifications.postConfigUpdated()
      }
  }
  ```

- [ ] **Step 5: Build and test Pro unlock flow**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  ```
  Manual test: In About tab → "Upgrade to Pro" (use StoreKit sandbox) → confirm fallback host field unlocks in share edit, add button no longer shows 3-share limit.

- [ ] **Step 6: Commit**

  ```bash
  git add AnchorApp/
  git commit -m "feat: Pro unlock — remove share limit + enable VPN fallback field + profiles tab"
  ```

---

## Task 18: Config Export/Import + Share Health Notifications

**Files:**
- Modify: `AnchorApp/Views/AboutTabView.swift` (add export/import buttons)
- Modify: `AnchorHelper/HelperApp.swift` (post health notifications)

- [ ] **Step 1: Add export/import to AboutTabView**

  In `AnchorApp/Views/AboutTabView.swift`, add after the Pro status section:
  ```swift
  if entitlement.isPro {
      Divider().padding(.horizontal, 40)
      HStack(spacing: 12) {
          Button("Export Config") {
              guard let config = try? ConfigStore().load(),
                    let data = try? JSONEncoder().encode(config) else { return }
              let panel = NSSavePanel()
              panel.nameFieldStringValue = "anchor-config.json"
              panel.allowedContentTypes = [.json]
              if panel.runModal() == .OK, let url = panel.url {
                  try? data.write(to: url)
              }
          }
          Button("Import Config") {
              let panel = NSOpenPanel()
              panel.allowedContentTypes = [.json]
              if panel.runModal() == .OK, let url = panel.url,
                 let data = try? Data(contentsOf: url),
                 let config = try? JSONDecoder().decode(AnchorConfig.self, from: data) {
                  try? ConfigStore().save(config)
                  MountNotifications.postConfigUpdated()
              }
          }
      }
  }
  ```

- [ ] **Step 2: Add health notifications to HelperApp**

  In `AnchorHelper/HelperApp.swift`, track previous states and post a `UNUserNotification` when a share transitions to `.unreachable` or back to `.mounted`:

  Add at the top of `HelperApp`:
  ```swift
  import UserNotifications

  private var previousStates: [UUID: MountState] = [:]
  ```

  In `reloadAndMount()`, after `mountEngine.processShares`, read new states and compare:
  ```swift
  // Post health notifications for state transitions (Pro only)
  if isPro {
      let newConfig = try configStore.load()
      for share in newConfig.shares {
          // MountNotifications already fired — read from MountSession via notifications
          // Health notification logic lives in observeStateChanges() below
      }
  }
  ```

  Add a method called from `run()`:
  ```swift
  private func observeHealthNotifications() {
      MountNotifications.observeStateChanged { [weak self] event in
          guard let self, self.isPro else { return }
          let prev = self.previousStates[event.shareID]
          self.previousStates[event.shareID] = event.state

          if prev == .mounted && event.state == .unreachable {
              self.postNotification(title: "Share Disconnected",
                  body: "A share went offline. Anchor will reconnect automatically.")
          } else if prev == .unreachable && event.state == .mounted {
              self.postNotification(title: "Share Reconnected",
                  body: "Your share is back online.")
          }
      }
  }

  private func postNotification(title: String, body: String) {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }
  ```

  Call `observeHealthNotifications()` in `run()` before the network loop.

  Request notification permission in `AppDelegate.applicationDidFinishLaunching`:
  ```swift
  UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
  ```

- [ ] **Step 3: Build**

  ```bash
  xcodebuild build -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' 2>&1 | tail -3
  xcodebuild build -project Anchor.xcodeproj -scheme AnchorHelper -destination 'platform=macOS' 2>&1 | tail -3
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorApp/ AnchorHelper/
  git commit -m "feat: config export/import + share health notifications (Pro)"
  ```

**End of Phase 2.** Anchor Pro is fully functional: unlimited shares, VPN fallback routing, profiles, config export/import, and health notifications.

---

# Phase 3 — App Store + Polish

---

## Task 19: App Sandbox Entitlements Audit

**Files:**
- Modify: `AnchorApp/AnchorApp.entitlements`
- Modify: `AnchorHelper/AnchorHelper.entitlements`

- [ ] **Step 1: Set AnchorApp entitlements**

  In `AnchorApp/AnchorApp.entitlements`, ensure:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.app-sandbox</key>
      <true/>
      <key>com.apple.security.network.client</key>
      <true/>
      <key>com.apple.security.files.user-selected.read-write</key>
      <true/>
      <key>com.apple.application-identifier</key>
      <string>$(AppIdentifierPrefix)com.yourname.anchor</string>
      <key>com.apple.security.application-groups</key>
      <array>
          <string>group.com.yourname.anchor</string>
      </array>
  </dict>
  </plist>
  ```

- [ ] **Step 2: Set AnchorHelper entitlements**

  In `AnchorHelper/AnchorHelper.entitlements`:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.app-sandbox</key>
      <true/>
      <key>com.apple.security.network.client</key>
      <true/>
      <key>com.apple.application-identifier</key>
      <string>$(AppIdentifierPrefix)com.yourname.anchor.AnchorHelper</string>
      <key>com.apple.security.application-groups</key>
      <array>
          <string>group.com.yourname.anchor</string>
      </array>
  </dict>
  </plist>
  ```

  > **Note on NetFS and sandboxing:** `NetFSMountURLSync` requires `com.apple.security.network.client`. Test mounting from a sandboxed build — if it's blocked, file a temporary exception entitlement request with Apple or use `osascript` as a fallback (out-of-sandbox script execution).

- [ ] **Step 3: Archive and validate**

  In Xcode → Product → Archive → Distribute App → App Store Connect → Validate. Fix any entitlement warnings before submitting.

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorApp/ AnchorHelper/
  git commit -m "chore: App Sandbox entitlements for MAS submission"
  ```

---

## Task 20: App Icon + Version

- [ ] **Step 1: Create anchor icon assets**

  Design or commission a 1024×1024 anchor icon (⚓ stylised, macOS Big Sur style). Use [Icon Set Creator](https://apps.apple.com/app/icon-set-creator/id939343785) to generate all required sizes. Drop into `AnchorApp/Resources/Assets.xcassets/AppIcon.appiconset/`.

- [ ] **Step 2: Set version and build number**

  In Xcode → Anchor target → General:
  - Version: `1.0`
  - Build: `1`

- [ ] **Step 3: Add CFBundleShortVersionString to Info.plist if missing**

  Verify `AnchorApp/Info.plist` contains:
  ```xml
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add AnchorApp/Resources/
  git commit -m "chore: app icon and version 1.0"
  ```

---

## Task 21: GitHub Repo + README

- [ ] **Step 1: Create public GitHub repo**

  ```bash
  cd /Users/mikezieseniss/dev/anchor
  gh repo create anchor --public --description "macOS menu bar app — auto-mount SMB shares with mesh VPN awareness (Tailscale, NetBird, ZeroTier)" --source . --push
  ```

- [ ] **Step 2: Write README.md**

  ```bash
  cat > /Users/mikezieseniss/dev/anchor/README.md << 'EOF'
  # Anchor

  > Auto-mount your SMB/NFS network shares. Wherever you are.

  Anchor is a macOS menu bar app that keeps your network shares mounted — at home on your LAN, at the office over NetBird, or anywhere via Tailscale or ZeroTier. No manual reconnecting, no credential prompts.

  ## Features

  **Free**
  - Up to 3 shares auto-mounted on login and wake
  - SMB + NFS support
  - Instant network-change detection (zero polling)
  - Keychain credential storage

  **Pro ($9.99 one-time)**
  - Unlimited shares
  - Mesh VPN smart routing: try LAN first, fall back to Tailscale / NetBird / ZeroTier automatically
  - Multi-profile support (Home / Office / Travel)
  - Config export/import for fleet deployment
  - Share health notifications

  ## Requirements
  macOS 13.0 Ventura or later

  ## Installation
  [Mac App Store](#) | [Direct Download (free build)](#)

  ## License
  MIT
  EOF
  git add README.md
  git commit -m "docs: README"
  git push
  ```

---

## Task 22: App Store Submission

- [ ] **Step 1: Create App Store listing in App Store Connect**

  - App Name: `Anchor - Network Share Mounter`
  - Subtitle: `Auto-mount SMB shares everywhere`
  - Keywords: `smb, network drive, automount, nas, vpn, tailscale, netbird, zerotier, share`
  - Category: Utilities

- [ ] **Step 2: Take App Store screenshots**

  Required sizes: 1280×800 and 1440×900 (macOS).
  Capture: menu bar open, settings window (shares tab), about tab (Pro upgrade), share edit sheet.

- [ ] **Step 3: Archive + submit**

  Xcode → Product → Archive → Distribute App → App Store Connect → Upload.
  In App Store Connect → select build → submit for review.

- [ ] **Step 4: Set up RevenueCat entitlement**

  In [app.revenuecat.com](https://app.revenuecat.com):
  - Create entitlement: `pro`
  - Create product: `com.yourname.anchor.pro`
  - Attach product to entitlement

---

*Plan complete. Estimated total: 9–12 weeks (Phase 1: 4–5w, Phase 2: 3–4w, Phase 3: 2–3w).*
