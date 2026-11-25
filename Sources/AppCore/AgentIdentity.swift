import Foundation
import Security

/// Tells whether a running agent is the one embedded in the opened
/// OpenLaunchPad.app. An agent outlives the app bundle it came from, so after a
/// manual update the old one keeps running until something replaces it.
///
/// Also compiled into the OpenLaunchPad launcher, which links no frameworks.
enum AgentIdentity {
    /// The code a process runs, from its code signature.
    enum RunningCode: Equatable {
        case hash(Data)
        /// The process runs, but its file was deleted or replaced on disk.
        case goneFromDisk
        case unknown
    }

    /// Only certain evidence counts, so that an unreadable signature can never
    /// make every click restart the agent instead of toggling it.
    static func isOutdated(running: RunningCode, embedded: Set<Data>) -> Bool {
        switch running {
        case .hash(let hash): !embedded.isEmpty && !embedded.contains(hash)
        case .goneFromDisk: true
        case .unknown: false
        }
    }

    static func runningCode(of process: pid_t) -> RunningCode {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: process] as CFDictionary
        let found = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard found == errSecSuccess, let code else { return classify(found, process) }
        // A signature is read from the process's path, where a newer file may
        // be by now. Only this compares that file with the code in memory.
        let unchanged = SecCodeCheckValidity(code, [], nil)
        if unchanged == errSecCSStaticCodeChanged { return classify(unchanged, process) }
        var staticCode: SecStaticCode?
        let located = SecCodeCopyStaticCode(code, [], &staticCode)
        guard located == errSecSuccess, let staticCode else { return classify(located, process) }
        let (status, hash) = codeHash(of: staticCode)
        guard status == errSecSuccess else { return classify(status, process) }
        return hash.map(RunningCode.hash) ?? .unknown
    }

    /// Every architecture has its own hash, and the process runs only one.
    static func embeddedHashes(ofAgentAt url: URL) -> Set<Data> {
        Set(["arm64", "arm64e", "x86_64"].compactMap { architecture in
            let attributes = [kSecCodeAttributeArchitecture: architecture] as CFDictionary
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPathAndAttributes(url as CFURL, [], attributes, &code) == errSecSuccess,
                let code
            else { return nil }
            return codeHash(of: code).hash
        })
    }

    private static func codeHash(of code: SecStaticCode) -> (status: OSStatus, hash: Data?) {
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(code, [], &information)
        let values = information as? [String: Any]
        return (status, values?[kSecCodeInfoUnique as String] as? Data)
    }

    private static func classify(_ status: OSStatus, _ process: pid_t) -> RunningCode {
        let missingFile = OSStatus(errSecErrnoBase) + ENOENT
        switch status {
        case missingFile, errSecCSStaticCodeNotFound, errSecCSStaticCodeChanged:
            // A process that just ended has no file either.
            return kill(process, 0) == 0 ? .goneFromDisk : .unknown
        default:
            return .unknown
        }
    }
}
