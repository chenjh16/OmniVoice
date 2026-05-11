import Dispatch
import Foundation

@MainActor
final class MainActorTimerSlot {
    private(set) var timer: Timer?

    func replace(_ timer: Timer?) {
        self.timer?.invalidate()
        self.timer = timer
    }

    @discardableResult
    func schedule(
        interval: TimeInterval,
        repeats: Bool,
        _ handler: @MainActor @escaping () -> Void
    ) -> Timer {
        cancel()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            Task { @MainActor in
                handler()
            }
        }
        self.timer = timer
        return timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class MainActorWorkItemSlot {
    private(set) var workItem: DispatchWorkItem?

    func replace(_ workItem: DispatchWorkItem?) {
        self.workItem?.cancel()
        self.workItem = workItem
    }

    func schedule(after delay: TimeInterval, _ handler: @MainActor @escaping () -> Void) {
        cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                handler()
            }
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
