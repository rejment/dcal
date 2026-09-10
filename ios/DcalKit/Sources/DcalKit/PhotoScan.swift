// Finding the days that mattered, from the record you already keep.
//
// A photo library is a life with timestamps on it. This reads only the
// metadata - when, where, and whether you hearted it - and never the pixels,
// so nothing has to be recognised, uploaded or understood to work out that
// something happened on a particular Tuesday.
//
// Four signals, because no single one is enough:
//
//   away         photos a long way from where you usually were that year,
//                with consecutive days merged into one trip. The strongest,
//                and the only one that can carry a real name.
//   busy         far more photos than a normal day for you. Parties,
//                weddings, births - photographed heavily, standing still.
//   favourite    days holding photos you hearted. Rare, and you already
//                decided they mattered.
//   after quiet  the first photos in months, which tends to mark something
//                changing rather than something happening.
//
// Nothing here proposes a title. A day with forty photos was a birthday or a
// burst pipe and only the person who was there knows which - so this ranks
// and describes, and the choosing happens on screen.

import Foundation

public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Metres, on a sphere. Good to a fraction of a percent, which is far
    /// more than "is this the same town" needs.
    public func distance(to other: Coordinate) -> Double {
        let earth = 6_371_000.0
        let phi1 = latitude * .pi / 180
        let phi2 = other.latitude * .pi / 180
        let dPhi = (other.latitude - latitude) * .pi / 180
        let dLambda = (other.longitude - longitude) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// One photo, reduced to the three things this needs.
public struct PhotoMoment: Equatable, Sendable {
    public let date: Date
    public let coordinate: Coordinate?
    public let isFavourite: Bool

    public init(date: Date, coordinate: Coordinate? = nil, isFavourite: Bool = false) {
        self.date = date
        self.coordinate = coordinate
        self.isFavourite = isFavourite
    }
}

public struct PhotoFinding: Identifiable, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable, CaseIterable {
        case away, busy, favourite, afterQuiet

        public var label: String {
            switch self {
            case .away: "Away from home"
            case .busy: "A lot of photos"
            case .favourite: "Photos you hearted"
            case .afterQuiet: "First in a long while"
            }
        }
    }

    public let id: String
    public let start: Date
    /// The last day with photos in it, not an exclusive end.
    public let lastDay: Date
    public let dayCount: Int
    public let photoCount: Int
    public let favouriteCount: Int
    public let reasons: [Reason]
    public let coordinate: Coordinate?
    public let score: Double

    public var isTrip: Bool { reasons.contains(.away) && dayCount > 1 }

    /// The whole span, so a trip becomes one block rather than a row of dots.
    public var duration: TimeInterval {
        max(0, lastDay.timeIntervalSince(start) + 86400)
    }

    public var suggestedCategory: Category {
        reasons.contains(.away) ? .travel : .people
    }

    public var suggestedWeight: Weight {
        isTrip || score >= 3 ? .notable : .worthRemembering
    }

    public func proposedEvent(title: String) -> Event {
        Event(
            title: title,
            start: start,
            duration: dayCount > 1 ? duration : 0,
            category: suggestedCategory,
            weight: suggestedWeight,
            note: ""
        )
    }
}

public enum PhotoScan {
    /// Far enough that you went somewhere, rather than across town.
    public static let awayMetres = 100_000.0
    /// Days with no photos between two away days still belong to the trip.
    public static let tripGapDays = 3
    /// A quiet stretch long enough that coming out of it means something.
    public static let quietDays = 60

    public static func findings(
        in moments: [PhotoMoment],
        calendar: Calendar,
        limit: Int = 400
    ) -> [PhotoFinding] {
        guard !moments.isEmpty else { return [] }

        // --- one bucket per local day ---
        struct Day {
            var date: Date
            var count = 0
            var favourites = 0
            var latitudes: [Double] = []
            var longitudes: [Double] = []

            var coordinate: Coordinate? {
                guard !latitudes.isEmpty else { return nil }
                return Coordinate(
                    latitude: median(latitudes),
                    longitude: median(longitudes)
                )
            }
        }

        var byDay: [Date: Day] = [:]
        for moment in moments {
            let key = calendar.startOfDay(for: moment.date)
            var day = byDay[key] ?? Day(date: key)
            day.count += 1
            if moment.isFavourite { day.favourites += 1 }
            if let where_ = moment.coordinate {
                day.latitudes.append(where_.latitude)
                day.longitudes.append(where_.longitude)
            }
            byDay[key] = day
        }
        let days = byDay.values.sorted { $0.date < $1.date }
        guard !days.isEmpty else { return [] }

        // --- where you lived, year by year, so moving house is not a trip ---
        var homes: [Int: Coordinate] = [:]
        var byYear: [Int: [Day]] = [:]
        for day in days {
            byYear[calendar.component(.year, from: day.date), default: []].append(day)
        }
        for (year, group) in byYear {
            if let base = homeCluster(of: group.compactMap(\.coordinate)) { homes[year] = base }
        }
        func home(inYear year: Int) -> Coordinate? {
            if let exact = homes[year] { return exact }
            // Nearest year that knows, so a gap in the record does not turn
            // everything after it into a trip.
            return homes
                .min { abs($0.key - year) < abs($1.key - year) }?
                .value
        }

        // --- how many photos a normal day holds, for this person ---
        let baseline = max(3.0, median(days.map { Double($0.count) }) * 3)

        // --- classify each day ---
        var reasonsByDay: [Date: Set<PhotoFinding.Reason>] = [:]
        var previous: Date?
        for day in days {
            var reasons: Set<PhotoFinding.Reason> = []

            let year = calendar.component(.year, from: day.date)
            if let here = day.coordinate, let base = home(inYear: year),
               here.distance(to: base) > awayMetres {
                reasons.insert(.away)
            }
            if Double(day.count) >= max(8, baseline) {
                reasons.insert(.busy)
            }
            if day.favourites >= 2 {
                reasons.insert(.favourite)
            }
            if let previous,
               let gap = calendar.dateComponents([.day], from: previous, to: day.date).day,
               gap >= quietDays, day.count >= 3 {
                reasons.insert(.afterQuiet)
            }
            previous = day.date
            if !reasons.isEmpty { reasonsByDay[day.date] = reasons }
        }

        // --- consecutive away days are one trip ---
        var findings: [PhotoFinding] = []
        var index = 0
        let interesting = days.filter { reasonsByDay[$0.date] != nil }
        while index < interesting.count {
            let first = interesting[index]
            var last = first
            var members = [first]

            if reasonsByDay[first.date]?.contains(.away) == true {
                var next = index + 1
                while next < interesting.count,
                      reasonsByDay[interesting[next].date]?.contains(.away) == true,
                      let gap = calendar.dateComponents(
                          [.day], from: last.date, to: interesting[next].date
                      ).day,
                      gap <= tripGapDays {
                    last = interesting[next]
                    members.append(last)
                    next += 1
                }
                index = next
            } else {
                index += 1
            }

            let reasons = members.reduce(into: Set<PhotoFinding.Reason>()) {
                $0.formUnion(reasonsByDay[$1.date] ?? [])
            }
            let photos = members.reduce(0) { $0 + $1.count }
            let favourites = members.reduce(0) { $0 + $1.favourites }
            let spanDays = (calendar.dateComponents(
                [.day], from: first.date, to: last.date
            ).day ?? 0) + 1

            findings.append(PhotoFinding(
                id: ISO8601DateFormatter.salvageStamp.string(from: first.date) + "+\(spanDays)",
                start: first.date,
                lastDay: last.date,
                dayCount: spanDays,
                photoCount: photos,
                favouriteCount: favourites,
                reasons: PhotoFinding.Reason.allCases.filter { reasons.contains($0) },
                coordinate: members.compactMap(\.coordinate).first,
                score: score(reasons: reasons, days: spanDays, photos: photos,
                             favourites: favourites, baseline: baseline)
            ))
        }

        return Array(
            findings
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
        .sorted { $0.start < $1.start }
    }

    static func score(
        reasons: Set<PhotoFinding.Reason>,
        days: Int,
        photos: Int,
        favourites: Int,
        baseline: Double
    ) -> Double {
        var total = 0.0
        if reasons.contains(.away) { total += 3 + min(Double(days) / 4, 3) }
        if reasons.contains(.busy) { total += min(Double(photos) / baseline, 4) }
        if reasons.contains(.favourite) { total += min(Double(favourites), 3) }
        if reasons.contains(.afterQuiet) { total += 1.5 }
        return total
    }

    /// Where the most *days* were spent, not the most photos - three weeks in
    /// Japan can easily out-shoot a year at home.
    static func homeCluster(of coordinates: [Coordinate]) -> Coordinate? {
        guard !coordinates.isEmpty else { return nil }
        // Quarter of a degree is roughly 25km: the same town, near enough.
        var cells: [String: [Coordinate]] = [:]
        for point in coordinates {
            let key = "\(Int((point.latitude * 4).rounded()))/\(Int((point.longitude * 4).rounded()))"
            cells[key, default: []].append(point)
        }
        guard let biggest = cells.values.max(by: { $0.count < $1.count }) else { return nil }
        return Coordinate(
            latitude: median(biggest.map(\.latitude)),
            longitude: median(biggest.map(\.longitude))
        )
    }
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 0
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}
