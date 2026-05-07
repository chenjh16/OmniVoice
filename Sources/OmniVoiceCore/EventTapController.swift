import AppKit
import CoreGraphics
import Foundation

public enum EventTapSignal: Equatable, Sendable {
    case triggerDown
    case triggerUp
    case cancel(EventTapCancellationReason)
    case tapDisabled
    case tapReenabled
    case tapFailed
    case triggerAckTimeout
    case triggerWatchdogReset
    case emergencyRescue
}

public enum EventTapCancellationReason: Equatable, Sendable {
    case escapeKey
    case triggerCombination
}

public enum EventTapTriggerAction: Equatable, Sendable {
    case down
    case up
}

public struct EventTapTriggerDecision: Equatable, Sendable {
    public let action: EventTapTriggerAction?
    public let shouldSuppress: Bool

    public init(action: EventTapTriggerAction?, shouldSuppress: Bool) {
        self.action = action
        self.shouldSuppress = shouldSuppress
    }

    public static let passThrough = EventTapTriggerDecision(action: nil, shouldSuppress: false)
}

public enum EventTapTriggerClassifier {
    public static func decision(
        for trigger: TriggerKey,
        type: CGEventType,
        flags: CGEventFlags,
        keyCode: Int,
        isRepeat: Bool,
        triggerPressed: Bool
    ) -> EventTapTriggerDecision {
        switch trigger.kind {
        case .fnGlobe:
            guard type == .flagsChanged else { return .passThrough }
            let fnDown = flags.contains(.maskSecondaryFn)
            guard fnDown != triggerPressed else { return .passThrough }
            return EventTapTriggerDecision(action: fnDown ? .down : .up, shouldSuppress: true)
        case .functionKey:
            guard trigger.keyCode == keyCode else { return .passThrough }
            if type == .keyDown {
                return EventTapTriggerDecision(action: isRepeat ? nil : .down, shouldSuppress: true)
            }
            if type == .keyUp {
                return EventTapTriggerDecision(action: .up, shouldSuppress: true)
            }
            return .passThrough
        case .modifier:
            guard type == .flagsChanged, trigger.keyCode == keyCode else { return .passThrough }
            let pressed = flags.rawValue & trigger.modifierFlagsRawValue != 0
            return EventTapTriggerDecision(action: pressed ? .down : .up, shouldSuppress: true)
        case .capsLock:
            guard type == .flagsChanged, trigger.keyCode == keyCode else { return .passThrough }
            return EventTapTriggerDecision(action: triggerPressed ? .up : .down, shouldSuppress: true)
        }
    }
}

public enum EventTapEventTypes {
    // NSSystemDefined is delivered through CGEvent with raw value 14 for media/brightness keys.
    public static let systemDefined = CGEventType(rawValue: 14)!
}

public enum EventTapFnCombinationCancellation {
    public static func cancelReason(
        trigger: TriggerKey,
        type: CGEventType,
        triggerPressed: Bool
    ) -> EventTapCancellationReason? {
        guard trigger.kind == .fnGlobe, triggerPressed else { return nil }
        return type == .keyDown || type == EventTapEventTypes.systemDefined ? .triggerCombination : nil
    }

    public static func shouldCancel(
        trigger: TriggerKey,
        type: CGEventType,
        triggerPressed: Bool
    ) -> Bool {
        cancelReason(trigger: trigger, type: type, triggerPressed: triggerPressed) != nil
    }
}

public enum FnEscapeRescueDetector {
    public static let escapeKeyCode = 53

    public static func shouldRescue(
        type: CGEventType,
        keyCode: Int,
        flags: CGEventFlags
    ) -> Bool {
        type == .keyDown &&
        keyCode == escapeKeyCode &&
        flags.contains(.maskSecondaryFn)
    }
}

public enum EventTapEscapeCancellation {
    public static func cancelReason(
        type: CGEventType,
        keyCode: Int,
        cancellationActive: Bool
    ) -> EventTapCancellationReason? {
        guard cancellationActive,
              type == .keyDown,
              keyCode == FnEscapeRescueDetector.escapeKeyCode else {
            return nil
        }
        return .escapeKey
    }
}

public final class EventTapController: @unchecked Sendable {
    public var onSignal: (@Sendable (EventTapSignal) -> Void)?

    private let lock = NSLock()
    private lazy var eventTapRunLoop = EventTapRunLoopController(name: "OmniVoice Event Tap") { [weak self] in
        guard let self else { return nil }
        let mask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << EventTapEventTypes.systemDefined.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        )
    }
    private var triggerKey: TriggerKey
    private var triggerPressed = false
    private var triggerPressedAt: Date?
    private var cancellationActive = false
    private var triggerSuppressionEnabled = true
    private var passThroughOnly = false
    private var triggerWatchdogTimeoutSeconds: TimeInterval = 310
    private var releaseRecoveryCandidateSince: Date?
    private var watchdogTimer: Timer?
    private var nextSignalID = 1
    private var pendingSignalID: Int?

    public init(triggerKey: TriggerKey = .defaultTrigger) {
        self.triggerKey = triggerKey
    }

    deinit {
        stop()
    }

    public func update(triggerKey: TriggerKey) {
        lock.withLock {
            self.triggerKey = triggerKey
            self.triggerPressed = false
            self.triggerPressedAt = nil
            self.releaseRecoveryCandidateSince = nil
        }
    }

    public func updateWatchdogTimeout(seconds: TimeInterval) {
        lock.withLock {
            triggerWatchdogTimeoutSeconds = max(5, seconds)
        }
    }

    public var isRunning: Bool {
        eventTapRunLoop.isRunning
    }

    public func setCancellationActive(_ active: Bool) {
        lock.withLock {
            cancellationActive = active
        }
    }

    public func setTriggerSuppressionEnabled(_ enabled: Bool) {
        lock.withLock {
            triggerSuppressionEnabled = enabled
            if !enabled {
                triggerPressed = false
                triggerPressedAt = nil
                releaseRecoveryCandidateSince = nil
            }
        }
    }

    public func acknowledgeMainSignal() {
        lock.withLock {
            pendingSignalID = nil
        }
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        lock.withLock {
            passThroughOnly = false
            triggerPressed = false
            triggerPressedAt = nil
            releaseRecoveryCandidateSince = nil
            pendingSignalID = nil
        }
        guard eventTapRunLoop.start() else {
            post(.tapFailed)
            return false
        }
        startWatchdogTimer()
        return true
    }

    public func stop() {
        let timer = lock.withLock { () -> Timer? in
            let timer = watchdogTimer
            watchdogTimer = nil
            triggerPressed = false
            triggerPressedAt = nil
            releaseRecoveryCandidateSince = nil
            pendingSignalID = nil
            passThroughOnly = true
            return timer
        }
        eventTapRunLoop.stop()
        timer?.invalidate()
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let wasPressed = lock.withLock { () -> Bool in
                let pressed = triggerPressed
                triggerPressed = false
                triggerPressedAt = nil
                releaseRecoveryCandidateSince = nil
                pendingSignalID = nil
                self.passThroughOnly = true
                return pressed
            }
            if wasPressed {
                post(.triggerUp)
            }
            post(.tapDisabled)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.eventTapRunLoop.stop()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if FnEscapeRescueDetector.shouldRescue(type: type, keyCode: keyCode, flags: event.flags) {
            clearPressedTriggerState()
            lock.withLock {
                self.passThroughOnly = true
                pendingSignalID = nil
            }
            post(.emergencyRescue)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.eventTapRunLoop.stop()
            }
            return Unmanaged.passUnretained(event)
        }

        if let cancelReason = EventTapEscapeCancellation.cancelReason(
            type: type,
            keyCode: keyCode,
            cancellationActive: lock.withLock({ cancellationActive })
        ) {
            post(.cancel(cancelReason))
            return nil
        }

        let (currentTrigger, currentlyPressed, suppressionEnabled, passThroughOnly) = lock.withLock {
            (triggerKey, triggerPressed, triggerSuppressionEnabled, self.passThroughOnly)
        }
        guard !passThroughOnly, suppressionEnabled else {
            return Unmanaged.passUnretained(event)
        }
        if let cancelReason = EventTapFnCombinationCancellation.cancelReason(
            trigger: currentTrigger,
            type: type,
            triggerPressed: currentlyPressed
        ) {
            clearPressedTriggerState()
            post(.cancel(cancelReason))
            return Unmanaged.passUnretained(event)
        }

        let decision = EventTapTriggerClassifier.decision(
            for: currentTrigger,
            type: type,
            flags: event.flags,
            keyCode: keyCode,
            isRepeat: isRepeat,
            triggerPressed: currentlyPressed
        )
        guard decision.action != nil || decision.shouldSuppress else {
            return Unmanaged.passUnretained(event)
        }

        if let action = decision.action {
            switch action {
            case .down:
                postIfStateChanges(pressed: true, signal: .triggerDown)
            case .up:
                postIfStateChanges(pressed: false, signal: .triggerUp)
            }
        }

        if decision.shouldSuppress {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func postIfStateChanges(pressed: Bool, signal: EventTapSignal) {
        var shouldPost = false
        var signalID: Int?
        lock.withLock {
            if triggerPressed != pressed {
                triggerPressed = pressed
                triggerPressedAt = pressed ? Date() : nil
                releaseRecoveryCandidateSince = nil
                let id = nextSignalID
                nextSignalID += 1
                pendingSignalID = id
                signalID = id
                shouldPost = true
            }
        }
        guard shouldPost else { return }
        post(signal)
        if let signalID {
            scheduleMainSignalAckWatchdog(signalID: signalID)
        }
    }

    private func clearPressedTriggerState() {
        lock.withLock {
            triggerPressed = false
            triggerPressedAt = nil
            releaseRecoveryCandidateSince = nil
            pendingSignalID = nil
        }
    }

    private func post(_ signal: EventTapSignal) {
        DispatchQueue.main.async { [weak self] in
            self?.onSignal?(signal)
        }
    }

    private func scheduleMainSignalAckWatchdog(signalID: Int) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.stopIfMainSignalUnacknowledged(signalID: signalID)
        }
    }

    private func stopIfMainSignalUnacknowledged(signalID: Int) {
        let shouldStop = lock.withLock { () -> Bool in
            guard pendingSignalID == signalID else { return false }
            pendingSignalID = nil
            passThroughOnly = true
            triggerPressed = false
            triggerPressedAt = nil
            releaseRecoveryCandidateSince = nil
            return true
        }
        guard shouldStop else { return }
        eventTapRunLoop.stop()
        post(.triggerAckTimeout)
    }

    private func startWatchdogTimer() {
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.checkTriggerPollingRecovery()
            self?.checkTriggerWatchdog()
        }
        RunLoop.main.add(timer, forMode: .common)
        let oldTimer = lock.withLock { () -> Timer? in
            let old = watchdogTimer
            watchdogTimer = timer
            return old
        }
        oldTimer?.invalidate()
    }

    private func checkTriggerWatchdog() {
        let shouldReset = lock.withLock { () -> Bool in
            guard EventTapWatchdogDecision.shouldReset(
                pressedAt: triggerPressedAt,
                now: Date(),
                timeoutSeconds: triggerWatchdogTimeoutSeconds
            ) else {
                return false
            }
            triggerPressed = false
            triggerPressedAt = nil
            releaseRecoveryCandidateSince = nil
            return true
        }
        guard shouldReset else { return }
        post(.triggerWatchdogReset)
        post(.triggerUp)
    }

    private func checkTriggerPollingRecovery() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let now = Date()
        let signal = lock.withLock { () -> EventTapSignal? in
            guard triggerPressed,
                  EventTapPollingRecoveryDecision.isReleaseCandidate(trigger: triggerKey, flags: flags) else {
                releaseRecoveryCandidateSince = nil
                return nil
            }
            let candidateSince = releaseRecoveryCandidateSince ?? now
            releaseRecoveryCandidateSince = candidateSince
            if EventTapPollingRecoveryDecision.shouldPostSyntheticUp(
                candidateSince: candidateSince,
                now: now,
                graceSeconds: 0.75
            ) {
                triggerPressed = false
                triggerPressedAt = nil
                releaseRecoveryCandidateSince = nil
                return .triggerUp
            }
            return nil
        }
        guard let signal else { return }
        post(signal)
    }
}

public enum EventTapPollingRecoveryDecision {
    public static func isReleaseCandidate(trigger: TriggerKey, flags: CGEventFlags) -> Bool {
        switch trigger.kind {
        case .fnGlobe:
            return false
        case .modifier:
            return flags.rawValue & trigger.modifierFlagsRawValue == 0
        case .functionKey, .capsLock:
            return false
        }
    }

    public static func shouldPostSyntheticUp(
        candidateSince: Date,
        now: Date,
        graceSeconds: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(candidateSince) >= graceSeconds
    }
}

public enum EventTapWatchdogDecision {
    public static func shouldReset(
        pressedAt: Date?,
        now: Date,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        guard let pressedAt else { return false }
        return now.timeIntervalSince(pressedAt) >= timeoutSeconds
    }
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(proxy: proxy, type: type, event: event)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
