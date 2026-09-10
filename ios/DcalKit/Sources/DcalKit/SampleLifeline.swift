// The lifeline the app opens with, so the first launch shows what it does
// instead of an empty column.
//
// Two halves, because the app has two jobs to demonstrate: a made-up life
// from 1985 to a hypothetical retirement, and eleven weeks of ordinary
// appointments around today so the deepest zoom has something real-shaped
// in it. Everything here is invented.

import Foundation

public enum SampleLifeline {
    public static func make(now: Date = Date(), calendar: Calendar) -> Lifeline {
        var events: [Event] = []

        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return calendar.date(from: parts) ?? now
        }
        func add(
            _ date: Date,
            _ duration: TimeInterval,
            _ title: String,
            _ category: Category,
            _ weight: Weight,
            _ note: String = ""
        ) {
            events.append(Event(
                title: title, start: date, duration: duration,
                category: category, weight: weight, note: note
            ))
        }

        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400

        // The spine of a life.
        add(at(1985, 6, 14, 4, 12), 0, "Born", .life, .milestone, "A Friday morning, six weeks early.")
        add(at(1989, 4, 2), 0, "The red bicycle", .life, .milestone, "First thing I can actually remember.")
        add(at(1992, 8, 17, 8), 0, "Started school", .life, .milestone)
        add(at(1996, 7, 1), 0, "We moved to the coast", .life, .milestone)
        add(at(2001, 8, 20, 8), 0, "Started high school", .life, .milestone)
        add(at(2004, 9, 6, 9), 0, "First real job", .life, .milestone, "Warehouse. Six months.")
        add(at(2006, 3, 1), 0, "Moved to the city", .life, .milestone)
        add(at(2010, 6, 11, 15), 0, "Graduated", .life, .milestone)
        add(at(2013, 5, 1), 0, "The flat on Bergsgatan", .life, .milestone, "Seven good years.")
        add(at(2019, 1, 7, 9), 0, "Started at Vantor", .life, .milestone)
        add(at(2024, 4, 20), 0, "Moved to the house", .life, .milestone)
        add(at(2029, 1, 1), 0, "Sabbatical year", .life, .milestone, "Planned. Not yet booked.")
        add(at(2050, 6, 14), 0, "Retirement, in theory", .life, .milestone)

        // Stretches worth seeing from a distance.
        add(at(2016, 4, 2), 16 * day, "Japan", .travel, .notable, "Tokyo, Kanazawa, Kyoto.")
        add(at(2021, 7, 3), 21 * day, "Summer on Gotland", .travel, .notable)
        add(at(2023, 11, 18), 9 * day, "Lisbon", .travel, .notable)
        add(at(2026, 7, 4), 24 * day, "Summer holiday", .travel, .notable, "Four weeks off. Nothing booked yet.")
        add(at(2027, 6, 19), 14 * day, "Summer house, rented", .travel, .notable)
        add(at(2018, 10, 6), 0, "Grandmother's 90th", .people, .notable)
        add(at(2022, 2, 28), 3 * day, "Hospital, appendix", .health, .notable)

        // Every birthday and New Year, so the years have a pulse rather than
        // long empty stretches between milestones.
        for year in 1986...2040 {
            let round = (year - 1985) % 10 == 0
            add(
                at(year, 6, 14), 0,
                round ? "Turning \(year - 1985)" : "Birthday",
                .people, round ? .notable : .worthRemembering
            )
        }
        for year in 1990...2035 {
            add(at(year, 1, 1), 0, "New Year", .people, .worthRemembering)
        }

        // The ordinary weeks around today.
        let today = calendar.startOfDay(for: now)
        for offset in -40...40 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            func clock(_ h: Int, _ m: Int = 0) -> Date {
                var stamp = parts
                stamp.hour = h
                stamp.minute = m
                return calendar.date(from: stamp) ?? date
            }
            let weekend = calendar.isDateInWeekend(date)
            let weekday = calendar.component(.weekday, from: date)

            add(clock(6, 45), 0, "Wake up", .rhythm, .everyday)
            add(clock(22, 30), 0, "Lights out", .rhythm, .everyday)

            if weekend {
                add(clock(9, 30), 1.5 * hour, "Slow breakfast", .home, .worthRemembering)
                if weekday == 7 { add(clock(14), 2 * hour, "Groceries and laundry", .home, .everyday) }
            } else {
                add(clock(8, 30), 25 * 60, "Stand-up", .work, .worthRemembering)
                add(clock(12, 15), 45 * 60, "Lunch", .rhythm, .everyday)
                if offset % 3 == 0 { add(clock(10), hour, "Team meeting", .work, .worthRemembering) }
                if offset % 4 == 1 { add(clock(13, 30), 2.5 * hour, "Deep work", .work, .everyday, "Phone in the drawer.") }
                if offset % 5 == 2 { add(clock(15), 30 * 60, "One-to-one", .work, .worthRemembering) }
                add(clock(17, 10), 0, "Leave work", .rhythm, .everyday)
            }
            if weekday == 3 || weekday == 5 { add(clock(18, 30), hour, "Swimming", .health, .worthRemembering) }
            if weekday == 6 { add(clock(19), 2.5 * hour, "Dinner with Kim and Ravi", .people, .notable) }
            if weekday == 7 { add(clock(11), 3 * hour, "Long walk", .health, .worthRemembering) }
        }

        // A few things coming up, so the near future is not blank.
        add(today.addingTimeInterval(3 * day + 9.5 * hour), 45 * 60, "Dentist", .health, .notable, "Bring the referral.")
        add(today.addingTimeInterval(6 * day + 18 * hour), 4 * hour, "Anna's leaving party", .people, .notable)
        add(today.addingTimeInterval(11 * day + 7.7 * hour), 2.3 * hour, "Train to Gothenburg", .travel, .notable, "Seat 34, carriage 4.")
        add(today.addingTimeInterval(17 * day + 14 * hour), hour, "Yearly check-up", .health, .notable)
        add(today.addingTimeInterval(-2 * day + 16 * hour), 1.5 * hour, "Bike service", .home, .worthRemembering)

        return Lifeline(events: events)
    }
}
