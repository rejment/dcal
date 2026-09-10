// The spreadsheet form of a lifeline.
//
// For putting a life in from old photos and notes, a spreadsheet beats a JSON
// editor: you get columns, sorting, fill-down and a date picker for free. So
// the same events go out and come back as CSV, with a row of column names at
// the top.
//
// Reading is as forgiving as the JSON side, and then some, because a
// spreadsheet is whatever the program that saved it felt like writing:
// commas, semicolons (which is what Excel uses on a Swedish machine) or tabs;
// CRLF or LF; a byte order mark; Excel's own "sep=;" hint line. Columns are
// found by name, so their order does not matter and extra ones are ignored.
//
// Every field is then handed to the same validator the JSON path uses, so the
// two formats cannot drift apart in what they accept or what they say when
// something is wrong.

import Foundation

extension LifelineDocument {
    /// Column names understood on the way in. The first of each list is what
    /// gets written on the way out.
    enum Column: CaseIterable {
        case title, start, lasts, weight, category, note, id

        var names: [String] {
            switch self {
            case .title: ["title", "name", "what", "event"]
            case .start: ["start", "starts", "date", "when"]
            case .lasts: ["lasts", "duration", "length", "how long"]
            case .weight: ["weight", "size", "how big"]
            case .category: ["category", "kind", "type", "part of life"]
            case .note: ["note", "notes", "comment", "description"]
            case .id: ["id", "uuid"]
            }
        }

        /// The dictionary key the shared validator expects.
        var key: String { names[0] }
    }

    // MARK: - Writing

    public func csv(for lifeline: Lifeline) -> String {
        var out = Column.allCases.map(\.key).joined(separator: ",") + "\n"
        for event in lifeline.events {
            let fields = [
                event.title,
                stamp(event.start),
                event.duration > 0 ? spell(event.duration) : "",
                event.weight.slug,
                event.category.rawValue,
                event.note,
                event.id.uuidString,
            ]
            out += fields.map(Self.escape).joined(separator: ",") + "\n"
        }
        return out
    }

    /// Quoted whenever it contains anything that could be a separator in some
    /// other program's idea of CSV, so the file survives a round trip through
    /// a spreadsheet that saves with semicolons.
    static func escape(_ raw: String) -> String {
        let awkward: Set<Character> = [",", ";", "\t", "\"", "\n", "\r"]
        guard raw.contains(where: { awkward.contains($0) }) else { return raw }
        return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Reading

    public func lifeline(fromCSV text: String) throws -> Lifeline {
        var body = text
        // A byte order mark forms one grapheme cluster with the letter after
        // it, so it cannot be dropped as a Character.
        if body.unicodeScalars.first == "\u{FEFF}" {
            body = String(String.UnicodeScalarView(body.unicodeScalars.dropFirst()))
        }

        // Excel writes this to announce its own separator.
        var declared: Character?
        if body.lowercased().hasPrefix("sep=") {
            declared = body.prefix(while: { !$0.isNewline }).dropFirst(4).first
            body = String(body.drop(while: { !$0.isNewline }).drop(while: \.isNewline))
        }

        let delimiter = declared ?? Self.delimiter(for: body)
        let rows = Self.records(from: body, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

        guard let header = rows.first else { throw LifelineDocumentError.notReadable }

        var columns: [Int: Column] = [:]
        for (index, cell) in header.enumerated() {
            let name = cell.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let column = Column.allCases.first(where: { $0.names.contains(name) }) {
                columns[index] = column
            }
        }
        let found = Set(columns.values)
        guard found.contains(.title), found.contains(.start) else {
            throw LifelineDocumentError.missingColumns
        }

        let body_ = rows.dropFirst()
        guard !body_.isEmpty else { throw LifelineDocumentError.noEvents }

        var events: [Event] = []
        for (offset, row) in body_.enumerated() {
            var fields: [String: Any] = [:]
            for (index, cell) in row.enumerated() {
                guard let column = columns[index] else { continue }
                let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                fields[column.key] = value
            }
            // Row 1 is the header, so the first event is on row 2 - the same
            // number the spreadsheet shows down its left edge.
            events.append(try event(from: fields, at: .row(offset + 2)))
        }
        return Lifeline(events: events)
    }

    /// Whichever candidate appears most often outside quotes on the first
    /// line. Comma when nothing suggests otherwise.
    static func delimiter(for text: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if character.isNewline { break }
            if counts[character] != nil { counts[character, default: 0] += 1 }
        }
        let best = counts.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }
        return (best?.value ?? 0) > 0 ? best!.key : ","
    }

    /// RFC 4180: quoted fields may contain the delimiter, newlines, and
    /// doubled quotes standing for one.
    static func records(from text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]

            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(character)
                }
                index += 1
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            default:
                // Swift reads CRLF as a single Character, so this has to ask
                // rather than compare against "\n" and "\r".
                if character.isNewline {
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                } else {
                    field.append(character)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
