// Where you are looking, in two numbers.
//
// Everything on screen is a function of these: a centre instant and how many
// points one second occupies. Zooming keeps the instant under your fingers
// fixed, which is the whole trick to a pinch that feels attached to the
// timeline rather than to the screen.

import CoreGraphics
import Foundation

public struct TimeScale: Equatable, Sendable {
    /// The instant at the vertical middle of the view.
    public var centre: Date
    /// Screen points per second of real time.
    public var pointsPerSecond: Double
    /// Viewport height in points.
    public var height: CGFloat

    public init(centre: Date, pointsPerSecond: Double, height: CGFloat) {
        self.centre = centre
        self.pointsPerSecond = pointsPerSecond
        self.height = height
    }

    // A life is the outer limit and a couple of hours the inner one. Beyond
    // either end there is nothing more to learn: further in and you are
    // reading the gaps between minutes, further out and a decade is a pixel.
    public static let shortestSpan: TimeInterval = 2 * 3600
    public static let longestSpan: TimeInterval = 140 * 365.2425 * 86400

    public static let earliest = Date(timeIntervalSince1970: -2_208_988_800) // 1900-01-01
    public static let latest = Date(timeIntervalSince1970: 4_418_150_400)    // 2110-01-01

    public static func pointsPerSecond(height: CGFloat, span: TimeInterval) -> Double {
        guard span > 0 else { return 1 }
        return Double(height) / span
    }

    public static func scaleLimits(height: CGFloat) -> ClosedRange<Double> {
        let tightest = pointsPerSecond(height: height, span: longestSpan)
        let loosest = pointsPerSecond(height: height, span: shortestSpan)
        return tightest...loosest
    }

    public var span: TimeInterval { Double(height) / pointsPerSecond }
    public var top: Date { date(atY: 0) }
    public var bottom: Date { date(atY: height) }
    public var visibleRange: ClosedRange<Date> { top...bottom }

    public func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(centre) * pointsPerSecond) + height / 2
    }

    public func date(atY y: CGFloat) -> Date {
        centre.addingTimeInterval(Double(y - height / 2) / pointsPerSecond)
    }

    /// Points one unit of the given length occupies right now. The single
    /// number every level-of-detail decision in the app is made from.
    public func points(for interval: TimeInterval) -> Double {
        interval * pointsPerSecond
    }

    public func clamped() -> TimeScale {
        var copy = self
        let limits = Self.scaleLimits(height: height)
        copy.pointsPerSecond = Curve.clamp(pointsPerSecond, limits.lowerBound, limits.upperBound)
        if copy.centre < Self.earliest { copy.centre = Self.earliest }
        if copy.centre > Self.latest { copy.centre = Self.latest }
        return copy
    }

    /// Zoom by `factor` while pinning whatever sits at `y`.
    public func zoomed(by factor: Double, around y: CGFloat) -> TimeScale {
        let anchor = date(atY: y)
        var copy = self
        let limits = Self.scaleLimits(height: height)
        copy.pointsPerSecond = Curve.clamp(pointsPerSecond * factor, limits.lowerBound, limits.upperBound)
        copy.centre = anchor.addingTimeInterval(-Double(y - height / 2) / copy.pointsPerSecond)
        return copy.clamped()
    }

    public func panned(byPoints dy: CGFloat) -> TimeScale {
        var copy = self
        copy.centre = centre.addingTimeInterval(-Double(dy) / pointsPerSecond)
        return copy.clamped()
    }
}

/// The named rungs on the zoom ladder. Every gesture has one of these as a
/// button, because pinching to a precise scale is exactly the thing this app
/// should not require of anyone.
public enum ZoomStep: String, CaseIterable, Identifiable, Sendable {
    case hours, days, weeks, months, years, life

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hours: "Hours"
        case .days: "Days"
        case .weeks: "Weeks"
        case .months: "Months"
        case .years: "Years"
        case .life: "Life"
        }
    }

    /// Nil for `life`, whose span depends on how long the life is.
    public var span: TimeInterval? {
        switch self {
        case .hours: 15 * 3600
        case .days: 5 * 86400
        case .weeks: 42 * 86400
        case .months: 426 * 86400
        case .years: 12 * 365.2425 * 86400
        case .life: nil
        }
    }
}
