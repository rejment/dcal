// Does the scan find the days that mattered, and leave the rest alone?

import Foundation
import Testing
@testable import DcalKit

private let stockholm = Coordinate(latitude: 59.33, longitude: 18.07)
private let gotland = Coordinate(latitude: 57.64, longitude: 18.30)
private let kyoto = Coordinate(latitude: 35.01, longitude: 135.77)

private func moments(
    day: Date,
    count: Int,
    at place: Coordinate? = stockholm,
    favourites: Int = 0
) -> [PhotoMoment] {
    (0..<count).map { index in
        PhotoMoment(
            date: day.addingTimeInterval(Double(index) * 600 + 36000),
            coordinate: place,
            isFavourite: index < favourites
        )
    }
}

/// An ordinary year: two or three photos on most days, at home.
private func ordinaryYear(_ year: Int) -> [PhotoMoment] {
    var out: [PhotoMoment] = []
    for dayOfYear in stride(from: 1, through: 360, by: 2) {
        let day = Fixture.date(year, 1, 1).addingTimeInterval(Double(dayOfYear) * 86400)
        out += moments(day: Fixture.calendar.startOfDay(for: day), count: 2)
    }
    return out
}

@Test func anOrdinaryYearHasNothingWorthReporting() {
    let found = PhotoScan.findings(in: ordinaryYear(2020), calendar: Fixture.calendar)
    #expect(found.isEmpty)
}

@Test func aTripBecomesOneEventNotTwelve() {
    var library = ordinaryYear(2016)
    // Twelve days in Kyoto, photographed the way people photograph trips.
    for offset in 0..<12 {
        let day = Fixture.date(2016, 4, 2).addingTimeInterval(Double(offset) * 86400)
        library += moments(day: day, count: 25, at: kyoto)
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    let trips = found.filter(\.isTrip)

    #expect(trips.count == 1)
    let trip = trips[0]
    #expect(trip.start == Fixture.date(2016, 4, 2))
    #expect(trip.dayCount == 12)
    // At least the trip's own photos. More, in fact: the ordinary days that
    // fall inside the span count too, the way the morning you flew out has
    // pictures of your own kitchen in it.
    #expect(trip.photoCount >= 12 * 25)
    #expect(trip.reasons.contains(.away))
    #expect(trip.suggestedCategory == .travel)
    #expect(trip.suggestedWeight == .notable)
    // Twelve days becomes a block on the timeline, not a dot.
    #expect(trip.proposedEvent(title: "Japan").duration == 12 * 86400)
}

@Test func aGapOfADayInsideATripDoesNotSplitIt() {
    var library = ordinaryYear(2021)
    // Photographed on days 1, 2, then nothing, then 5, 6 - still one holiday.
    for offset in [0, 1, 4, 5] {
        let day = Fixture.date(2021, 7, 3).addingTimeInterval(Double(offset) * 86400)
        library += moments(day: day, count: 15, at: gotland)
    }
    let trips = PhotoScan.findings(in: library, calendar: Fixture.calendar).filter(\.isTrip)
    #expect(trips.count == 1)
    #expect(trips[0].dayCount == 6)
}

@Test func aBigDayAtHomeIsFoundWithoutGoingAnywhere() {
    var library = ordinaryYear(2018)
    library += moments(day: Fixture.date(2018, 10, 6), count: 60)

    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    let party = found.first { $0.start == Fixture.date(2018, 10, 6) }
    #expect(party != nil)
    #expect(party?.reasons.contains(.busy) == true)
    #expect(party?.reasons.contains(.away) == false)
    #expect(party?.suggestedCategory == .people)
}

@Test func heartedPhotosMarkTheirDay() {
    var library = ordinaryYear(2019)
    library += moments(day: Fixture.date(2019, 3, 14), count: 4, favourites: 3)

    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    let hearted = found.first { $0.start == Fixture.date(2019, 3, 14) }
    #expect(hearted?.reasons.contains(.favourite) == true)
    #expect(hearted?.favouriteCount == 3)
    // One heart is not a signal; two is.
    #expect(!found.contains { $0.favouriteCount == 1 })
}

@Test func comingBackAfterMonthsOfNothingCounts() {
    var library = moments(day: Fixture.date(2022, 1, 10), count: 3)
    library += moments(day: Fixture.date(2022, 6, 1), count: 6)

    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    let returning = found.first { $0.start == Fixture.date(2022, 6, 1) }
    #expect(returning?.reasons.contains(.afterQuiet) == true)
}

@Test func movingHouseIsNotATripForever() {
    // Two years in Stockholm, then two on Gotland. The second pair is home,
    // not a two-year holiday.
    var library: [PhotoMoment] = []
    for year in [2014, 2015] {
        for dayOfYear in stride(from: 1, through: 350, by: 3) {
            let day = Fixture.calendar.startOfDay(
                for: Fixture.date(year, 1, 1).addingTimeInterval(Double(dayOfYear) * 86400))
            library += moments(day: day, count: 2, at: stockholm)
        }
    }
    for year in [2016, 2017] {
        for dayOfYear in stride(from: 1, through: 350, by: 3) {
            let day = Fixture.calendar.startOfDay(
                for: Fixture.date(year, 1, 1).addingTimeInterval(Double(dayOfYear) * 86400))
            library += moments(day: day, count: 2, at: gotland)
        }
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    #expect(found.filter(\.isTrip).isEmpty)
    #expect(found.isEmpty)
}

@Test func homeIsWhereTheDaysAreNotWhereThePhotosAre() {
    // Three weeks abroad can easily out-shoot a whole year at home, so the
    // cluster has to be counted in days rather than in photographs.
    var everyday = (0..<200).map { _ in stockholm }
    everyday += (0..<800).map { _ in kyoto }
    // Even with four times as many Kyoto points, a single cluster wins on
    // count - so this checks the caller's job, feeding it one point per day.
    #expect(PhotoScan.homeCluster(of: everyday) != nil)

    let byDay = Array(repeating: stockholm, count: 200) + Array(repeating: kyoto, count: 21)
    let home = PhotoScan.homeCluster(of: byDay)
    #expect(home?.distance(to: stockholm) ?? .infinity < 30_000)
}

@Test func distancesAreRoughlyRight() {
    // Stockholm to Kyoto is about 8,000 km; to Gotland about 200.
    #expect(abs(stockholm.distance(to: kyoto) / 1000 - 8_000) < 500)
    #expect(abs(stockholm.distance(to: gotland) / 1000 - 210) < 60)
    #expect(stockholm.distance(to: stockholm) == 0)
}

@Test func theBusiestThingsComeOutOnTop() {
    var library = ordinaryYear(2023)
    library += moments(day: Fixture.date(2023, 5, 2), count: 20)
    for offset in 0..<9 {
        let day = Fixture.date(2023, 11, 18).addingTimeInterval(Double(offset) * 86400)
        library += moments(day: day, count: 30, at: kyoto)
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    #expect(found.count >= 2)
    // Returned in date order for reading, but the trip scores highest.
    #expect(found.map(\.start) == found.map(\.start).sorted())
    #expect(found.max { $0.score < $1.score }?.isTrip == true)
}

@Test func anEmptyLibraryIsNotAnError() {
    #expect(PhotoScan.findings(in: [], calendar: Fixture.calendar).isEmpty)
    #expect(PhotoScan.findings(
        in: [PhotoMoment(date: Fixture.date(2020, 1, 1))], calendar: Fixture.calendar
    ).isEmpty)
}

// MARK: - Not drowning the reader

/// What a phone actually produces: a handful of photos most days for years.
private func phoneLibrary(years: ClosedRange<Int>) -> [PhotoMoment] {
    var out: [PhotoMoment] = []
    for year in years {
        for dayOfYear in 0..<360 {
            let day = Fixture.calendar.startOfDay(
                for: Fixture.date(year, 1, 1).addingTimeInterval(Double(dayOfYear) * 86400))
            // Three or four on a normal day, which is what caught a quarter of
            // every year when "busy" meant three times the median.
            out += moments(day: day, count: 3 + (dayOfYear % 2))
        }
    }
    return out
}

@Test func anOrdinaryPhoneLibraryDoesNotFillTheList() {
    let found = PhotoScan.findings(in: phoneLibrary(years: 2015...2020), calendar: Fixture.calendar)
    // Six years of daily photographs, nothing unusual in them. The first
    // version reported hundreds of these.
    #expect(found.count < 10)
}

@Test func theRealThingsStillSurfaceOutOfAllThatNoise() {
    var library = phoneLibrary(years: 2015...2020)
    // A wedding at home, and two weeks away.
    library += moments(day: Fixture.date(2017, 6, 24), count: 90)
    for offset in 0..<14 {
        let day = Fixture.date(2019, 8, 3).addingTimeInterval(Double(offset) * 86400)
        library += moments(day: day, count: 40, at: kyoto)
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)

    #expect(found.contains { $0.start == Fixture.date(2017, 6, 24) })
    #expect(found.contains { $0.isTrip && $0.dayCount == 14 })
    // And the trip outranks the wedding, which outranks everything else.
    #expect(found.max { $0.score < $1.score }?.isTrip == true)
}

@Test func aLongHolidayDoesNotHideAWeddingAtHome() {
    // Days away are excluded from the baseline. Left in, a fortnight of heavy
    // holiday photography raises the bar above the wedding.
    var library = phoneLibrary(years: 2019...2019)
    library += moments(day: Fixture.date(2019, 6, 24), count: 45)
    for offset in 0..<14 {
        let day = Fixture.date(2019, 8, 3).addingTimeInterval(Double(offset) * 86400)
        library += moments(day: day, count: 120, at: kyoto)
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    #expect(found.contains { $0.start == Fixture.date(2019, 6, 24) })
}

@Test func howMuchToShowIsTheReadersChoice() {
    var library = phoneLibrary(years: 2010...2020)
    for year in 2010...2020 {
        for month in [3, 7, 11] {
            for offset in 0..<6 {
                let day = Fixture.date(year, month, 1).addingTimeInterval(Double(offset) * 86400)
                library += moments(day: day, count: 30, at: kyoto)
            }
        }
    }
    let all = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    #expect(all.count > 20)

    let big = PhotoScan.top(all, .highlights)
    let fair = PhotoScan.top(all, .balanced)
    #expect(big.count <= 40)
    #expect(fair.count >= big.count)
    // Narrowing keeps the best, and everything stays in date order to read.
    #expect(big.map(\.start) == big.map(\.start).sorted())
    let bestScore = all.map(\.score).max() ?? 0
    #expect(big.contains { $0.score == bestScore })
}

@Test func theSamplePhotosLeanOnTheOnesYouHearted() {
    let samples =
        (0..<20).map { (id: "plain-\($0)", favourite: false) }
        + [(id: "hearted-a", favourite: true), (id: "hearted-b", favourite: true)]

    let picked = PhotoScan.representatives(of: samples)
    #expect(picked.count == 4)
    #expect(picked.prefix(2) == ["hearted-a", "hearted-b"])
    // The rest spread across the day rather than the first two of the morning.
    #expect(picked[2] != "plain-1")
    #expect(Set(picked).count == 4)
}

@Test func aDayCarriesPhotosToLookAt() {
    var library = ordinaryYear(2024)
    let day = Fixture.date(2024, 5, 18)
    library += (0..<40).map { index in
        PhotoMoment(
            date: day.addingTimeInterval(Double(index) * 600 + 36000),
            coordinate: stockholm,
            isFavourite: index < 2,
            identifier: "asset-\(index)"
        )
    }
    let found = PhotoScan.findings(in: library, calendar: Fixture.calendar)
    let busy = found.first { $0.start == day }
    #expect(busy?.sampleIdentifiers.isEmpty == false)
    #expect(busy?.sampleIdentifiers.count ?? 0 <= 4)
}
