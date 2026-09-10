// How photographed each stretch of life was, ready to paint.
//
// The ribbon already carries two things: the colour of the time, and a
// coloured notch for everything you have recorded. This is a third, and it
// uses the one channel left - brightness. Where you took photographs the
// column glows; where you took none it stays dark. The empty years become
// visible without anyone having to write anything down.
//
// Counts per day and nothing else, so a whole life is a few tens of
// kilobytes and can sit on disk between launches. No coordinates, no
// identifiers, nothing that says what any photograph was of.

import CoreGraphics
import Foundation

public struct PhotoDensity: Codable, Equatable, Sendable {
    /// Days since 1970, and how many photos fell on each. Sorted.
    public let days: [Int]
    public let counts: [Int]
    /// What a well-photographed day looks like for this person. Everything is
    /// measured against it, so the glow means the same thing at every zoom
    /// and does not rescale as you pan.
    public let reference: Double
    public let built: Date

    public init(days: [Int], counts: [Int], reference: Double, built: Date = Date()) {
        self.days = days
        self.counts = counts
        self.reference = max(1, reference)
        self.built = built
    }

    public init(moments: [PhotoMoment], calendar: Calendar, now: Date = Date()) {
        var tally: [Int: Int] = [:]
        for moment in moments {
            let day = Int(calendar.startOfDay(for: moment.date).timeIntervalSince1970 / 86400)
            tally[day, default: 0] += 1
        }
        let ordered = tally.keys.sorted()
        days = ordered
        counts = ordered.map { tally[$0] ?? 0 }
        // The 80th percentile of the days you photographed at all: high enough
        // that ordinary days do not saturate, low enough that the glow is not
        // reserved for weddings.
        let sorted = counts.map(Double.init).sorted()
        reference = max(1, percentile(sorted, 0.8))
        built = now
    }

    public var isEmpty: Bool { days.isEmpty }

    public var span: ClosedRange<Date>? {
        guard let first = days.first, let last = days.last else { return nil }
        let from = Date(timeIntervalSince1970: Double(first) * 86400)
        let to = Date(timeIntervalSince1970: Double(last) * 86400)
        return from...to
    }

    /// One value per bucket down the view, 0 to 1, where 1 is "as
    /// photographed as a good day".
    ///
    /// A day may be thinner than a bucket or taller than the screen depending
    /// on the zoom, so it is spread across whatever it covers rather than
    /// dropped into one slot - otherwise a day view would show a single hard
    /// line and a lifetime would show nothing at all.
    public func profile(scale: TimeScale, bucketPoints: CGFloat = 2) -> [Double] {
        let bucketCount = max(1, Int((scale.height / bucketPoints).rounded(.up)))
        guard !days.isEmpty else { return Array(repeating: 0, count: bucketCount) }

        var photos = [Double](repeating: 0, count: bucketCount)
        var covered = [Double](repeating: 0, count: bucketCount)

        let topDay = Int(scale.top.timeIntervalSince1970 / 86400) - 1
        let bottomDay = Int(scale.bottom.timeIntervalSince1970 / 86400) + 1
        var index = lowerBound(of: topDay)

        let pointsPerDay = scale.points(for: 86400)
        while index < days.count, days[index] <= bottomDay {
            defer { index += 1 }
            let start = Double(days[index]) * 86400
            let y0 = scale.y(for: Date(timeIntervalSince1970: start))
            let y1 = y0 + CGFloat(pointsPerDay)
            let count = Double(counts[index])

            let first = Int(floor(y0 / bucketPoints))
            let last = Int(floor((y1 - 0.001) / bucketPoints))
            if last < 0 || first >= bucketCount { continue }

            let touched = max(1, last - first + 1)
            let share = count / Double(touched)
            for bucket in max(0, first)...min(bucketCount - 1, max(0, last)) {
                photos[bucket] += share
                covered[bucket] += 1.0 / Double(touched)
            }
        }

        // How many days' worth of time each bucket holds, so a bucket
        // covering a fortnight is judged against a fortnight of good days.
        let daysPerBucket = max(Double(bucketPoints) / max(pointsPerDay, 0.0001), 0.0001)
        return (0..<bucketCount).map { bucket in
            guard photos[bucket] > 0 else { return 0 }
            let expected = max(covered[bucket], min(daysPerBucket, 1)) * reference
            return Curve.clamp(photos[bucket] / max(expected, 0.0001), 0, 1)
        }
    }

    private func lowerBound(of day: Int) -> Int {
        var low = 0
        var high = days.count
        while low < high {
            let middle = (low + high) / 2
            if days[middle] < day { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// Kept beside the lifeline, and rebuilt rather than migrated - it is a
/// cache of the photo library, never a source of truth.
public struct PhotoDensityStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return directory.appendingPathComponent("dcal-photo-density.json")
    }

    public func load() -> PhotoDensity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PhotoDensity.self, from: data)
    }

    public func save(_ density: PhotoDensity) {
        guard let data = try? JSONEncoder().encode(density) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
