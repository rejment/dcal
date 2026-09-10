// The three decisions that make a zoomable timeline readable, kept apart
// from any drawing so they can be tested directly.

import CoreGraphics
import Foundation

public enum Layout {
    /// Side-by-side lanes for things happening at once, the way any calendar
    /// day view works - but computed per cluster of genuinely overlapping
    /// spans, so a busy Tuesday morning does not squeeze a lone Friday
    /// afternoon into a narrow column too.
    public static func packLanes(_ spans: [ClosedRange<CGFloat>]) -> [(lane: Int, lanes: Int)] {
        var result = [(lane: Int, lanes: Int)](repeating: (lane: 0, lanes: 1), count: spans.count)
        let order = spans.indices.sorted { left, right in
            spans[left].lowerBound == spans[right].lowerBound
                ? spans[left].upperBound > spans[right].upperBound
                : spans[left].lowerBound < spans[right].lowerBound
        }

        var cluster: [Int] = []
        var clusterEnd = -CGFloat.greatestFiniteMagnitude

        func flush() {
            guard !cluster.isEmpty else { return }
            var laneEnds: [CGFloat] = []
            for index in cluster {
                var lane = 0
                while lane < laneEnds.count, laneEnds[lane] > spans[index].lowerBound + 0.5 {
                    lane += 1
                }
                if lane == laneEnds.count { laneEnds.append(0) }
                laneEnds[lane] = spans[index].upperBound
                result[index].lane = lane
            }
            for index in cluster { result[index].lanes = laneEnds.count }
            cluster.removeAll()
            clusterEnd = -CGFloat.greatestFiniteMagnitude
        }

        for index in order {
            if !cluster.isEmpty, spans[index].lowerBound >= clusterEnd - 0.5 { flush() }
            cluster.append(index)
            clusterEnd = max(clusterEnd, spans[index].upperBound)
        }
        flush()
        return result
    }

    /// How important a thing has to be to still carry its name at this zoom.
    /// This is the map-label rule: street names vanish before town names,
    /// town names before countries.
    public static func minimumWeight(forSpan span: TimeInterval) -> Weight {
        let day: TimeInterval = 86400
        let year: TimeInterval = 31_556_952
        if span <= 5 * day { return .everyday }
        if span <= 50 * day { return .worthRemembering }
        if span <= 4 * year { return .notable }
        return .milestone
    }

    public struct LabelCandidate: Sendable {
        public let index: Int
        public let y: CGFloat
        public let weight: Weight

        public init(index: Int, y: CGFloat, weight: Weight) {
            self.index = index
            self.y = y
            self.weight = weight
        }
    }

    /// Greedy placement: heaviest first, and among equals whichever comes
    /// first in the list, which the caller keeps in chronological order.
    /// Anything that would collide is dropped rather than nudged - a label
    /// that has moved is a label pointing at the wrong moment.
    ///
    /// The tie-break must not depend on the viewport. It used to prefer
    /// whatever was nearest the middle of the screen, which sounds right and
    /// is not: two neighbours competing for one slot then swap winners as you
    /// scroll past them, and a label blinks out while another appears beside
    /// it. Ordering by time instead makes the outcome for any pair fixed, so
    /// panning at a given zoom cannot change what is on screen.
    ///
    /// Sorting has to be made stable by hand - Swift's sort is not - or equal
    /// weights would shuffle among themselves for the same reason.
    public static func placeLabels(
        _ candidates: [LabelCandidate],
        gap: (Weight) -> CGFloat,
        limit: Int = 120
    ) -> [Int] {
        let ordered = candidates.enumerated().sorted { left, right in
            left.element.weight == right.element.weight
                ? left.offset < right.offset
                : left.element.weight > right.element.weight
        }.map(\.element)
        var taken: [CGFloat] = []
        var placed: [Int] = []
        for candidate in ordered {
            guard placed.count < limit else { break }
            let needed = gap(candidate.weight)
            if taken.contains(where: { abs($0 - candidate.y) < needed }) { continue }
            taken.append(candidate.y)
            placed.append(candidate.index)
        }
        return placed
    }
}
