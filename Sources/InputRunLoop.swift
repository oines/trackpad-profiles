import CoreFoundation
import Foundation

/// Runs contact delivery and the Quartz event tap on a thread separate from AppKit.
final class InputRunLoop: @unchecked Sendable {
    private final class Delivery {
        let perform: () -> Void

        init(_ perform: @escaping () -> Void) {
            self.perform = perform
        }
    }

    private final class Startup: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        let source: CFRunLoopSource
        var runLoop: CFRunLoop?

        init(source: CFRunLoopSource) {
            self.source = source
        }
    }

    private final class Reply<Value>: @unchecked Sendable {
        let ready = DispatchSemaphore(value: 0)
        var value: Value?
    }

    let runLoop: CFRunLoop
    private let source: CFRunLoopSource
    private let finished = DispatchGroup()
    private let lock = NSLock()
    private var cancelled = false

    init(deliver: @escaping () -> Void) {
        let delivery = Delivery(deliver)
        var context = CFRunLoopSourceContext()
        context.version = 0
        context.info = Unmanaged.passUnretained(delivery).toOpaque()
        context.retain = { info in
            guard let info else { return nil }
            _ = Unmanaged<Delivery>.fromOpaque(info).retain()
            return info
        }
        context.release = { info in
            if let info { Unmanaged<Delivery>.fromOpaque(info).release() }
        }
        context.perform = { info in
            guard let info else { return }
            let delivery = Unmanaged<Delivery>.fromOpaque(info).takeUnretainedValue()
            autoreleasepool(invoking: delivery.perform)
        }
        let source = withExtendedLifetime(delivery) {
            CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
        }
        self.source = source

        let startup = Startup(source: source)
        let finished = self.finished
        finished.enter()
        // Capturing the run loop state separately lets deinit stop the thread.
        let thread = Thread {
            let runLoop = CFRunLoopGetCurrent()!
            CFRunLoopAddSource(runLoop, startup.source, .defaultMode)
            startup.runLoop = runLoop
            startup.ready.signal()

            CFRunLoopRun()
            CFRunLoopSourceInvalidate(startup.source)
            finished.leave()
        }
        thread.name = "Trackpad Profiles Input"
        thread.qualityOfService = .userInteractive
        thread.start()
        startup.ready.wait()
        runLoop = startup.runLoop!
    }

    deinit {
        cancel()
    }

    func signal() {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }

        CFRunLoopSourceSignal(source)
        CFRunLoopWakeUp(runLoop)
    }

    /// The owner serializes configuration calls to sync and cancel.
    func sync<Result>(_ operation: @escaping () -> Result) -> Result {
        lock.lock()
        precondition(!cancelled, "Input run loop has stopped")
        if CFRunLoopGetCurrent() === runLoop {
            lock.unlock()
            return operation()
        }

        let reply = Reply<Result>()
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            reply.value = autoreleasepool(invoking: operation)
            reply.ready.signal()
        }
        CFRunLoopWakeUp(runLoop)
        lock.unlock()

        reply.ready.wait()
        return reply.value!
    }

    func cancel() {
        lock.lock()
        if !cancelled {
            cancelled = true
            let runLoop = self.runLoop
            // Enqueue the stop so cancellation also works before the first run.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
        lock.unlock()

        if CFRunLoopGetCurrent() !== runLoop {
            finished.wait()
        }
    }
}
