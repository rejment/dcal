// The glow in the ribbon: it has to mean the same thing at every zoom.

import CoreGraphics
import Foundation
import Testing
@testable import DcalKit

private let height: CGFloat = 800

private func scale(centre: Date, span: TimeInterval) -> TimeScale {
    TimeScale(
        centre: centre,
        pointsPerSecond: TimeScale.pointsPerSecond(height: height, span: span),
        height: height
    )
}

private func density(_ perDay: [(Date, Int)]) -> PhotoDensity {
    var moments: [PhotoMoment] = []
    for (day, count) in perDay {
        moments += (0..<count).map {
            PhotoMoment(date: day.addingTimeInterval(Double($0) * 300 + 36000))
        }
    }
    return PhotoDensity(moments: moments, calendar: Fixture.calendar)
}

@Test func nothingPhotographedGlowsNotAtAll() {
    let empty = PhotoDensity(moments: [], calendar: Fixture.calendar)
    #expect(empty.isEmpty)
    let profile = empty.profile(scale: scale(centre: Fixture.date(2020, 1, 1), span: 86400))
    #expect(profile.allSatisfy { $0 == 0 })
}

@Test func aPhotographedDayFillsItsOwnHeightAndNoMore() {
    let day = Fixture.date(2020, 6, 15)
    let built = density([(day, 20)])
    let view = scale(centre: day.addingTimeInterval(43200), span: 4 * 86400)
    let profile = built.profile(scale: view)

    // Lit somewhere, dark somewhere: one day out of four on screen.
    #expect(profile.contains { $0 > 0.3 })
    #expect(profile.contains { $0 == 0 })

    // The lit stretch is about a quarter of the view, being one day of four.
    let lit = profile.filter { $0 > 0 }.count
    let expected = profile.count / 4
    #expect(abs(lit - expected) <= 3)
}

@Test func theGlowDoesNotChangeWhenYouScroll() {
    let day = Fixture.date(2020, 6, 15)
    let built = density([(day, 30)])

    var peaks: [Double] = []
    for shift in stride(from: -2.0, through: 2.0, by: 0.25) {
        let view = scale(
            centre: day.addingTimeInterval(43200 + shift * 86400),
            span: 10 * 86400
        )
        peaks.append(built.profile(scale: view).max() ?? 0)
    }
    // Same day, same brightness, wherever it sits on screen.
    let first = peaks[0]
    for peak in peaks { #expect(abs(peak - first) < 0.2) }
}

@Test func aBusyStretchOutshinesAQuietOneAtEveryZoom() {
    var perDay: [(Date, Int)] = []
    // A quiet year, then a heavily photographed one.
    for offset in 0..<360 {
        perDay.append((Fixture.date(2018, 1, 1).addingTimeInterval(Double(offset) * 86400), 1))
    }
    for offset in 0..<360 {
        perDay.append((Fixture.date(2019, 1, 1).addingTimeInterval(Double(offset) * 86400), 25))
    }
    let built = density(perDay)

    // Read the glow *at* each date rather than the brightest thing on screen -
    // zoomed out far enough, both years are in view at once and the maximum
    // says nothing about either of them.
    for span in [30 * 86400.0, 400 * 86400.0, 6 * 31_556_952.0] {
        let quietDay = Fixture.date(2018, 6, 1)
        let busyDay = Fixture.date(2019, 6, 1)
        let quiet = glow(built, at: quietDay, span: span)
        let busy = glow(built, at: busyDay, span: span)
        #expect(busy > quiet, "at a span of \(Int(span / 86400)) days")
        #expect(quiet < 0.25, "a lightly photographed year should stay dim")
    }
}

/// The value the ribbon would paint at one instant, in a view centred on it.
private func glow(
    _ density: PhotoDensity,
    at date: Date,
    span: TimeInterval,
    bucketPoints: CGFloat = 2
) -> Double {
    let view = scale(centre: date, span: span)
    let profile = density.profile(scale: view, bucketPoints: bucketPoints)
    let index = Int(view.y(for: date) / bucketPoints)
    guard profile.indices.contains(index) else { return 0 }
    return profile[index]
}

@Test func anEmptyDecadeStaysDarkWithAWholeLifeOnScreen() {
    var perDay: [(Date, Int)] = []
    for year in [1995, 1996, 2015, 2016] {
        for offset in stride(from: 0, to: 350, by: 2) {
            perDay.append((Fixture.date(year, 1, 1).addingTimeInterval(Double(offset) * 86400), 8))
        }
    }
    let built = density(perDay)
    let view = scale(centre: Fixture.date(2005, 1, 1), span: 40 * 31_556_952)
    let profile = built.profile(scale: view)

    // The middle of the view is the empty stretch between them.
    let middle = profile[profile.count / 2]
    #expect(middle == 0)
    #expect(profile.max() ?? 0 > 0.2)
}

@Test func theGlowIsNeverOutOfRange() {
    // One absurd day should saturate, not overflow.
    let built = density([(Fixture.date(2020, 3, 1), 4000)])
    for span in [3600.0, 86400.0, 30 * 86400.0, 31_556_952.0, 100 * 31_556_952.0] {
        let profile = built.profile(scale: scale(centre: Fixture.date(2020, 3, 1), span: span))
        #expect(profile.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

@Test func aLifetimeOfCountsIsSmallEnoughToKeep() throws {
    var perDay: [(Date, Int)] = []
    for offset in 0..<(40 * 365) {
        perDay.append((Fixture.date(1985, 1, 1).addingTimeInterval(Double(offset) * 86400), 6))
    }
    let built = density(perDay)
    let data = try JSONEncoder().encode(built)
    // Forty years of daily counts. Small enough to sit on disk and be read
    // at launch without anyone noticing.
    #expect(data.count < 400_000)

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = PhotoDensityStore(url: directory.appendingPathComponent("density.json"))
    #expect(store.load() == nil)
    store.save(built)
    #expect(store.load() == built)
}
