// The colour of the column is the only thing carrying "when is this?" before
// a label loads, so it has to be continuous and it has to point the right way.

import Foundation
import Testing
@testable import DcalKit

private func brightness(_ colour: RGB) -> Double {
    colour.red + colour.green + colour.blue
}

@Test func theSkyWrapsAroundMidnight() {
    let midnight = SkyPalette.sky(hour: 0)
    let alsoMidnight = SkyPalette.sky(hour: 24)
    #expect(abs(midnight.red - alsoMidnight.red) < 1e-9)
    #expect(abs(midnight.green - alsoMidnight.green) < 1e-9)
    #expect(abs(midnight.blue - alsoMidnight.blue) < 1e-9)
    // And nothing jumps: neighbouring quarter-hours stay close together.
    var previous = SkyPalette.sky(hour: 0)
    for step in stride(from: 0.25, through: 24, by: 0.25) {
        let next = SkyPalette.sky(hour: step)
        let jump = abs(next.red - previous.red) + abs(next.green - previous.green)
            + abs(next.blue - previous.blue)
        #expect(jump < 0.2)
        previous = next
    }
}

@Test func middayIsBrighterThanTheMiddleOfTheNight() {
    #expect(brightness(SkyPalette.sky(hour: 12)) > brightness(SkyPalette.sky(hour: 3)))
    #expect(brightness(SkyPalette.sky(hour: 12)) > brightness(SkyPalette.sky(hour: 23)))
    // Dawn and dusk are the warm moments. Not literally red-dominant - the
    // colour is a mauve - but the red/blue balance swings hard towards red
    // and back, which is what makes sunrise legible as a band.
    func warmth(_ hour: Double) -> Double {
        let colour = SkyPalette.sky(hour: hour)
        return colour.red - colour.blue
    }
    #expect(warmth(7) > warmth(4))
    #expect(warmth(7) > warmth(10))
    #expect(warmth(18.6) > warmth(16))
    #expect(warmth(2) < 0)   // the middle of the night is plain blue
}

@Test func julyIsWarmAndJanuaryIsCold() {
    let july = SkyPalette.seasonHue(month: 7, dayFraction: 0.5)
    let january = SkyPalette.seasonHue(month: 1, dayFraction: 0.5)
    #expect(july < 60)        // amber end of the ramp
    #expect(january > 190)    // blue end
    // Continuous across New Year rather than snapping back.
    let december = SkyPalette.seasonHue(month: 12, dayFraction: 0.99)
    #expect(abs(december - SkyPalette.seasonHue(month: 1, dayFraction: 0)) < 6)
}

@Test func theGroundHandsOverFromHoursToSeasonsToDecades() {
    let calendar = Fixture.calendar
    let instant = Fixture.date(2026, 7, 15, 3)

    func ground(span: TimeInterval) -> RGB {
        SkyPalette.ground(
            at: instant,
            scale: TimeScale(
                centre: instant,
                pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: span),
                height: 800
            ),
            calendar: calendar
        )
    }

    // Close in, 3am in July is night: dark, and darker than the same instant
    // read at year scale, where only the summer tint survives.
    let closeUp = ground(span: 12 * 3600)
    let yearScale = ground(span: 400 * 86400)
    #expect(brightness(closeUp) < brightness(yearScale))
    #expect(yearScale.red > yearScale.blue)   // midsummer is warm

    // A whole life on screen: seasons are gone, nothing is out of range.
    let lifetime = ground(span: 90 * 31_556_952)
    for channel in [lifetime.red, lifetime.green, lifetime.blue] {
        #expect(channel >= 0 && channel <= 1)
    }
}

@Test func theScheduleViewFadesInRatherThanSnapping() {
    func opacity(span: TimeInterval) -> Double {
        SkyPalette.scheduleOpacity(for: TimeScale(
            centre: Fixture.date(2026, 9, 10),
            pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: span),
            height: 800
        ))
    }
    #expect(opacity(span: 3 * 86400) == 1)          // a day is tall: full schedule
    #expect(opacity(span: 60 * 86400) == 0)         // two months: landmarks only
    let middle = opacity(span: 6 * 86400)
    #expect(middle > 0 && middle < 1)               // both drawn, crossfading
}
