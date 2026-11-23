import AppKit
import CoreGraphics

private struct ContactSample {
    let x: Double
    let y: Double
    let touching: Bool
    let timestamp = ProcessInfo.processInfo.systemUptime
}

// The private framework delivers on its own thread. Keep only the latest
// frame so a busy UI cannot play back a backlog of stale cursor movements.
private final class ContactRelay {
    private let lock = NSLock()
    private var latest: ContactSample?
    private var scheduled = false
    @MainActor var receive: ((ContactSample) -> Void)?

    func submit(_ sample: ContactSample) {
        lock.lock()
        latest = sample
        let shouldSchedule = !scheduled
        scheduled = true
        lock.unlock()

        if shouldSchedule {
            DispatchQueue.main.async { [weak self] in self?.deliver() }
        }
    }

    func reset() {
        lock.lock()
        latest = nil
        lock.unlock()
    }

    @MainActor private func deliver() {
        lock.lock()
        let sample = latest
        latest = nil
        scheduled = false
        lock.unlock()

        if let sample { receive?(sample) }
    }
}

private let trackpadCallback: TPContactCallback = { x, y, touching, context in
    guard let context else { return }
    let relay = Unmanaged<ContactRelay>.fromOpaque(context).takeUnretainedValue()
    relay.submit(ContactSample(x: x, y: y, touching: touching))
}

@MainActor
final class TrackpadEngine {
    enum State {
        case running
        case eventTapUnavailable
        case frameworkUnavailable
        case noTrackpad
    }

    private struct Session {
        var profile: AppProfile
        var pid: pid_t
        var bounds: CGRect
    }

    private static let outputTag: Int64 = 0x4D_54_50_41_50_50
    private static let contactTimeout: TimeInterval = 0.055

    private let relay = ContactRelay()
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private var session: Session?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var contactTimestamp: TimeInterval?
    private var point: CGPoint?

    init() {
        relay.receive = { [weak self] sample in self?.handle(sample) }
    }

    func activate(_ profile: AppProfile, pid: pid_t, bounds: CGRect) -> State {
        if let session, session.pid == pid {
            if session.bounds != bounds || session.profile != profile {
                contactTimestamp = nil
                point = nil
                relay.reset()
            }
            self.session = Session(profile: profile, pid: pid, bounds: bounds)
            return .running
        }

        stop()
        guard installEventTap() else { return .eventTapUnavailable }
        let deviceCount = TPStart(trackpadCallback, Unmanaged.passUnretained(relay).toOpaque())
        guard deviceCount > 0 else {
            stop()
            return deviceCount == 0 ? .noTrackpad : .frameworkUnavailable
        }

        session = Session(profile: profile, pid: pid, bounds: bounds)
        return .running
    }

    func stop() {
        contactTimestamp = nil
        point = nil
        if session != nil { TPStop() }
        session = nil
        relay.reset()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func installEventTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, context in
            let eventForForwarding = Unmanaged.passUnretained(event)
            guard let context else { return eventForForwarding }
            let engine = Unmanaged<TrackpadEngine>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                engine.shouldForward(type: type, event: event) ? eventForForwarding : nil
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
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func shouldForward(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return true
        }

        // Leave clicks and scrolling alone, and pass physical mouse movement
        // through whenever there is no fresh trackpad position.
        if event.getIntegerValueField(.eventSourceUserData) == Self.outputTag {
            return session.map(matchesForeground) ?? false
        }
        guard let session, let contactTimestamp,
              ProcessInfo.processInfo.systemUptime - contactTimestamp <= Self.contactTimeout,
              matchesForeground(session)
        else { return true }

        return false
    }

    private func handle(_ sample: ContactSample) {
        guard sample.touching, let session, matchesForeground(session),
              ProcessInfo.processInfo.systemUptime - sample.timestamp <= Self.contactTimeout,
              let location = session.profile.map(x: sample.x, y: sample.y, to: session.bounds)
        else {
            contactTimestamp = nil
            point = nil
            return
        }

        contactTimestamp = sample.timestamp
        // Report immediately on initial contact, even if the finger lands
        // without the small slide needed for a native mouse-moved event.
        guard point != location else { return }

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
        event.post(tap: .cgSessionEventTap)
        point = location
    }

    private func matchesForeground(_ session: Session) -> Bool {
        guard NSApp?.isActive != true else { return false }
        let application = NSWorkspace.shared.frontmostApplication
        return application?.processIdentifier == session.pid && application?.bundleIdentifier == session.profile.id
    }
}
