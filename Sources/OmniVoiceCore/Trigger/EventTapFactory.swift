import CoreGraphics
import Foundation

enum EventTapFactory {
    static func create(
        owner: AnyObject,
        events: [CGEventType],
        callback: CGEventTapCallBack
    ) -> CFMachPort? {
        let mask = events.reduce(CGEventMask(0)) { partial, type in
            partial | CGEventMask(1 << type.rawValue)
        }
        let userInfo = Unmanaged.passUnretained(owner).toOpaque()
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        )
    }

    static func stopAsync(_ runLoop: EventTapRunLoopController) {
        DispatchQueue.global(qos: .userInitiated).async {
            runLoop.stop()
        }
    }
}
