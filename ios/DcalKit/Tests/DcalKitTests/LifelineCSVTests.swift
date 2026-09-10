// The spreadsheet form. Whatever program saved it.

import Foundation
import Testing
@testable import DcalKit

private var document: LifelineDocument { LifelineDocument(calendar: Fixture.calendar) }

@Test func aLifelineSurvivesTheSpreadsheetRoundTrip() throws {
    let original = SampleLifeline.make(now: Fixture.date(2026, 9, 10), calendar: Fixture.calendar)
    let back = try document.lifeline(fromCSV: document.csv(for: original))

    #expect(back.events.count == original.events.count)
    for (before, after) in zip(original.events, back.events) {
        #expect(before.id == after.id)
        #expect(before.title == after.title)
        #expect(before.category == after.category)
        #expect(before.weight == after.weight)
        #expect(before.note == after.note)
        #expect(before.duration == after.duration)
        #expect(abs(before.start.timeIntervalSince(after.start)) < 60)
    }
}

@Test func theHeaderNamesTheColumnsAndOrderDoesNotMatter() throws {
    let lifeline = try document.lifeline(fromCSV: """
    category,start,title,weight
    travel,2016-04-02,Japan,notable
    life,1985-06-14 04:12,Born,milestone
    """)
    // Sorted by date on the way in, whatever order the rows were in.
    #expect(lifeline.events.map(\.title) == ["Born", "Japan"])
    #expect(lifeline.events[0].weight == .milestone)
    #expect(lifeline.events[1].category == .travel)
}

@Test func twoColumnsIsEnoughToStartWith() throws {
    let lifeline = try document.lifeline(fromCSV: """
    title,start
    Started school,1992-08-17
    Moved to the coast,1996-07-01
    """)
    #expect(lifeline.events.count == 2)
    #expect(lifeline.events[0].start == Fixture.date(1992, 8, 17))
    #expect(lifeline.events[0].weight == .worthRemembering)
}

@Test func columnsCanBeCalledWhatASpreadsheetWouldCallThem() throws {
    let lifeline = try document.lifeline(fromCSV: """
    What,When,How long,How big,Notes
    Japan,2016-04-02,16 days,notable,Tokyo and Kyoto
    """)
    let japan = lifeline.events[0]
    #expect(japan.title == "Japan")
    #expect(japan.duration == 16 * 86400.0)
    #expect(japan.weight == .notable)
    #expect(japan.note == "Tokyo and Kyoto")
}

@Test func whateverTheProgramUsedAsASeparator() throws {
    // Excel on a Swedish machine writes semicolons.
    let semicolons = try document.lifeline(fromCSV: """
    title;start;weight
    Born;1985-06-14;milestone
    """)
    #expect(semicolons.events[0].title == "Born")

    let tabs = try document.lifeline(fromCSV: "title\tstart\nBorn\t1985-06-14")
    #expect(tabs.events[0].title == "Born")

    // And Excel's own announcement of it.
    let declared = try document.lifeline(fromCSV: "sep=;\r\ntitle;start\r\nBorn;1985-06-14\r\n")
    #expect(declared.events[0].title == "Born")
}

@Test func windowsLineEndingsAndAByteOrderMark() throws {
    let lifeline = try document.lifeline(fromCSV: "\u{FEFF}title,start\r\nBorn,1985-06-14\r\nSchool,1992-08-17\r\n")
    #expect(lifeline.events.map(\.title) == ["Born", "School"])
}

@Test func quotedFieldsCarryCommasQuotesAndNewlines() throws {
    let lifeline = try document.lifeline(fromCSV: """
    title,start,note
    "The ""good"" flat",2013-05-01,"Line one.
    Line two, with a comma."
    """)
    #expect(lifeline.events[0].title == "The \"good\" flat")
    #expect(lifeline.events[0].note == "Line one.\nLine two, with a comma.")
}

@Test func awkwardTextComesBackOutQuotedProperly() throws {
    let awkward = Lifeline(events: [
        Event(title: "Lunch, then a walk", start: Fixture.date(2026, 9, 10, 12),
              note: "She said \"maybe\".\nThen nothing."),
        Event(title: "Semi;colon", start: Fixture.date(2026, 9, 11)),
    ])
    let back = try document.lifeline(fromCSV: document.csv(for: awkward))
    #expect(back.events[0].title == "Lunch, then a walk")
    #expect(back.events[0].note == "She said \"maybe\".\nThen nothing.")
    // Quoted even though a comma file would not need it, so re-saving with
    // semicolons cannot split the field.
    #expect(document.csv(for: awkward).contains("\"Semi;colon\""))
}

@Test func blankRowsAreSkippedRatherThanRefused() throws {
    let lifeline = try document.lifeline(fromCSV: """
    title,start

    Born,1985-06-14

    School,1992-08-17
    """)
    #expect(lifeline.events.count == 2)
}

@Test func mistakesPointAtTheSpreadsheetRow() {
    func failure(_ text: String) -> LifelineDocumentError? {
        do { _ = try document.lifeline(fromCSV: text); return nil }
        catch let error as LifelineDocumentError { return error }
        catch { return nil }
    }

    #expect(failure("first name,age\nDaniel,41") == .missingColumns)
    #expect(failure("title,start\n") == .noEvents)

    // Header is row 1, so the second event is row 3 - what the spreadsheet
    // shows down its left edge.
    #expect(failure("""
    title,start
    Born,1985-06-14
    School,14 juni 1992
    """) == .badDate(at: .row(3), title: "School", value: "14 juni 1992"))

    let message = LifelineDocumentError
        .badDate(at: .row(3), title: "School", value: "14 juni 1992").errorDescription ?? ""
    #expect(message.contains("row 3"))
    #expect(!message.contains("event 3"))
}

@Test func oneOpenFileButtonTakesEitherKind() throws {
    let lifeline = Lifeline(events: [
        Event(title: "Born", start: Fixture.date(1985, 6, 14, 4, 12),
              category: .life, weight: .milestone)
    ])
    // The routing is on content, not on the file extension.
    #expect(try document.lifeline(from: document.csv(for: lifeline)).events.count == 1)
    #expect(try document.lifeline(from: document.text(for: lifeline)).events.count == 1)
    #expect(try document.lifeline(from: "  \n [ {\"title\":\"a\",\"start\":\"2020-01-01\"} ]").events.count == 1)
}
