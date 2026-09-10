// Everything on the timeline, kept sorted, plus the one derived fact that
// makes a lifetime readable: how old you were.

import Foundation

public struct Lifeline: Codable, Equatable, Sendable {
    public private(set) var events: [Event]

    public init(events: [Event] = []) {
        self.events = events.sorted { $0.start < $1.start }
    }

    public mutating func upsert(_ event: Event) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort { $0.start < $1.start }
    }

    public mutating func remove(id: Event.ID) {
        events.removeAll { $0.id == id }
    }

    /// Anything whose stretch touches the range, moments included.
    public func events(overlapping range: ClosedRange<Date>) -> [Event] {
        events.filter { $0.end >= range.lowerBound && $0.start <= range.upperBound }
    }

    /// The birth marks the origin of the age axis. Whichever milestone sits
    /// earliest is taken to be it, so importing a life does not need a
    /// separate settings screen.
    public var birth: Date? {
        events.first { $0.weight == .milestone }?.start
    }

    public func age(at date: Date, calendar: Calendar) -> Int? {
        guard let birth, date >= birth else { return nil }
        return calendar.dateComponents([.year], from: birth, to: date).year
    }
}

/// A JSON file in Application Support. Small enough that rewriting the whole
/// thing on every edit is simpler than anything cleverer, and it means the
/// file can be read, diffed and repaired by hand.
public struct LifelineStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("dcal-lifeline.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func load() throws -> Lifeline? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(Lifeline.self, from: data)
    }

    /// What happened when the app tried to pick up where it left off.
    public enum Load: Equatable, Sendable {
        case nothingSaved
        case loaded(Lifeline)
        /// There was a file and it could not be read. It has been moved to
        /// `keptAt` rather than written over.
        case unreadable(keptAt: URL)
    }

    /// Reading on launch, without the one behaviour that could lose a life:
    /// treating "I couldn't read this" as "there was nothing here" and then
    /// saving over it. A file that fails to decode is moved aside under a
    /// dated name, so the bytes survive whatever went wrong - a half-written
    /// save, a shape this version no longer understands - and can still be
    /// opened through Import, which reads the store format too.
    public func loadOrSalvage(salvageInto directory: URL? = nil) -> Load {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return .nothingSaved }
        if let lifeline = try? load(), !lifeline.events.isEmpty { return .loaded(lifeline) }

        let stamp = ISO8601DateFormatter.salvageStamp.string(from: Date())
        let home = directory ?? url.deletingLastPathComponent()
        let aside = home.appendingPathComponent("dcal-lifeline-unreadable-\(stamp).json")
        do {
            try manager.createDirectory(at: home, withIntermediateDirectories: true)
            try manager.moveItem(at: url, to: aside)
        } catch {
            // Even the rescue failed. Leave the file exactly where it is -
            // still better than overwriting it.
            return .unreadable(keptAt: url)
        }
        return .unreadable(keptAt: aside)
    }


    public func save(_ lifeline: Lifeline) throws {
        let data = try Self.encoder.encode(lifeline)
        try data.write(to: url, options: .atomic)
    }
}

extension ISO8601DateFormatter {
    static let salvageStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        return formatter
    }()
}
