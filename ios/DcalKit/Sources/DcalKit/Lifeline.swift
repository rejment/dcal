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

    public func save(_ lifeline: Lifeline) throws {
        let data = try Self.encoder.encode(lifeline)
        try data.write(to: url, options: .atomic)
    }
}
