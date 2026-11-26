import AppKit
import CoreGraphics

private struct ContactSample {
    let x: Double
    let y: Double
    let touching: Bool
    let timestamp = DispatchTime.now().uptimeNanoseconds
}

private struct MappingSession: Equatable {
    let profile: AppProfile
    let pid: pid_t
    let bounds: CGRect
}

private let trackpadCallback: TPContactCallback = { x, y, touching, context in
    guard let context else { return }
    let pipeline = Unmanaged<PointerPipeline>.fromOpaque(context).takeUnretainedValue()
    pipeline.submit(ContactSample(x: x, y: y, touching: touching))
}

@MainActor
final class TrackpadEngine {
    enum State {
        case running
        case eventTapUnavailable
        case frameworkUnavailable
        case noTrackpad
    }

    private var pipeline: PointerPipeline?
    private var activeSession: MappingSession?

    func activate(_ profile: AppProfile, pid: pid_t, bounds: CGRect) -> State {
        let session = MappingSession(profile: profile, pid: pid, bounds: bounds)
        guard session != activeSession else { return .running }

        let pipeline = self.pipeline ?? PointerPipeline(workspace: .shared)
        self.pipeline = pipeline

        if activeSession?.pid == pid {
            pipeline.update(session)
            activeSession = session
            return .running
        }

        stop()
        guard pipeline.start(session) else { return .eventTapUnavailable }
        let deviceCount = TPStart(trackpadCallback, Unmanaged.passUnretained(pipeline).toOpaque())
        guard deviceCount > 0 else {
            pipeline.stop()
            return deviceCount == 0 ? .noTrackpad : .frameworkUnavailable
        }

        activeSession = session
        return .running
    }

    func stop() {
        guard activeSession != nil else { return }

        pipeline?.stop()
        TPStop()
        activeSession = nil
    }

    func shutdown() {
        stop()
        pipeline?.shutdown()
        pipeline = nil
    }
}

// Only the sample slot is shared with the private framework callback.
// Cursor output and the Quartz event tap use the same run loop.
private final class PointerPipeline: @unchecked Sendable {
    private static let outputTag: Int64 = 0x4D_54_50_41_50_50
    private static let contactTimeout: UInt64 = 55_000_000

    private let workspace: NSWorkspace
    private let mapper = NSRunningApplication.current
    private let sampleLock = NSLock()
    private var pending: ContactSample?
    private var acceptsSamples = false

    private lazy var input = InputRunLoop { [weak self] in self?.deliver() }
    private var session: MappingSession?
    private var eventSource: CGEventSource?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var contactTimestamp: UInt64?
    private var lastPosition: CGPoint?

    init(workspace: NSWorkspace) {
        self.workspace = workspace
    }

    func start(_ session: MappingSession) -> Bool {
        // Initialize the worker before TPStart can deliver any samples.
        input.sync { [self] in
            guard installEventTap() else { return false }
            eventSource = CGEventSource(stateID: .combinedSessionState)
            self.session = session
            resetSamples(accepting: true)
            return true
        }
    }

    func update(_ session: MappingSession) {
        input.sync { [self] in
            self.session = session
            resetSamples(accepting: true)
        }
    }

    func stop() {
        input.sync { [self] in
            session = nil
            resetSamples(accepting: false)
            if let eventTapSource {
                CFRunLoopRemoveSource(input.runLoop, eventTapSource, .commonModes)
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
                CFMachPortInvalidate(eventTap)
            }
            eventTap = nil
            eventTapSource = nil
            eventSource = nil
        }
    }

    func shutdown() {
        input.cancel()
    }

    func submit(_ sample: ContactSample) {
        sampleLock.lock()
        guard acceptsSamples else {
            sampleLock.unlock()
            return
        }

        let needsWake = pending == nil
        pending = sample
        sampleLock.unlock()
        if needsWake { input.signal() }
    }

    private func resetSamples(accepting: Bool) {
        sampleLock.lock()
        acceptsSamples = accepting
        pending = nil
        sampleLock.unlock()
        contactTimestamp = nil
        lastPosition = nil
    }

    private func deliver() {
        sampleLock.lock()
        let sample = pending
        pending = nil
        sampleLock.unlock()

        guard let sample else { return }
        guard sample.touching, let session,
              isFresh(sample.timestamp), matchesForeground(session),
              let location = session.profile.map(x: sample.x, y: sample.y, to: session.bounds)
        else {
            contactTimestamp = nil
            lastPosition = nil
            return
        }

        contactTimestamp = sample.timestamp
        guard location != lastPosition else { return }

        let (type, button): (CGEventType, CGMouseButton)
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            (type, button) = (.leftMouseDragged, .left)
        } else if CGEventSource.buttonState(.combinedSessionState, button: .right) {
            (type, button) = (.rightMouseDragged, .right)
        } else if CGEventSource.buttonState(.combinedSessionState, button: .center) {
            (type, button) = (.otherMouseDragged, .center)
        } else {
            (type, button) = (.mouseMoved, .left)
        }

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ) else {
            contactTimestamp = nil
            return
        }

        event.setIntegerValueField(.eventSourceUserData, value: Self.outputTag)
        guard matchesForeground(session) else {
            contactTimestamp = nil
            lastPosition = nil
            return
        }
        event.post(tap: .cgSessionEventTap)
        lastPosition = location
    }

    private func installEventTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            let original = Unmanaged.passUnretained(event)
            guard let context else { return original }
            let pipeline = Unmanaged<PointerPipeline>.fromOpaque(context).takeUnretainedValue()
            return autoreleasepool {
                pipeline.shouldForward(type: type, event: event) ? original : nil
            }
        }

        // Filter physical movement early when macOS allows it. The generated
        // absolute movement always enters the pipeline at the session tap.
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: context
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: context
        )
        guard let tap else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(input.runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func shouldForward(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return true
        }

        if event.getIntegerValueField(.eventSourceUserData) == Self.outputTag {
            return session.map(matchesForeground) ?? false
        }
        // Let native motion through immediately without a fresh, in-scope touch.
        guard let session, let contactTimestamp,
              isFresh(contactTimestamp), matchesForeground(session)
        else { return true }

        return false
    }

    private func isFresh(_ timestamp: UInt64) -> Bool {
        DispatchTime.now().uptimeNanoseconds - timestamp <= Self.contactTimeout
    }

    private func matchesForeground(_ session: MappingSession) -> Bool {
        guard !mapper.isActive else { return false }
        let application = workspace.frontmostApplication
        return application?.processIdentifier == session.pid && application?.bundleIdentifier == session.profile.id
    }
}
