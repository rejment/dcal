// The store, the age axis, and the shape of what the app opens with.

import Foundation
import Testing
@testable import DcalKit

@Test func editsKeepTheTimelineSorted() {
    var lifeline = Lifeline(events: [
        Event(title: "Later", start: Fixture.date(2026, 9, 10)),
        Event(title: "Earlier", start: Fixture.date(2020, 1, 1)),
    ])
    #expect(lifeline.events.map(\.title) == ["Earlier", "Later"])

    let middle = Event(title: "Middle", start: Fixture.date(2023, 6, 1))
    lifeline.upsert(middle)
    #expect(lifeline.events.map(\.title) == ["Earlier", "Middle", "Later"])

    var moved = middle
    moved.start = Fixture.date(2030, 1, 1)
    lifeline.upsert(moved)
    #expect(lifeline.events.map(\.title) == ["Earlier", "Later", "Middle"])
    #expect(lifeline.events.count == 3)

    lifeline.remove(id: middle.id)
    #expect(lifeline.events.map(\.title) == ["Earlier", "Later"])
}

@Test func overlapPicksUpStretchesThatStartedBeforeTheWindow() {
    let trip = Event(
        title: "Japan", start: Fixture.date(2026, 4, 2),
        duration: 16 * 86400, category: .travel, weight: .notable
    )
    let after = Event(title: "Later", start: Fixture.date(2026, 12, 1))
    let lifeline = Lifeline(events: [trip, after])

    let window = Fixture.date(2026, 4, 10)...Fixture.date(2026, 4, 11)
    #expect(lifeline.events(overlapping: window).map(\.title) == ["Japan"])
}

@Test func ageCountsBirthdaysNotYears() {
    let lifeline = SampleLifeline.make(now: Fixture.date(2026, 9, 10), calendar: Fixture.calendar)
    #expect(lifeline.birth == Fixture.date(1985, 6, 14, 4, 12))

    // Born 14 June 1985.
    #expect(lifeline.age(at: Fixture.date(1992, 6, 13), calendar: Fixture.calendar) == 6)
    #expect(lifeline.age(at: Fixture.date(1992, 6, 15), calendar: Fixture.calendar) == 7)
    #expect(lifeline.age(at: Fixture.date(1992, 8, 17), calendar: Fixture.calendar) == 7)
    // Before the beginning there is no age to give.
    #expect(lifeline.age(at: Fixture.date(1980, 1, 1), calendar: Fixture.calendar) == nil)
}

@Test func theSampleHasSomethingToSeeAtEveryZoom() {
    let now = Fixture.date(2026, 9, 10, 12)
    let lifeline = SampleLifeline.make(now: now, calendar: Fixture.calendar)

    // Today, in hours.
    let today = Fixture.date(2026, 9, 10)...Fixture.date(2026, 9, 11)
    #expect(lifeline.events(overlapping: today).count > 5)

    // A whole life, in milestones.
    let milestones = lifeline.events.filter { $0.weight == .milestone }
    #expect(milestones.count >= 12)
    #expect(milestones.first?.title == "Born")

    // And a future worth looking at, not just a past.
    #expect(lifeline.events.contains { $0.start > now.addingTimeInterval(365 * 86400) })
}

@Test func theStoreSurvivesARoundTrip() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = LifelineStore(url: directory.appendingPathComponent("lifeline.json"))
    #expect(try store.load() == nil)

    let original = SampleLifeline.make(now: Fixture.date(2026, 9, 10), calendar: Fixture.calendar)
    try store.save(original)
    let reloaded = try store.load()
    #expect(reloaded == original)
    #expect(reloaded?.events.count == original.events.count)
}
