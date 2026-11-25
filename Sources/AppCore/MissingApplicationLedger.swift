import Foundation

/// Remembers how long saved applications have been absent from complete scans.
///
/// Updaters and reinstalls remove an application before its replacement appears.
/// Forgetting it at once would move it to the end of the last page and dissolve
/// a folder that has only one other application.
struct MissingApplicationLedger: Sendable {
    private let grace: TimeInterval
    private var firstMissing: [ApplicationIdentity: TimeInterval] = [:]

    init(grace: TimeInterval) { self.grace = grace }

    /// Records one complete scan. `now` must not go backwards.
    mutating func record(missing: Set<ApplicationIdentity>, at now: TimeInterval) {
        firstMissing = firstMissing.filter { missing.contains($0.key) }
        for identity in missing where firstMissing[identity] == nil { firstMissing[identity] = now }
    }

    /// Missing applications whose place in the layout is still reserved.
    func reserved(at now: TimeInterval) -> Set<ApplicationIdentity> {
        Set(firstMissing.filter { now - $0.value < grace }.keys)
    }

    /// Time until the next reservation ends, or nil when there is none.
    func timeUntilReview(at now: TimeInterval) -> TimeInterval? {
        firstMissing.values.map { grace - (now - $0) }.filter { $0 > 0 }.min()
    }
}
