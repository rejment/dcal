// Boundaries come from Calendar, not from arithmetic on seconds, and these
// are the cases where the difference shows.

import Foundation
import Testing
@testable import DcalKit

@Test func floorsToTheStartOfEachUnit() {
    let cal = Fixture.tickCalendar
    let instant = Fixture.date(2026, 9, 10, 14, 37)

    #expect(cal.floor(instant, to: level("m15")) == Fixture.date(2026, 9, 10, 14, 30))
    #expect(cal.floor(instant, to: level("h3")) == Fixture.date(2026, 9, 10, 12))
    #expect(cal.floor(instant, to: level("d1")) == Fixture.date(2026, 9, 10))
    // 10 September 2026 is a Thursday; the week starts on the Monday.
    #expect(cal.floor(instant, to: level("w1")) == Fixture.date(2026, 9, 7))
    #expect(cal.floor(instant, to: level("mo1")) == Fixture.date(2026, 9, 1))
    #expect(cal.floor(instant, to: level("mo3")) == Fixture.date(2026, 7, 1))
    #expect(cal.floor(instant, to: level("y10")) == Fixture.date(2020, 1, 1))
    #expect(cal.floor(instant, to: level("y50")) == Fixture.date(2000, 1, 1))
}

@Test func daylightSavingDaysAreNotTwentyFourHours() {
    let cal = Fixture.tickCalendar
    // Stockholm springs forward on 29 March 2026 and falls back on 25 October.
    let spring = Fixture.date(2026, 3, 29)
    let autumn = Fixture.date(2026, 10, 25)

    #expect(cal.advance(spring, by: level("d1")).timeIntervalSince(spring) == 23 * 3600)
    #expect(cal.advance(autumn, by: level("d1")).timeIntervalSince(autumn) == 25 * 3600)

    // The hour lines follow the wall clock: 02:00 never happens in spring.
    let hours = cal.ticks(level("h1"), from: spring, to: cal.advance(spring, by: level("d1")))
    let labels = hours.map { cal.label(for: $0, level: level("h1"), tight: false) }
    #expect(labels.contains("01:00"))
    #expect(!labels.contains("02:00"))
    #expect(labels.contains("03:00"))
}

@Test func ticksCoverTheRangeAndStayInside() {
    let cal = Fixture.tickCalendar
    let from = Fixture.date(2026, 9, 10, 9, 20)
    let to = Fixture.date(2026, 9, 10, 12, 40)
    let hours = cal.ticks(level("h1"), from: from, to: to)

    #expect(hours == [
        Fixture.date(2026, 9, 10, 10),
        Fixture.date(2026, 9, 10, 11),
        Fixture.date(2026, 9, 10, 12),
    ])
    #expect(cal.ticks(level("h1"), from: to, to: from).isEmpty)
}

@Test func labelsReadTheWayTheRulerNeeds() {
    let cal = Fixture.tickCalendar
    #expect(cal.label(for: Fixture.date(2026, 9, 10, 7, 30), level: level("m15"), tight: true) == "07:30")
    #expect(cal.label(for: Fixture.date(2026, 9, 10), level: level("d1"), tight: true) == "10")
    #expect(cal.label(for: Fixture.date(2026, 9, 10), level: level("d1"), tight: false).hasSuffix(" 10"))
    #expect(cal.label(for: Fixture.date(2026, 9, 7), level: level("w1"), tight: false) == "w37")
    #expect(cal.label(for: Fixture.date(2026, 9, 1), level: level("mo1"), tight: false) == "September")
    #expect(cal.label(for: Fixture.date(2026, 7, 1), level: level("mo3"), tight: false) == "Q3")
    #expect(cal.label(for: Fixture.date(2026, 1, 1), level: level("y1"), tight: false) == "2026")
}

@Test func weekendsAreFridayNightThroughSunday() {
    let cal = Fixture.tickCalendar
    #expect(!cal.isWeekend(Fixture.date(2026, 9, 10, 12)))  // Thursday
    #expect(cal.isWeekend(Fixture.date(2026, 9, 12, 12)))   // Saturday
    #expect(cal.isWeekend(Fixture.date(2026, 9, 13, 12)))   // Sunday
}

@Test func theRulerPicksAUnitYouCanActuallyRead() {
    func major(spanSeconds: Double) -> String {
        let scale = TimeScale(
            centre: Fixture.date(2026, 9, 10, 12),
            pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: spanSeconds),
            height: 800
        )
        return TickCalendar.levels(for: scale).major.id
    }
    #expect(major(spanSeconds: 2.5 * 3600) == "m15")
    #expect(major(spanSeconds: 4 * 3600) == "h1")
    #expect(major(spanSeconds: 15 * 3600) == "h3")
    #expect(major(spanSeconds: 5 * 86400) == "d1")
    #expect(major(spanSeconds: 40 * 86400) == "w1")
    #expect(major(spanSeconds: 400 * 86400) == "mo3")
    #expect(major(spanSeconds: 12 * 31_556_952) == "y1")
    #expect(major(spanSeconds: 90 * 31_556_952) == "y10")

    // Coarse to fine, never skipping backwards as you zoom in.
    let ladder = TickLevel.ladder.map(\.id)
    var previous = ladder.count
    for span in [90.0, 12, 1, 0.1, 0.01, 0.001].map({ $0 * 31_556_952 }) {
        let index = ladder.firstIndex(of: major(spanSeconds: span))!
        #expect(index <= previous)
        previous = index
    }
}

private func level(_ id: String) -> TickLevel {
    TickLevel.ladder.first { $0.id == id }!
}
