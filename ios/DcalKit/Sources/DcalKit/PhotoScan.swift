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
    /// The library's own id, so a thumbnail can be fetched later. Still no
    /// image data here - this is a string, not a picture.
    public let identifier: String?

    public init(
        date: Date,
        coordinate: Coordinate? = nil,
        isFavourite: Bool = false,
        identifier: String? = nil
    ) {
        self.date = date
        self.coordinate = coordinate
        self.isFavourite = isFavourite
        self.identifier = identifier
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
    /// A few photos that stand for the day, hearted ones first. Without these
    /// the list asks you to judge "40 photos, a Tuesday in 2011" from nothing.
    public let sampleIdentifiers: [String]
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
    /// How much of a life to pull out. The signals cannot tell a wedding from
    /// a wet Tuesday, so rather than pretend a threshold is objective, this
    /// ranks everything and lets the reader say how far down to go.
    public enum Sensitivity: String, CaseIterable, Sendable, Identifiable {
        case highlights, balanced, everything

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .highlights: "The big things"
            case .balanced: "A fair amount"
            case .everything: "Everything"
            }
        }

        public var limit: Int {
            switch self {
            case .highlights: 40
            case .balanced: 150
            case .everything: 600
            }
        }
    }

    /// The highest scoring findings, back in date order for reading.
    public static func top(_ findings: [PhotoFinding], _ sensitivity: Sensitivity) -> [PhotoFinding] {
        Array(findings.sorted { $0.score > $1.score }.prefix(sensitivity.limit))
            .sorted { $0.start < $1.start }
    }

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
            var samples: [(id: String, favourite: Bool)] = []

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
            if let id = moment.identifier, day.samples.count < 12 {
                day.samples.append((id: id, favourite: moment.isFavourite))
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

        // --- which days were spent somewhere else ---
        var awayDays: Set<Date> = []
        for day in days {
            let year = calendar.component(.year, from: day.date)
            if let here = day.coordinate, let base = home(inYear: year),
               here.distance(to: base) > awayMetres {
                awayDays.insert(day.date)
            }
        }

        // --- how many photos a normal day at home holds, for this person ---
        // Days away are left out of this on purpose. They are already their
        // own signal, and counting them here lets one long holiday raise the
        // bar so far that a wedding at home no longer clears it.
        //
        // Times five and never fewer than a dozen. Times three caught a
        // quarter of every year on a phone that takes three photos on an
        // ordinary day, which is how the first version found four hundred
        // "interesting" days and told you nothing.
        let homeCounts = days
            .filter { !awayDays.contains($0.date) }
            .map { Double($0.count) }
            .sorted()
        let baseline = max(12.0, median(homeCounts) * 5, percentile(homeCounts, 0.97))

        // --- classify each day ---
        var reasonsByDay: [Date: Set<PhotoFinding.Reason>] = [:]
        var previous: Date?
        for day in days {
            var reasons: Set<PhotoFinding.Reason> = []

            if awayDays.contains(day.date) {
                reasons.insert(.away)
            }
            if Double(day.count) >= baseline {
                reasons.insert(.busy)
            }
            // Three, not two. Two hearts on a day is a nice pair of photos.
            if day.favourites >= 3 {
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
                sampleIdentifiers: representatives(of: members.flatMap(\.samples)),
                score: score(reasons: reasons, days: spanDays, photos: photos,
                             favourites: favourites, baseline: baseline)
            ))
        }

        return Array(findings.sorted { $0.score > $1.score }.prefix(limit))
            .sorted { $0.start < $1.start }
    }

    /// Hearted first, then spread across the span rather than the first four
    /// of the first morning.
    static func representatives(of samples: [(id: String, favourite: Bool)], count: Int = 4) -> [String] {
        let hearted = samples.filter(\.favourite).map(\.id)
        var chosen = Array(hearted.prefix(count))
        guard chosen.count < count else { return chosen }

        let rest = samples.map(\.id).filter { !chosen.contains($0) }
        guard !rest.isEmpty else { return chosen }
        let wanted = count - chosen.count
        let step = max(1, rest.count / wanted)
        for index in stride(from: 0, to: rest.count, by: step) where chosen.count < count {
            chosen.append(rest[index])
        }
        return chosen
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

func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int((Double(sorted.count - 1) * fraction).rounded())
    return sorted[max(0, min(sorted.count - 1, index))]
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 0
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle]
}
