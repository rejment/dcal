// The header has to answer "where am I" at every zoom, in the same shape.

import Foundation
import Testing
@testable import DcalKit

private func describe(span: TimeInterval, centre: Date = Fixture.date(2026, 9, 10, 12)) -> Whereabouts {
    Whereabouts.describe(
        scale: TimeScale(
            centre: centre,
            pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: span),
            height: 800
        ),
        calendar: Fixture.calendar
    )
}

@Test func theHeaderNamesTheDayThenTheMonthThenTheDecade() {
    let day: TimeInterval = 86400
    let year: TimeInterval = 31_556_952

    #expect(describe(span: 15 * 3600).context == "Thursday")
    #expect(describe(span: 15 * 3600).headline == "10 September 2026")
    #expect(describe(span: 6 * day).context == "Week 37")
    #expect(describe(span: 6 * day).headline == "September 2026")
    #expect(describe(span: 40 * day).context == "2026")
    #expect(describe(span: 40 * day).headline == "September")
    #expect(describe(span: 1.5 * year).context == "The 2020s")
    #expect(describe(span: 1.5 * year).headline == "2026")
    #expect(describe(span: 12 * year).context == "The 21st century")
    #expect(describe(span: 12 * year).headline == "The 2020s")

    // A whole life gets the years it actually covers.
    let lifetime = describe(span: 60 * year, centre: Fixture.date(2005, 1, 1))
    #expect(lifetime.context == "A lifetime")
    #expect(lifetime.headline == "1975–2035")
}

@Test func thereIsAlwaysAHeadlineAndItIsNeverEmpty() {
    for span in [2.0 * 3600, 86400.0, 20 * 86400.0, 200 * 86400.0, 3 * 31_556_952.0, 100 * 31_556_952.0] {
        let where0 = describe(span: span)
        #expect(!where0.headline.isEmpty)
        #expect(!where0.spanWords.isEmpty)
    }
}

@Test func spansAreRoundNumbersInTheLargestUsefulUnit() {
    #expect(Whereabouts.words(3600) == "one hour")
    #expect(Whereabouts.words(3 * 3600) == "3 hours")
    #expect(Whereabouts.words(86400) == "one day")
    #expect(Whereabouts.words(5 * 86400) == "5 days")
    #expect(Whereabouts.words(21 * 86400) == "3 weeks")
    #expect(Whereabouts.words(200 * 86400) == "7 months")
    #expect(Whereabouts.words(50 * 31_556_952) == "50 years")
}

@Test func centuriesAndOtherOrdinalsReadCorrectly() {
    #expect(Whereabouts.ordinal(1) == "1st")
    #expect(Whereabouts.ordinal(2) == "2nd")
    #expect(Whereabouts.ordinal(3) == "3rd")
    #expect(Whereabouts.ordinal(11) == "11th")
    #expect(Whereabouts.ordinal(12) == "12th")
    #expect(Whereabouts.ordinal(13) == "13th")
    #expect(Whereabouts.ordinal(21) == "21st")
}
