// The file someone edits on a desktop. Reading has to be forgiving; writing
// has to produce something worth opening.

import Foundation
import Testing
@testable import DcalKit

private var document: LifelineDocument { LifelineDocument(calendar: Fixture.calendar) }

@Test func aLifelineSurvivesTheRoundTrip() throws {
    let original = SampleLifeline.make(now: Fixture.date(2026, 9, 10), calendar: Fixture.calendar)
    let text = document.text(for: original)
    let back = try document.lifeline(from: text)

    #expect(back.events.count == original.events.count)
    for (before, after) in zip(original.events, back.events) {
        #expect(before.id == after.id)
        #expect(before.title == after.title)
        #expect(before.category == after.category)
        #expect(before.weight == after.weight)
        #expect(before.note == after.note)
        #expect(before.duration == after.duration)
        // Seconds are dropped on the way out - nothing here needs them.
        #expect(abs(before.start.timeIntervalSince(after.start)) < 60)
    }
}

@Test func aTitleAndADateIsEnoughToTypeIn() throws {
    let lifeline = try document.lifeline(from: """
    { "events": [
        { "title": "Started school", "start": "1992-08-17" },
        { "title": "Moved to the coast", "start": "1996-07-01" }
    ] }
    """)
    #expect(lifeline.events.map(\.title) == ["Started school", "Moved to the coast"])
    #expect(lifeline.events[0].start == Fixture.date(1992, 8, 17))
    #expect(lifeline.events[0].duration == 0)
    #expect(lifeline.events[0].weight == .worthRemembering)
    // Every row gets an identity even when the file gives none.
    #expect(lifeline.events[0].id != lifeline.events[1].id)
}

@Test func datesAreReadHoweverTheyWereWritten() {
    let midnight = Fixture.date(1985, 6, 14)
    let morning = Fixture.date(1985, 6, 14, 4, 12)

    #expect(document.date(from: "1985-06-14") == midnight)
    #expect(document.date(from: "1985-06-14 04:12") == morning)
    #expect(document.date(from: "1985-06-14T04:12") == morning)
    #expect(document.date(from: "1985-06-14 04:12:00") == morning)
    #expect(document.date(from: "  1985-06-14  ") == midnight)
    // What the app's own store file contains: ISO 8601, in UTC.
    #expect(document.date(from: "1985-06-14T02:12:00Z") == morning)
    #expect(document.date(from: "not a date") == nil)
    #expect(document.date(from: "") == nil)
}

@Test func lengthsAreReadHoweverTheyWereWritten() {
    #expect(document.duration(from: "90 minutes") == 5400)
    #expect(document.duration(from: "90 min") == 5400)
    #expect(document.duration(from: "2 hours") == 7200)
    #expect(document.duration(from: "2h") == 7200)
    #expect(document.duration(from: "16 days") == 16 * 86400.0)
    #expect(document.duration(from: "1 week") == 604800)
    #expect(document.duration(from: "moment") == 0)
    #expect(document.duration(from: "") == 0)
    #expect(document.duration(from: "3600") == 3600)   // bare seconds
    #expect(document.duration(from: "a while") == nil)
}

@Test func lengthsAreWrittenInWholeUnits() {
    #expect(document.spell(3600) == "1 hour")
    #expect(document.spell(5400) == "90 minutes")
    #expect(document.spell(16 * 86400) == "16 days")
    #expect(document.spell(604800) == "1 week")
    #expect(document.spell(2 * 604800) == "2 weeks")
}

@Test func theStoreFileImportsAsItStands() throws {
    // Seconds for duration, a number for weight, ISO dates with a zone: the
    // exact shape LifelineStore writes, so a file lifted off the device works.
    let lifeline = try document.lifeline(from: """
    { "events": [
        { "title": "Japan", "start": "2016-04-02T00:00:00+02:00",
          "duration": 1382400, "weight": 2, "category": "travel", "note": "" }
    ] }
    """)
    let japan = lifeline.events[0]
    #expect(japan.duration == 16 * 86400)
    #expect(japan.weight == .notable)
    #expect(japan.category == .travel)
}

@Test func weightsReadAsWordsOrNumbers() throws {
    let lifeline = try document.lifeline(from: """
    { "events": [
        { "title": "a", "start": "2020-01-01", "weight": "milestone" },
        { "title": "b", "start": "2020-01-02", "weight": "worth remembering" },
        { "title": "c", "start": "2020-01-03", "weight": "everyday" },
        { "title": "d", "start": "2020-01-04", "weight": 2 }
    ] }
    """)
    #expect(lifeline.events.map(\.weight) == [.milestone, .worthRemembering, .everyday, .notable])
}

@Test func aBareListOfEventsWorksToo() throws {
    // Pasted out of the middle of a file, without the wrapper.
    let lifeline = try document.lifeline(from: """
    [ { "title": "Born", "start": "1985-06-14 04:12", "weight": "milestone" } ]
    """)
    #expect(lifeline.events.count == 1)
    #expect(lifeline.birth == Fixture.date(1985, 6, 14, 4, 12))
}

@Test func mistakesSayWhichEventAndWhatToDoAboutIt() {
    func failure(_ text: String) -> LifelineDocumentError? {
        do { _ = try document.lifeline(from: text); return nil }
        catch let error as LifelineDocumentError { return error }
        catch { return nil }
    }

    #expect(failure("not json at all") == .notReadable)
    #expect(failure("{ \"events\": [] }") == .noEvents)
    #expect(failure("""
    { "events": [ { "start": "2020-01-01" } ] }
    """) == .missingTitle(row: 1))
    #expect(failure("""
    { "events": [ { "title": "Born", "start": "1985-06-14" },
                  { "title": "School", "start": "14 juni 1992" } ] }
    """) == .badDate(row: 2, title: "School", value: "14 juni 1992"))
    #expect(failure("""
    { "events": [ { "title": "Japan", "start": "2016-04-02", "lasts": "a fortnight" } ] }
    """) == .badDuration(row: 1, title: "Japan", value: "a fortnight"))
    #expect(failure("""
    { "events": [ { "title": "Born", "start": "1985-06-14", "weight": "huge" } ] }
    """) == .badWeight(row: 1, title: "Born", value: "huge"))
    #expect(failure("""
    { "events": [ { "title": "Born", "start": "1985-06-14", "category": "birthday" } ] }
    """) == .badCategory(row: 1, title: "Born", value: "birthday"))

    // And the message actually tells you what to type instead.
    let message = LifelineDocumentError
        .badDate(row: 2, title: "School", value: "14 juni 1992").errorDescription ?? ""
    #expect(message.contains("School"))
    #expect(message.contains("1985-06-14"))
}

@Test func quotesAndNewlinesInNotesSurvive() throws {
    let awkward = Event(
        title: "The \"good\" flat",
        start: Fixture.date(2013, 5, 1),
        note: "Line one.\nLine two with a \\ backslash and a \"quote\"."
    )
    let text = document.text(for: Lifeline(events: [awkward]))
    let back = try document.lifeline(from: text)
    #expect(back.events[0].title == awkward.title)
    #expect(back.events[0].note == awkward.note)
}

@Test func whatIsWrittenIsWorthOpening() {
    let lifeline = Lifeline(events: [
        Event(title: "Born", start: Fixture.date(1985, 6, 14, 4, 12),
              category: .life, weight: .milestone, note: "Six weeks early."),
        Event(title: "Japan", start: Fixture.date(2016, 4, 2), duration: 16 * 86400,
              category: .travel, weight: .notable),
    ])
    let text = document.text(for: lifeline)

    #expect(text.contains("\"dcal\": 1"))
    #expect(text.contains("\"title\": \"Born\", \"start\": \"1985-06-14 04:12\""))
    #expect(text.contains("\"weight\": \"milestone\""))
    #expect(text.contains("\"lasts\": \"16 days\""))
    // A moment carries no length at all rather than a confusing zero.
    #expect(!text.contains("\"lasts\": \"0"))
    // One event per line, so a diff of two backups reads.
    #expect(text.split(separator: "\n").filter { $0.contains("\"title\"") }.count == 2)
}
