import AppKit
import CoreGraphics
import Foundation

public final class EventTapController: @unchecked Sendable {
    public var onSignal: (@Sendable (EventTapSignal) -> Void)?

    private let lock = NSLock()
    private lazy var eventTapRunLoop = EventTapRunLoopController(name: "OmniVoice Event Tap") { [weak self] in
        guard let self else { return nil }
        return EventTapFactory.create(
            owner: self,
            events: [.keyDown, .keyUp, .flagsChanged, EventTapEventTypes.systemDefined],
            callback: eventTapCallback,
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

    public func clearCurrentTriggerStateForContinuousRecording() {
        clearPressedTriggerState()
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
            EventTapFactory.stopAsync(eventTapRunLoop)
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
            EventTapFactory.stopAsync(eventTapRunLoop)
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

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(proxy: proxy, type: type, event: event)
}
