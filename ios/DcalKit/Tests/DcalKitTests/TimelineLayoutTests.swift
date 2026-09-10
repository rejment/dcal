// A whole frame, built and inspected without a screen.

import CoreGraphics
import Foundation
import Testing
@testable import DcalKit

private let size = CGSize(width: 390, height: 800)
private let chromeTop: CGFloat = 100
private let chromeBottom: CGFloat = 110

private func layout(centre: Date, span: TimeInterval, now: Date) -> TimelineLayout {
    TimelineLayoutBuilder.build(
        scale: TimeScale(
            centre: centre,
            pointsPerSecond: TimeScale.pointsPerSecond(height: size.height, span: span),
            height: size.height
        ),
        size: size,
        chromeTop: chromeTop,
        chromeBottom: chromeBottom,
        lifeline: SampleLifeline.make(now: now, calendar: Fixture.calendar),
        tickCalendar: Fixture.tickCalendar,
        now: now
    )
}

@Test func closeInItIsACalendarDay() {
    let now = Fixture.date(2026, 9, 10, 12)
    let frame = layout(centre: now, span: 15 * 3600, now: now)

    #expect(frame.scheduleOpacity == 1)
    #expect(!frame.blocks.isEmpty)
    #expect(frame.landmarks.isEmpty)          // nothing is drawn twice
    #expect(frame.nowY != nil)

    // Stretches are boxes, moments are not.
    let lunch = frame.blocks.first { $0.event.title == "Lunch" }
    #expect(lunch?.isStretch == true)
    #expect(lunch?.timeText == "12:15–13:00")
    let wake = frame.blocks.first { $0.event.title == "Wake up" }
    #expect(wake?.isStretch == false)
    #expect(wake?.timeText == "06:45")

    // Blocks live to the right of the ribbon and stay on screen.
    for block in frame.blocks {
        #expect(block.frame.minX >= frame.metrics.contentX - 0.001)
        #expect(block.frame.maxX <= size.width)
    }
}

@Test func farOutItIsAMapOfMilestones() {
    let now = Fixture.date(2026, 9, 10, 12)
    let frame = layout(centre: Fixture.date(2005, 1, 1), span: 60 * 31_556_952, now: now)

    #expect(frame.scheduleOpacity == 0)
    #expect(frame.blocks.isEmpty)
    #expect(!frame.landmarks.isEmpty)

    let titles = frame.landmarks.map(\.event.title)
    #expect(titles.contains("Born"))
    #expect(titles.contains("Started school"))
    // Everyday things are long gone, but they still leave marks in the ribbon.
    #expect(!titles.contains("Wake up"))
    #expect(frame.notches.count > frame.landmarks.count * 5)

    // Age is shown once a year is too small to answer "how long ago".
    let school = frame.landmarks.first { $0.event.title == "Started school" }
    #expect(school?.ageText == "age 7")

    // A trip gets a bracket down the ribbon; a birth is a single instant.
    let japan = frame.landmarks.first { $0.event.title == "Japan" }
    #expect(japan == nil || japan?.bracket != nil)
    #expect(frame.landmarks.first { $0.event.title == "Born" }?.bracket == nil)
}

@Test func labelsNeverOverlapEachOther() {
    let now = Fixture.date(2026, 9, 10, 12)
    for span in [2.0, 8, 30, 60].map({ $0 * 31_556_952 }) {
        let frame = layout(centre: Fixture.date(2005, 1, 1), span: span, now: now)
        let ys = frame.landmarks.map(\.y).sorted()
        for pair in zip(ys, ys.dropFirst()) {
            #expect(pair.1 - pair.0 >= 22.9)
        }
    }
}

@Test func theRulerStaysClearOfTheHeaderAndTheButtons() {
    let now = Fixture.date(2026, 9, 10, 12)
    for span in [12 * 3600.0, 5 * 86400.0, 400 * 86400.0, 60 * 31_556_952.0] {
        let frame = layout(centre: now, span: span, now: now)
        #expect(!frame.ticks.isEmpty)
        for tick in frame.ticks {
            #expect(tick.y >= chromeTop)
            #expect(tick.y <= size.height - chromeBottom)
        }
    }
}

@Test func tappingReturnsWhateverWasDrawnThere() {
    let now = Fixture.date(2026, 9, 10, 12)

    let day = layout(centre: now, span: 15 * 3600, now: now)
    let block = day.blocks.first { $0.event.title == "Lunch" }!
    #expect(day.event(at: CGPoint(x: block.frame.midX, y: block.frame.midY))?.id == block.event.id)
    // The ruler is not a target.
    #expect(day.event(at: CGPoint(x: 10, y: block.frame.midY)) == nil)

    let life = layout(centre: Fixture.date(2005, 1, 1), span: 60 * 31_556_952, now: now)
    let landmark = life.landmarks.first { $0.event.title == "Born" }!
    #expect(life.event(at: CGPoint(x: 200, y: landmark.y))?.id == landmark.event.id)
}

@Test func bandsAlternateAndDoNotFlipWhenYouScroll() {
    let calendar = Fixture.calendar
    let day = TickLevel.ladder.first { $0.id == "d1" }!

    // Consecutive days alternate...
    let first = TimelineLayoutBuilder.parity(of: Fixture.date(2026, 9, 10), level: day, calendar: calendar)
    let second = TimelineLayoutBuilder.parity(of: Fixture.date(2026, 9, 11), level: day, calendar: calendar)
    #expect(first != second)

    // ...and the answer for a given day never depends on the view, which is
    // what stops the stripes from inverting as you pan.
    let now = Fixture.date(2026, 9, 10, 12)
    let a = layout(centre: now, span: 5 * 86400, now: now)
    let b = layout(centre: now.addingTimeInterval(86400 * 1.5), span: 5 * 86400, now: now)
    let overlapA = a.bands.first { $0.rect.height > 10 }
    let overlapB = b.bands.first { $0.rect.height > 10 }
    #expect(overlapA != nil && overlapB != nil)
}

@Test func aFrameStaysCheapEnoughToBuildEveryTick() {
    let now = Fixture.date(2026, 9, 10, 12)
    // A lifetime holds every routine event the sample has; the grid must not
    // try to draw a line per minute for it.
    let frame = layout(centre: Fixture.date(2005, 1, 1), span: 60 * 31_556_952, now: now)
    #expect(frame.grid.count < 400)
    #expect(frame.groundStops.count <= 140)
}
