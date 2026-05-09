import Foundation

struct ConfigHotReloadController: Equatable {
    enum FileChangeAction: Equatable {
        case ignore
        case markPending
        case applyNow
    }

    private(set) var pendingReload = false
    private(set) var lastInvalidFingerprint: String?
    private(set) var lastMessage: String?
    private var ignoreFileChangesUntil: Date?

    mutating func markInternalWrite(now: Date = Date(), ignoreDuration: TimeInterval = 2) {
        ignoreFileChangesUntil = now.addingTimeInterval(ignoreDuration)
    }

    mutating func handleFileChanged(now: Date = Date(), isIdle: Bool) -> FileChangeAction {
        if let ignoreUntil = ignoreFileChangesUntil {
            if now < ignoreUntil {
                return .ignore
            }
            ignoreFileChangesUntil = nil
        }

        guard isIdle else {
            pendingReload = true
            return .markPending
        }
        return .applyNow
    }

    mutating func consumePendingIfIdle(isIdle: Bool) -> Bool {
        guard pendingReload, isIdle else { return false }
        pendingReload = false
        return true
    }

    mutating func markValidApplied() {
        lastInvalidFingerprint = nil
        lastMessage = nil
    }

    mutating func clearMessage() {
        lastMessage = nil
    }

    mutating func shouldReportInvalidConfig(fingerprint: String) -> Bool {
        guard fingerprint != lastInvalidFingerprint else { return false }
        lastInvalidFingerprint = fingerprint
        return true
    }

    mutating func setInvalidMessage(_ message: String) {
        lastMessage = message
    }

    static func fingerprint(data: Data?) -> String {
        guard let data else { return "missing" }
        return "\(data.count):\(data.hashValue)"
    }
}
