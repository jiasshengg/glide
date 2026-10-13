import CoreGraphics

final class ScrollEventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool {
        eventTap.map(CGEvent.tapIsEnabled(tap:)) ?? false
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            return isRunning
        }

        let scrollWheelMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let owner = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollWheelMask,
            callback: Self.callback,
            userInfo: owner
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
    }

    deinit {
        stop()
    }

    private func reenable() {
        guard let eventTap else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let owner = Unmanaged<ScrollEventTap>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            owner.reenable()
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            ScrollEventTransformer.reverseLineBasedScroll(event)
        }

        return Unmanaged.passUnretained(event)
    }
}

enum ScrollEventTransformer {
    private static let scrollFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1,
        .scrollWheelEventDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis1,
        .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventPointDeltaAxis1,
        .scrollWheelEventPointDeltaAxis2
    ]

    @discardableResult
    static func reverseLineBasedScroll(_ event: CGEvent) -> Bool {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else {
            return false
        }

        // Setting line deltas recalculates fixed-point and point deltas. Capture
        // every original value first, then restore their magnitudes in this order.
        let originalValues = scrollFields.map { event.getIntegerValueField($0) }
        for (field, value) in zip(scrollFields, originalValues) {
            event.setIntegerValueField(field, value: -value)
        }
        return true
    }
}
