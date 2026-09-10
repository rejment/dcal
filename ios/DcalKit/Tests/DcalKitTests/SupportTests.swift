// Shared fixtures. Everything is pinned to Stockholm and a POSIX locale so
// the results do not depend on where the machine running the tests is.
//
// Swift Testing rather than XCTest: the command line tools ship the former
// but not the latter, and these must run without Xcode.

import Foundation
import Testing
@testable import DcalKit

enum Fixture {
    static let timeZone = TimeZone(identifier: "Europe/Stockholm")!

    static var tickCalendar: TickCalendar {
        TickCalendar.standard(timeZone: timeZone, locale: Locale(identifier: "en_US_POSIX"))
    }

    static var calendar: Calendar { tickCalendar.calendar }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }
}

@Test func smoothstepRampsBetweenItsEdges() {
    #expect(Curve.smoothstep(10, 20, 5) == 0)
    #expect(Curve.smoothstep(10, 20, 25) == 1)
    #expect(abs(Curve.smoothstep(10, 20, 15) - 0.5) < 1e-9)
    // Monotonic, which is what stops a level of detail from flickering.
    #expect(Curve.smoothstep(10, 20, 13) < Curve.smoothstep(10, 20, 17))
}

@Test func rgbMixesAndStaysInRange() {
    let black = RGB(0, 0, 0)
    let white = RGB(1, 1, 1)
    #expect(black.mixed(with: white, amount: 0.5) == RGB(0.5, 0.5, 0.5))
    #expect(black.mixed(with: white, amount: 4) == white)
    #expect(white.scaled(by: 10) == white)
    #expect(RGB(hex: 0xF5C46B) == RGB(245.0 / 255, 196.0 / 255, 107.0 / 255))
}
