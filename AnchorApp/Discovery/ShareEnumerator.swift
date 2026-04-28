import Foundation

/// Enumerates SMB shares and resolves server names via `smbutil`.
/// Works on unsigned dev builds; fails gracefully in a signed sandbox (returns []/nil).
enum ShareEnumerator {

    /// Returns the NetBIOS/SMB server name for an IP (e.g. "MIKEAI").
    /// Used to show a friendly name for servers not advertising via Bonjour.
    static func serverName(for ip: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
                proc.arguments = ["status", ip]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                guard (try? proc.run()) != nil else { cont.resume(returning: nil); return }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    if proc.isRunning { proc.terminate() }
                }
                proc.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                // Parse "Server: MIKEAI"
                let name = output.components(separatedBy: "\n")
                    .first { $0.hasPrefix("Server:") }
                    .flatMap { line -> String? in
                        let parts = line.components(separatedBy: ": ")
                        guard parts.count >= 2 else { return nil }
                        return parts[1].trimmingCharacters(in: .whitespaces)
                    }
                cont.resume(returning: name?.isEmpty == false ? name : nil)
            }
        }
    }

    static func enumerate(host: String, username: String? = nil) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: run(host: host, username: username))
            }
        }
    }

    // MARK: - Private

    private static func run(host: String, username: String? = nil) -> [String] {
        let user = username.flatMap { $0.isEmpty ? nil : $0 }
        let urlArg: String
        if let u = user {
            let enc = u.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? u
            urlArg = "//\(enc)@\(host)"
        } else {
            urlArg = "//\(host)"
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        proc.arguments = ["view", urlArg]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if proc.isRunning { proc.terminate() }
            }
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return parse(String(data: data, encoding: .utf8) ?? "")
        } catch {
            return []  // sandboxed — no subprocess access
        }
    }

    // Parse smbutil view output: "ShareName    Disk    Comments"
    // Name may contain spaces; type is always the last all-caps word before whitespace.
    private static func parse(_ output: String) -> [String] {
        let hidden = Set(["ADMIN$", "C$", "D$", "E$", "F$", "IPC$", "PRINT$", "print$"])
        // Regex: capture name (possibly with spaces) then 2+ spaces then "Disk"
        guard let regex = try? NSRegularExpression(pattern: #"^(.+?)\s{2,}(Disk)"#, options: .anchorsMatchLines) else {
            return []
        }
        let range = NSRange(output.startIndex..., in: output)
        return regex.matches(in: output, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: output) else { return nil }
            let name = String(output[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !hidden.contains(name), !name.hasSuffix("$") else { return nil }
            return name
        }
    }
}
