// One thing that happened, or will.
//
// Two independent axes, and keeping them apart is what makes the zoomed-out
// view readable: `category` is what kind of thing it is (colour), `weight` is
// how far out it stays worth showing (survival). A dentist appointment is
// health and everyday; being born is life and a milestone.

import Foundation

public enum Category: String, Codable, CaseIterable, Sendable {
    case life, work, health, people, travel, home, rhythm

    public var label: String {
        switch self {
        case .life: "Milestone"
        case .work: "Work"
        case .health: "Health & body"
        case .people: "People"
        case .travel: "Travel"
        case .home: "Home"
        case .rhythm: "Everyday rhythm"
        }
    }

    public var rgb: RGB {
        switch self {
        case .life: RGB(hex: 0xF5C46B)
        case .work: RGB(hex: 0x6AA6F2)
        case .health: RGB(hex: 0xF2809F)
        case .people: RGB(hex: 0xB98CE8)
        case .travel: RGB(hex: 0x4FC9AE)
        case .home: RGB(hex: 0x9BD473)
        case .rhythm: RGB(hex: 0x7F8DAB)
        }
    }
}

/// How big a thing is, in the only terms that matter here: how far you can
/// zoom out and still see it.
public enum Weight: Int, Codable, CaseIterable, Comparable, Sendable {
    case everyday = 0
    case worthRemembering = 1
    case notable = 2
    case milestone = 3

    public static func < (lhs: Weight, rhs: Weight) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .everyday: "Everyday"
        case .worthRemembering: "Worth remembering"
        case .notable: "Notable"
        case .milestone: "Milestone"
        }
    }
}

public struct Event: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    /// Seconds. Zero means a moment rather than a stretch, and the two are
    /// drawn differently at every zoom level: a dot versus a block.
    public var duration: TimeInterval
    public var category: Category
    public var weight: Weight
    public var note: String

    public init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        duration: TimeInterval = 0,
        category: Category = .life,
        weight: Weight = .worthRemembering,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.duration = max(0, duration)
        self.category = category
        self.weight = weight
        self.note = note
    }

    public var end: Date { start.addingTimeInterval(duration) }
    public var isMoment: Bool { duration <= 0 }
    /// The point the label hangs off - the middle of a trip, the instant of a birth.
    public var anchor: Date { start.addingTimeInterval(duration / 2) }
}
