import CoreGraphics
import Foundation

final class EventTapRunLoopController: @unchecked Sendable {
    private let name: String
    private let makeTap: @Sendable () -> CFMachPort?
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(name: String, makeTap: @escaping @Sendable () -> CFMachPort?) {
        self.name = name
        self.makeTap = makeTap
    }

    var isRunning: Bool {
        lock.withRunLoopLock { eventTap != nil }
    }

    @discardableResult
    func start() -> Bool {
        stop()

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var startResult = false

        let thread = Thread { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            autoreleasepool {
                let currentRunLoop = CFRunLoopGetCurrent()
                guard let tap = self.makeTap(),
                      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                    resultLock.withRunLoopLock {
                        startResult = false
                    }
                    semaphore.signal()
                    return
                }

                CFRunLoopAddSource(currentRunLoop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                self.lock.withRunLoopLock {
                    self.eventTap = tap
                    self.runLoopSource = source
                    self.runLoop = currentRunLoop
                }
                resultLock.withRunLoopLock {
                    startResult = true
                }
                semaphore.signal()

                CFRunLoopRun()

                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
                CFMachPortInvalidate(tap)
                self.lock.withRunLoopLock {
                    if self.eventTap === tap {
                        self.eventTap = nil
                        self.runLoopSource = nil
                        self.runLoop = nil
                        self.thread = nil
                    }
                }
            }
        }
        thread.name = name
        lock.withRunLoopLock {
            self.thread = thread
        }
        thread.start()
        semaphore.wait()
        return resultLock.withRunLoopLock { startResult }
    }

    func stop() {
        let snapshot = lock.withRunLoopLock { () -> (CFMachPort?, CFRunLoopSource?, CFRunLoop?, Thread?) in
            let snapshot = (eventTap, runLoopSource, runLoop, thread)
            eventTap = nil
            runLoopSource = nil
            runLoop = nil
            thread = nil
            return snapshot
        }
        if let tap = snapshot.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.2 {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        snapshot.3?.cancel()
    }
}

private extension NSLock {
    func withRunLoopLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
