// The words at the top of the screen.
//
// Two lines, always the same shape: the small one names the larger thing you
// are inside, the big one names where you are. That structure is the point -
// someone who loses their footing in time gets the same two answers at every
// zoom level, instead of a ruler that changes units on them.

import Foundation

public struct Whereabouts: Equatable, Sendable {
    /// The containing unit. Nil only when there is nothing larger to name.
    public let context: String?
    public let headline: String
    /// How much time is on screen, in words. "Showing" is added by the view.
    public let spanWords: String

    public static func describe(scale: TimeScale, calendar: Calendar) -> Whereabouts {
        let centre = scale.centre
        let span = scale.span
        let day: TimeInterval = 86400
        let year: TimeInterval = 31_556_952

        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .weekOfYear], from: centre)
        let year0 = parts.year ?? 2000
        let monthIndex = (parts.month ?? 1) - 1
        let monthName = calendar.monthSymbols.indices.contains(monthIndex)
            ? calendar.monthSymbols[monthIndex] : ""
        let weekdayIndex = (parts.weekday ?? 1) - 1
        let weekdayName = calendar.weekdaySymbols.indices.contains(weekdayIndex)
            ? calendar.weekdaySymbols[weekdayIndex] : ""
        let decade = Int((Double(year0) / 10).rounded(.down)) * 10

        if span < 2.6 * day {
            return .init(
                context: weekdayName,
                headline: "\(parts.day ?? 1) \(monthName) \(year0)",
                spanWords: words(span)
            )
        }
        if span < 24 * day {
            return .init(
                context: "Week \(parts.weekOfYear ?? 1)",
                headline: "\(monthName) \(year0)",
                spanWords: words(span)
            )
        }
        if span < 150 * day {
            return .init(context: String(year0), headline: monthName, spanWords: words(span))
        }
        if span < 2.5 * year {
            return .init(context: "The \(decade)s", headline: String(year0), spanWords: words(span))
        }
        if span < 26 * year {
            let century = (year0 - 1) / 100 + 1
            return .init(
                context: "The \(ordinal(century)) century",
                headline: "The \(decade)s",
                spanWords: words(span)
            )
        }
        let first = calendar.component(.year, from: scale.top)
        let last = calendar.component(.year, from: scale.bottom)
        return .init(context: "A lifetime", headline: "\(first)–\(last)", spanWords: words(span))
    }

    /// Round numbers in the largest unit that still gives one. Nobody needs
    /// "showing 2.4 weeks".
    static func words(_ span: TimeInterval) -> String {
        let day: TimeInterval = 86400
        let year: TimeInterval = 31_556_952

        func plural(_ count: Int, _ unit: String) -> String {
            count == 1 ? "one \(unit)" : "\(count) \(unit)s"
        }
        if span < 4 * 3600 { return plural(max(1, Int((span / 3600).rounded())), "hour") }
        if span < 10 * day { return plural(max(1, Int((span / day).rounded())), "day") }
        if span < 70 * day { return plural(max(1, Int((span / (7 * day)).rounded())), "week") }
        if span < 500 * day { return plural(max(1, Int((span / (30.44 * day)).rounded())), "month") }
        return plural(max(1, Int((span / year).rounded())), "year")
    }

    static func ordinal(_ value: Int) -> String {
        let hundreds = value % 100
        if (11...13).contains(hundreds) { return "\(value)th" }
        return switch value % 10 {
        case 1: "\(value)st"
        case 2: "\(value)nd"
        case 3: "\(value)rd"
        default: "\(value)th"
        }
    }
}
