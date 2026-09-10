// The file you edit on a desktop, and the file you keep as a backup.
//
// Written to be read and typed by a person, not just parsed:
//
//   { "dcal": 1,
//     "events": [
//       { "title": "Born", "start": "1985-06-14 04:12",
//         "weight": "milestone", "category": "life",
//         "note": "A Friday morning, six weeks early." },
//       { "title": "Japan", "start": "2016-04-02", "lasts": "16 days",
//         "weight": "notable", "category": "travel" }
//     ] }
//
// Dates are local time, durations say what they mean, and weights are the
// words the app itself uses. Everything except a title and a start is
// optional, so a life can be typed in as two columns and filled in later.
//
// Reading is deliberately more forgiving than writing. Anything the app has
// ever written is accepted, including the raw store file - seconds for
// `duration`, numbers for `weight`, ISO 8601 with a timezone - so an old
// backup or a file lifted straight off the device still imports. Errors name
// the event by its position in the file, because that is what someone
// staring at a text editor needs to know.

import Foundation

public enum LifelineDocumentError: LocalizedError, Equatable {
    case notReadable
    case noEvents
    case missingTitle(row: Int)
    case missingDate(row: Int, title: String)
    case badDate(row: Int, title: String, value: String)
    case badDuration(row: Int, title: String, value: String)
    case badWeight(row: Int, title: String, value: String)
    case badCategory(row: Int, title: String, value: String)

    public var errorDescription: String? {
        switch self {
        case .notReadable:
            "That doesn't look like a lifeline file. It should be JSON with a list called \"events\"."
        case .noEvents:
            "The file has no events in it."
        case .missingTitle(let row):
            "Event \(row) has no title."
        case .missingDate(let row, let title):
            "\"\(title)\" (event \(row)) has no start date."
        case .badDate(let row, let title, let value):
            "\"\(title)\" (event \(row)) has a date I can't read: \"\(value)\". Write it as 1985-06-14, or 1985-06-14 04:12."
        case .badDuration(let row, let title, let value):
            "\"\(title)\" (event \(row)) has a length I can't read: \"\(value)\". Write it as 90 minutes, 2 hours, or 16 days."
        case .badWeight(let row, let title, let value):
            "\"\(title)\" (event \(row)) has an unknown size: \"\(value)\". Use everyday, worth remembering, notable, or milestone."
        case .badCategory(let row, let title, let value):
            "\"\(title)\" (event \(row)) has an unknown category: \"\(value)\". Use \(Category.allCases.map(\.rawValue).joined(separator: ", "))."
        }
    }
}

public struct LifelineDocument {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public static let formatVersion = 1

    // MARK: - Writing

    public func text(for lifeline: Lifeline, exported: Date = Date()) -> String {
        var out = "{\n"
        out += "  \"dcal\": \(Self.formatVersion),\n"
        out += "  \"exported\": \(quote(stamp(exported))),\n"
        out += "  \"events\": [\n"

        let rows = lifeline.events.map { event -> String in
            var fields = [
                "\"title\": \(quote(event.title))",
                "\"start\": \(quote(stamp(event.start)))",
            ]
            if event.duration > 0 { fields.append("\"lasts\": \(quote(spell(event.duration)))") }
            fields.append("\"weight\": \(quote(event.weight.slug))")
            fields.append("\"category\": \(quote(event.category.rawValue))")
            if !event.note.isEmpty { fields.append("\"note\": \(quote(event.note))") }
            fields.append("\"id\": \(quote(event.id.uuidString))")
            return "    { " + fields.joined(separator: ", ") + " }"
        }
        out += rows.joined(separator: ",\n")
        out += "\n  ]\n}\n"
        return out
    }

    /// Local time, no timezone marker - the file is about this person's life,
    /// not about UTC. Seconds are dropped because nothing here needs them.
    func stamp(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 1, parts.day ?? 1
        )
        if (parts.hour ?? 0) == 0 && (parts.minute ?? 0) == 0 { return day }
        return day + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Whole units where one fits, so a round trip reads the way it was typed.
    func spell(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        func unit(_ size: Int, _ name: String) -> String? {
            guard seconds % size == 0 else { return nil }
            let count = seconds / size
            return "\(count) \(name)\(count == 1 ? "" : "s")"
        }
        return unit(604800, "week") ?? unit(86400, "day") ?? unit(3600, "hour")
            ?? unit(60, "minute") ?? "\(seconds) seconds"
    }

    func quote(_ raw: String) -> String {
        var out = "\""
        for character in raw.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }

    // MARK: - Reading

    public func lifeline(from text: String) throws -> Lifeline {
        guard let data = text.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data)
        else { throw LifelineDocumentError.notReadable }

        // Either the whole document, or just the array, so a fragment pasted
        // out of one still imports.
        let rows: [[String: Any]]
        if let list = top as? [[String: Any]] {
            rows = list
        } else if let object = top as? [String: Any],
                  let list = object["events"] as? [[String: Any]] {
            rows = list
        } else {
            throw LifelineDocumentError.notReadable
        }
        guard !rows.isEmpty else { throw LifelineDocumentError.noEvents }

        var events: [Event] = []
        for (index, row) in rows.enumerated() {
            events.append(try event(from: row, row: index + 1))
        }
        return Lifeline(events: events)
    }

    private func event(from row: [String: Any], row number: Int) throws -> Event {
        let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { throw LifelineDocumentError.missingTitle(row: number) }

        guard let rawStart = row["start"] ?? row["date"] else {
            throw LifelineDocumentError.missingDate(row: number, title: title)
        }
        let startText = String(describing: rawStart)
        guard let start = date(from: startText) else {
            throw LifelineDocumentError.badDate(row: number, title: title, value: startText)
        }

        var duration: TimeInterval = 0
        if let raw = row["lasts"] ?? row["duration"] {
            if let seconds = raw as? NSNumber {
                duration = seconds.doubleValue
            } else if let spelled = raw as? String {
                guard let parsed = self.duration(from: spelled) else {
                    throw LifelineDocumentError.badDuration(row: number, title: title, value: spelled)
                }
                duration = parsed
            }
        }

        var weight = Weight.worthRemembering
        if let raw = row["weight"] ?? row["size"] {
            if let number = raw as? NSNumber, let parsed = Weight(rawValue: number.intValue) {
                weight = parsed
            } else if let word = raw as? String {
                guard let parsed = Weight(slug: word) else {
                    throw LifelineDocumentError.badWeight(row: number, title: title, value: word)
                }
                weight = parsed
            }
        }

        var category = Category.life
        if let word = row["category"] as? String, !word.isEmpty {
            guard let parsed = Category(rawValue: word.lowercased().trimmingCharacters(in: .whitespaces))
            else { throw LifelineDocumentError.badCategory(row: number, title: title, value: word) }
            category = parsed
        }

        let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        return Event(
            id: id, title: title, start: start, duration: max(0, duration),
            category: category, weight: weight,
            note: (row["note"] as? String) ?? ""
        )
    }

    /// Local time unless the text says otherwise.
    func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: trimmed) { return parsed }
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: trimmed) { return parsed }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for pattern in [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd", "yyyy-MM", "yyyy",
        ] {
            formatter.dateFormat = pattern
            if let parsed = formatter.date(from: trimmed) { return parsed }
        }
        return nil
    }

    func duration(from text: String) -> TimeInterval? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty || lower == "moment" || lower == "0" { return 0 }

        let scanner = Scanner(string: lower)
        guard let amount = scanner.scanDouble() else { return nil }
        let unit = lower[scanner.currentIndex...].trimmingCharacters(in: .whitespaces)

        switch unit {
        case "", "s", "sec", "secs", "second", "seconds": return amount
        case "m", "min", "mins", "minute", "minutes": return amount * 60
        case "h", "hr", "hrs", "hour", "hours": return amount * 3600
        case "d", "day", "days": return amount * 86400
        case "w", "week", "weeks": return amount * 604800
        default: return nil
        }
    }
}

extension Weight {
    /// The word the file uses. Kept separate from `label`, which is UI copy
    /// and free to change without breaking everyone's backups.
    var slug: String {
        switch self {
        case .everyday: "everyday"
        case .worthRemembering: "worth remembering"
        case .notable: "notable"
        case .milestone: "milestone"
        }
    }

    init?(slug: String) {
        let cleaned = slug.lowercased().trimmingCharacters(in: .whitespaces)
        switch cleaned {
        case "everyday", "every day", "routine", "0": self = .everyday
        case "worth remembering", "worthremembering", "1": self = .worthRemembering
        case "notable", "2": self = .notable
        case "milestone", "3": self = .milestone
        default: return nil
        }
    }
}
