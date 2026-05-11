import CoreGraphics
import Foundation

final class EventTapRunLoopController: @unchecked Sendable {
    private let name: String
    private let startupTimeoutSeconds: TimeInterval
    private let makeTap: @Sendable () -> CFMachPort?
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var generation = 0

    init(
        name: String,
        startupTimeoutSeconds: TimeInterval = 1.0,
        makeTap: @escaping @Sendable () -> CFMachPort?
    ) {
        self.name = name
        self.startupTimeoutSeconds = startupTimeoutSeconds
        self.makeTap = makeTap
    }

    var isRunning: Bool {
        lock.withLock { eventTap != nil }
    }

    @discardableResult
    func start() -> Bool {
        stop()

        let semaphore = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var startResult = false
        let generation = lock.withLock { () -> Int in
            self.generation += 1
            return self.generation
        }

        let thread = Thread { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }
            autoreleasepool {
                let currentRunLoop = CFRunLoopGetCurrent()
                guard self.isCurrentGeneration(generation) else {
                    semaphore.signal()
                    return
                }
                guard let tap = self.makeTap(),
                      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                    resultLock.withLock {
                        startResult = false
                    }
                    semaphore.signal()
                    return
                }
                guard self.isCurrentGeneration(generation) else {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFMachPortInvalidate(tap)
                    resultLock.withLock {
                        startResult = false
                    }
                    semaphore.signal()
                    return
                }

                CFRunLoopAddSource(currentRunLoop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                let stored = self.lock.withLock { () -> Bool in
                    guard self.generation == generation else { return false }
                    self.eventTap = tap
                    self.runLoopSource = source
                    self.runLoop = currentRunLoop
                    return true
                }
                guard stored else {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
                    CFMachPortInvalidate(tap)
                    resultLock.withLock {
                        startResult = false
                    }
                    semaphore.signal()
                    return
                }
                resultLock.withLock {
                    startResult = true
                }
                semaphore.signal()

                CFRunLoopRun()

                CGEvent.tapEnable(tap: tap, enable: false)
                CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
                CFMachPortInvalidate(tap)
                self.lock.withLock {
                    if self.generation == generation, self.eventTap === tap {
                        self.eventTap = nil
                        self.runLoopSource = nil
                        self.runLoop = nil
                        self.thread = nil
                    }
                }
            }
        }
        thread.name = name
        lock.withLock {
            self.thread = thread
        }
        thread.start()
        guard semaphore.wait(timeout: .now() + startupTimeoutSeconds) == .success else {
            stop()
            return false
        }
        return resultLock.withLock { startResult }
    }

    func stop() {
        let snapshot = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?, CFRunLoop?, Thread?) in
            generation += 1
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

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        lock.withLock {
            self.generation == generation
        }
    }
}
