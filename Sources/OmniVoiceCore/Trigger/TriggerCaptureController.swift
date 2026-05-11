import AppKit
import CoreGraphics
import Foundation

public enum TriggerCaptureEventKind: Equatable, Sendable {
    case keyDown
    case flagsChanged
    case other
}

public enum TriggerCaptureDecision: Equatable, Sendable {
    case capture(TriggerKey)
    case cancel
    case reject
    case ignore
}

public enum TriggerCapturePlanner {
    public static func decide(
        kind: TriggerCaptureEventKind,
        keyCode: Int?,
        isRepeat: Bool = false,
        includesFunctionModifier: Bool = false
    ) -> TriggerCaptureDecision {
        if kind == .keyDown, keyCode == 53 {
            return .cancel
        }
        switch kind {
        case .keyDown:
            guard !isRepeat else { return .ignore }
            return TriggerKey.captureCandidate(keyCode: keyCode).map(TriggerCaptureDecision.capture) ?? .reject
        case .flagsChanged:
            return TriggerKey.captureCandidate(
                keyCode: keyCode,
                includesFunctionModifier: includesFunctionModifier
            ).map(TriggerCaptureDecision.capture) ?? .reject
        case .other:
            return .ignore
        }
    }
}

public enum TriggerCaptureSignal: Equatable, Sendable {
    case captured(TriggerKey)
    case cancelled
    case rejected
    case failed
    case emergencyRescue
}

public struct TriggerCaptureBeginDecision: Equatable, Sendable {
    public let shouldPauseNormalTap: Bool

    public init(shouldPauseNormalTap: Bool) {
        self.shouldPauseNormalTap = shouldPauseNormalTap
    }
}

public struct TriggerCaptureFinishDecision: Equatable, Sendable {
    public let shouldRestoreNormalTap: Bool

    public init(shouldRestoreNormalTap: Bool) {
        self.shouldRestoreNormalTap = shouldRestoreNormalTap
    }
}

public enum TriggerCaptureSessionPlanner {
    public static func begin(listeningEnabled: Bool, normalTapRunning: Bool) -> TriggerCaptureBeginDecision {
        TriggerCaptureBeginDecision(shouldPauseNormalTap: listeningEnabled && normalTapRunning)
    }

    public static func finish(
        pausedNormalTap: Bool,
        restartListening: Bool,
        listeningEnabled: Bool
    ) -> TriggerCaptureFinishDecision {
        TriggerCaptureFinishDecision(
            shouldRestoreNormalTap: pausedNormalTap && restartListening && listeningEnabled
        )
    }
}

public final class TriggerCaptureController: @unchecked Sendable {
    public var onSignal: ((TriggerCaptureSignal) -> Void)?

    private let lock = NSLock()
    private lazy var eventTapRunLoop = EventTapRunLoopController(name: "OmniVoice Trigger Capture Tap") { [weak self] in
        guard let self else { return nil }
        return EventTapFactory.create(
            owner: self,
            events: [.keyDown, .flagsChanged, EventTapEventTypes.systemDefined],
            callback: triggerCaptureEventTapCallback,
        )
    }

    public init() {}

    deinit {
        stop()
    }

    public var isRunning: Bool {
        eventTapRunLoop.isRunning
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        guard eventTapRunLoop.start() else {
            post(.failed)
            return false
        }
        return true
    }

    public func stop() {
        eventTapRunLoop.stop()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            post(.failed)
            EventTapFactory.stopAsync(eventTapRunLoop)
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if FnEscapeRescueDetector.shouldRescue(type: type, keyCode: keyCode, flags: event.flags) {
            post(.emergencyRescue)
            EventTapFactory.stopAsync(eventTapRunLoop)
            return Unmanaged.passUnretained(event)
        }

        let kind: TriggerCaptureEventKind = switch type {
        case .keyDown:
            .keyDown
        case .flagsChanged:
            .flagsChanged
        default:
            .other
        }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let decision = TriggerCapturePlanner.decide(
            kind: kind,
            keyCode: keyCode,
            isRepeat: isRepeat,
            includesFunctionModifier: event.flags.contains(.maskSecondaryFn)
        )

        switch decision {
        case .capture(let trigger):
            post(.captured(trigger))
        case .cancel:
            post(.cancelled)
        case .reject:
            post(.rejected)
        case .ignore:
            break
        }
        return nil
    }

    private func post(_ signal: TriggerCaptureSignal) {
        DispatchQueue.main.async { [weak self] in
            self?.onSignal?(signal)
        }
    }
}

private let triggerCaptureEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<TriggerCaptureController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
