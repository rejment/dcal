// The ladder of time units, and how to walk the calendar in each of them.
//
// Months and years are not fixed lengths, so boundaries come from Calendar
// rather than arithmetic on seconds. That is also what makes the hour lines
// survive a daylight-saving change: on the night the clocks go back, 02:00
// happens twice, and asking the calendar gives the same answer the phone's
// own clock does.

import Foundation

public struct TickLevel: Equatable, Sendable, Identifiable {
    public enum Unit: Sendable, Equatable {
        case minute, hour, day, week, month, year
    }

    public let id: String
    public let unit: Unit
    public let count: Int
    /// Only ever used to estimate spacing, never to place a line.
    public let approximateLength: TimeInterval
    /// How heavy the line is drawn - coarser units read stronger, the way a
    /// map draws country borders over street lines.
    public let weight: Double

    public static let ladder: [TickLevel] = [
        TickLevel(id: "m15", unit: .minute, count: 15, approximateLength: 900, weight: 0.45),
        TickLevel(id: "h1", unit: .hour, count: 1, approximateLength: 3600, weight: 0.85),
        TickLevel(id: "h3", unit: .hour, count: 3, approximateLength: 10800, weight: 1.05),
        TickLevel(id: "h6", unit: .hour, count: 6, approximateLength: 21600, weight: 1.20),
        TickLevel(id: "d1", unit: .day, count: 1, approximateLength: 86400, weight: 1.50),
        TickLevel(id: "w1", unit: .week, count: 1, approximateLength: 604800, weight: 1.70),
        TickLevel(id: "mo1", unit: .month, count: 1, approximateLength: 2_630_016, weight: 2.00),
        TickLevel(id: "mo3", unit: .month, count: 3, approximateLength: 7_890_048, weight: 2.20),
        TickLevel(id: "y1", unit: .year, count: 1, approximateLength: 31_556_952, weight: 2.50),
        TickLevel(id: "y5", unit: .year, count: 5, approximateLength: 157_784_760, weight: 2.70),
        TickLevel(id: "y10", unit: .year, count: 10, approximateLength: 315_569_520, weight: 2.90),
        TickLevel(id: "y50", unit: .year, count: 50, approximateLength: 1_577_847_600, weight: 3.10),
    ]
}

public struct TickCalendar: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// Gregorian with ISO week rules, so "week 37" means what it means on a
    /// Swedish wall calendar rather than starting the week on Sunday.
    public static func standard(timeZone: TimeZone = .current, locale: Locale = .current) -> TickCalendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return TickCalendar(calendar: calendar)
    }

    /// The last boundary of `level` at or before `date`.
    public func floor(_ date: Date, to level: TickLevel) -> Date {
        switch level.unit {
        case .minute:
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            parts.minute = (parts.minute ?? 0) / level.count * level.count
            return calendar.date(from: parts) ?? date
        case .hour:
            var parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            parts.hour = (parts.hour ?? 0) / level.count * level.count
            return calendar.date(from: parts) ?? date
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)
            let back = (weekday - calendar.firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: -back, to: day) ?? day
        case .month:
            var parts = calendar.dateComponents([.year, .month], from: date)
            parts.month = ((parts.month ?? 1) - 1) / level.count * level.count + 1
            parts.day = 1
            return calendar.date(from: parts) ?? date
        case .year:
            var parts = DateComponents()
            let year = calendar.component(.year, from: date)
            parts.year = Int((Double(year) / Double(level.count)).rounded(.down)) * level.count
            parts.month = 1
            parts.day = 1
            return calendar.date(from: parts) ?? date
        }
    }

    public func advance(_ date: Date, by level: TickLevel) -> Date {
        let component: Calendar.Component = switch level.unit {
        case .minute: .minute
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.date(byAdding: component, value: level.count, to: date) ?? date
    }

    /// Every boundary of `level` inside the range, oldest first.
    public func ticks(_ level: TickLevel, from: Date, to: Date, limit: Int = 4000) -> [Date] {
        guard to > from else { return [] }
        var result: [Date] = []
        var cursor = floor(from, to: level)
        var guardCount = 0
        while cursor <= to, guardCount < limit {
            if cursor >= from { result.append(cursor) }
            let next = advance(cursor, by: level)
            // Belt and braces: a calendar that refuses to advance would spin here.
            guard next > cursor else { break }
            cursor = next
            guardCount += 1
        }
        return result
    }

    public func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// ISO week number, as configured above.
    public func weekOfYear(_ date: Date) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    public func label(for date: Date, level: TickLevel, tight: Bool) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        switch level.unit {
        case .minute, .hour:
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        case .day:
            let day = String(parts.day ?? 1)
            if tight { return day }
            let symbols = calendar.shortWeekdaySymbols
            let index = (parts.weekday ?? 1) - 1
            let name = symbols.indices.contains(index) ? symbols[index] : ""
            return "\(name) \(day)"
        case .week:
            return "w\(weekOfYear(date))"
        case .month:
            let index = (parts.month ?? 1) - 1
            if level.count == 3 { return "Q\(index / 3 + 1)" }
            let symbols = tight ? calendar.shortMonthSymbols : calendar.monthSymbols
            return symbols.indices.contains(index) ? symbols[index] : ""
        case .year:
            return String(parts.year ?? 0)
        }
    }

    /// The finest level whose lines are far enough apart to carry a label,
    /// and the one below it, which gets small unlabelled-looking ticks.
    public static func levels(for scale: TimeScale) -> (major: TickLevel, minor: TickLevel?) {
        let ladder = TickLevel.ladder
        let spacing = ladder.map { scale.points(for: $0.approximateLength) }
        let majorIndex = spacing.firstIndex(where: { $0 >= 66 }) ?? (ladder.count - 1)
        let minorIndex = (majorIndex > 0 && spacing[majorIndex - 1] >= 32) ? majorIndex - 1 : nil
        return (ladder[majorIndex], minorIndex.map { ladder[$0] })
    }
}
