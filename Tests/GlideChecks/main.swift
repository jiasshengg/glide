import AppKit

enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let message): message
        }
    }
}

@main
enum GlideChecks {
    static func main() throws {
        try reversesLineBasedScrollAxes()
        try preservesFractionalScrollMagnitudes()
        try leavesContinuousScrollEventsUnchanged()
        print("Glide checks passed")
    }

    private static func reversesLineBasedScrollAxes() throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 3,
            wheel2: -2,
            wheel3: 0
        ) else {
            throw CheckFailure.mismatch("Could not create a line-based scroll event")
        }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        let originalPointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let originalPointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let originalFixedAxis1 = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let originalFixedAxis2 = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2)

        try expect(ScrollEventTransformer.reverseLineBasedScroll(event), "Line-based event was not reversed")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3, "Vertical line delta has the wrong sign")
        try expect(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 2, "Horizontal line delta has the wrong sign")
        try expect(hasOppositeSign(originalPointAxis1, event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)), "Vertical point delta has the wrong sign")
        try expect(hasOppositeSign(originalPointAxis2, event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)), "Horizontal point delta has the wrong sign")
        try expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1) == -originalFixedAxis1, "Vertical fixed-point delta has the wrong sign")
        try expect(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2) == -originalFixedAxis2, "Horizontal fixed-point delta has the wrong sign")
    }

    private static func leavesContinuousScrollEventsUnchanged() throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 12,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw CheckFailure.mismatch("Could not create a continuous scroll event")
        }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let originalData = event.data

        try expect(!ScrollEventTransformer.reverseLineBasedScroll(event), "Continuous event was incorrectly reversed")
        try expect(event.data == originalData, "Continuous event was modified")
    }

    private static func preservesFractionalScrollMagnitudes() throws {
        for lineDelta: Int32 in [0, 3, -3] {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 2,
                wheel1: lineDelta,
                wheel2: -lineDelta,
                wheel3: 0
            ) else {
                throw CheckFailure.mismatch("Could not create a fractional scroll event")
            }

            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.5)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -0.75)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 17)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -9)
            let fields: [CGEventField] = [
                .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
                .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2
            ]
            let originalValues = fields.map { event.getIntegerValueField($0) }
            guard let originalScroll = NSEvent(cgEvent: event) else {
                throw CheckFailure.mismatch("Could not convert the original wheel event")
            }
            let originalX = originalScroll.scrollingDeltaX
            let originalY = originalScroll.scrollingDeltaY

            try expect(ScrollEventTransformer.reverseLineBasedScroll(event), "Fractional wheel event was not reversed")
            for (field, original) in zip(fields, originalValues) {
                try expect(event.getIntegerValueField(field) == -original, "Scroll magnitude changed for \(field)")
            }
            guard let reversedScroll = NSEvent(cgEvent: event) else {
                throw CheckFailure.mismatch("Could not convert the reversed wheel event")
            }
            try expect(reversedScroll.scrollingDeltaX == -originalX, "AppKit horizontal scroll magnitude changed")
            try expect(reversedScroll.scrollingDeltaY == -originalY, "AppKit vertical scroll magnitude changed")

            ScrollEventTransformer.reverseLineBasedScroll(event)
            for (field, original) in zip(fields, originalValues) {
                try expect(event.getIntegerValueField(field) == original, "Reversing twice did not restore \(field)")
            }
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure.mismatch(message)
        }
    }

    private static func hasOppositeSign(_ original: Int64, _ transformed: Int64) -> Bool {
        (original > 0 && transformed < 0) || (original < 0 && transformed > 0) || (original == 0 && transformed == 0)
    }
}
