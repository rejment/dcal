// One frame of the timeline, described but not drawn.
//
// Keeping this separate from the Canvas buys two things: the geometry can be
// unit tested without a screen, and a tap can be resolved against exactly the
// same rectangles that were drawn, instead of a second guess at where things
// probably landed.

import CoreGraphics
import Foundation

public struct TimelineLayout: Sendable {
    public struct Metrics: Sendable {
        public let size: CGSize
        /// Width of the ruler column on the left.
        public let gutter: CGFloat
        /// The saturated column of time itself.
        public let ribbon: CGRect
        public let contentX: CGFloat
        public let contentWidth: CGFloat
    }

    public struct Tick: Sendable {
        public let y: CGFloat
        public let text: String
        public let isMajor: Bool
        public let isWeekend: Bool
    }

    public struct GridLine: Sendable {
        public let y: CGFloat
        public let opacity: Double
    }

    public struct Band: Sendable {
        public let rect: CGRect
    }

    public struct Notch: Sendable {
        public let rect: CGRect
        public let colour: RGB
        public let opacity: Double
    }

    public struct Block: Sendable {
        public let event: Event
        public let frame: CGRect
        /// A stretch gets a box, a moment gets a dot and a line of text.
        public let isStretch: Bool
        public let timeText: String
    }

    public struct Landmark: Sendable {
        public let event: Event
        public let y: CGFloat
        /// Set when the thing lasted long enough to be worth a bracket.
        public let bracket: ClosedRange<CGFloat>?
        public let ageText: String?
        public let hitFrame: CGRect
    }

    public struct GroundStop: Sendable {
        public let location: Double
        public let colour: RGB
    }

    public let metrics: Metrics
    public let groundStops: [GroundStop]
    public let bands: [Band]
    public let grid: [GridLine]
    public let ticks: [Tick]
    public let notches: [Notch]
    public let blocks: [Block]
    public let landmarks: [Landmark]
    public let scheduleOpacity: Double
    public let nowY: CGFloat?

    /// Whatever was drawn at that point, topmost first.
    public func event(at point: CGPoint) -> Event? {
        if scheduleOpacity >= 0.5 {
            if let hit = blocks.last(where: { $0.frame.insetBy(dx: -4, dy: -2).contains(point) }) {
                return hit.event
            }
            return landmarks.last { $0.hitFrame.contains(point) }?.event
        }
        if let hit = landmarks.last(where: { $0.hitFrame.contains(point) }) { return hit.event }
        return blocks.last { $0.frame.insetBy(dx: -4, dy: -2).contains(point) }?.event
    }
}

public enum TimelineLayoutBuilder {
    static let ribbonWidth: CGFloat = 14

    public static func build(
        scale: TimeScale,
        size: CGSize,
        chromeTop: CGFloat,
        chromeBottom: CGFloat,
        lifeline: Lifeline,
        tickCalendar: TickCalendar,
        now: Date = Date()
    ) -> TimelineLayout {
        let calendar = tickCalendar.calendar
        let gutter: CGFloat = size.width < 420 ? 54 : 70
        let ribbon = CGRect(x: gutter, y: 0, width: ribbonWidth, height: size.height)
        let contentX = gutter + ribbonWidth + 13
        let contentWidth = max(60, size.width - contentX - 14)
        let metrics = TimelineLayout.Metrics(
            size: size, gutter: gutter, ribbon: ribbon,
            contentX: contentX, contentWidth: contentWidth
        )

        let top = scale.top
        let bottom = scale.bottom
        let (majorLevel, minorLevel) = TickCalendar.levels(for: scale)

        // --- the painted ground, sampled down the view ---
        let sampleCount = Int(Curve.clamp(Double(size.height) / 6, 40, 140))
        var groundStops: [TimelineLayout.GroundStop] = []
        groundStops.reserveCapacity(sampleCount)
        for index in 0..<max(2, sampleCount) {
            let location = Double(index) / Double(max(1, sampleCount - 1))
            let date = scale.date(atY: CGFloat(location) * size.height)
            groundStops.append(.init(
                location: location,
                colour: SkyPalette.ground(at: date, scale: scale, calendar: calendar)
            ))
        }

        // --- alternating bands of the unit you are reading in ---
        var bands: [TimelineLayout.Band] = []
        if scale.points(for: majorLevel.approximateLength) < Double(size.height) * 1.6 {
            // Start one unit early so the band the view opens inside is
            // painted from its real edge, not from the top of the screen.
            let start = top.addingTimeInterval(-majorLevel.approximateLength * 1.5)
            for date in tickCalendar.ticks(majorLevel, from: start, to: bottom) {
                guard parity(of: date, level: majorLevel, calendar: calendar) == 0 else { continue }
                let y0 = scale.y(for: date)
                let y1 = scale.y(for: tickCalendar.advance(date, by: majorLevel))
                bands.append(.init(rect: CGRect(
                    x: gutter + ribbonWidth, y: y0,
                    width: size.width - gutter - ribbonWidth, height: max(0, y1 - y0)
                )))
            }
        }

        // --- grid, every level that is legible, coarse ones heavier ---
        var grid: [TimelineLayout.GridLine] = []
        for level in TickLevel.ladder {
            let spacing = scale.points(for: level.approximateLength)
            guard spacing >= 9, spacing <= Double(size.height) * 2.2 else { continue }
            let isMajor = level == majorLevel
            let opacity = Curve.smoothstep(9, 34, spacing)
                * (0.045 + 0.05 * level.weight)
                * (isMajor ? 2.1 : 1)
            guard opacity >= 0.012 else { continue }
            for date in tickCalendar.ticks(level, from: top, to: bottom) {
                // Not snapped to the pixel grid. A crisp hairline is worth
                // less than moving in step with the ruler label beside it:
                // rounded, the line and its own label drift apart and back
                // together by up to half a point as you scroll, and the text
                // reads as wobbling against the line it belongs to.
                grid.append(.init(y: scale.y(for: date), opacity: opacity))
            }
        }

        // --- ruler ---
        let rulerTop = chromeTop
        let rulerBottom = size.height - chromeBottom
        var ticks: [TimelineLayout.Tick] = []
        if let minorLevel {
            for date in tickCalendar.ticks(minorLevel, from: top, to: bottom) {
                let y = scale.y(for: date)
                guard y >= rulerTop, y <= rulerBottom else { continue }
                ticks.append(.init(
                    y: y,
                    text: tickCalendar.label(for: date, level: minorLevel, tight: true),
                    isMajor: false,
                    isWeekend: false
                ))
            }
        }
        for date in tickCalendar.ticks(majorLevel, from: top, to: bottom) {
            let y = scale.y(for: date)
            guard y >= rulerTop, y <= rulerBottom else { continue }
            ticks.append(.init(
                y: y,
                text: tickCalendar.label(for: date, level: majorLevel, tight: size.width < 420),
                isMajor: true,
                isWeekend: majorLevel.unit == .day && tickCalendar.isWeekend(date)
            ))
        }

        // --- what is on screen ---
        let margin = Double(60) / scale.pointsPerSecond
        let visible = lifeline.events(overlapping:
            top.addingTimeInterval(-margin)...bottom.addingTimeInterval(margin))

        // Lanes and labels are decided against a good deal more than what is
        // on screen. Both are chain decisions - a block's lane depends on
        // everything it overlaps, a label's slot on its neighbours - so if
        // the input set changes as things scroll past the edge, the answer
        // changes for everything still in view and the whole column twitches.
        // A screen and a half either way covers any cluster that could reach
        // across the visible area.
        let reach = Double(size.height * 1.5) / scale.pointsPerSecond
        let context = lifeline.events(overlapping:
            top.addingTimeInterval(-reach)...bottom.addingTimeInterval(reach))

        // Every single thing leaves a mark in the ribbon, at every zoom.
        // This is what tells you a stretch of life was busy when there is no
        // room left to name any of it.
        var notches: [TimelineLayout.Notch] = []
        notches.reserveCapacity(visible.count)
        for event in visible {
            let y0 = scale.y(for: event.start)
            let y1 = scale.y(for: event.end)
            let minimum: CGFloat = event.weight == .milestone ? 2.6 : 1.6
            let height = max(minimum, y1 - y0)
            let width: CGFloat = switch event.weight {
            case .milestone: ribbonWidth - 2
            case .notable: ribbonWidth - 4
            default: ribbonWidth - 7
            }
            let opacity: Double = switch event.weight {
            case .milestone: 0.95
            case .notable: 0.7
            default: 0.42
            }
            notches.append(.init(
                rect: CGRect(x: gutter + 1, y: y0 - height / 2, width: width, height: height),
                colour: event.category.rgb,
                opacity: opacity
            ))
        }

        let scheduleOpacity = SkyPalette.scheduleOpacity(for: scale)

        var blocks: [TimelineLayout.Block] = []
        if scheduleOpacity > 0.005 {
            blocks = buildBlocks(
                visible: context, scale: scale, metrics: metrics, tickCalendar: tickCalendar
            )
        }

        var landmarks: [TimelineLayout.Landmark] = []
        if scheduleOpacity < 0.995 {
            landmarks = buildLandmarks(
                visible: context, scale: scale, metrics: metrics, lifeline: lifeline,
                calendar: calendar, rulerTop: rulerTop, rulerBottom: rulerBottom
            )
        }

        let nowYRaw = scale.y(for: now)
        let nowY = (nowYRaw > -30 && nowYRaw < size.height + 30) ? nowYRaw : nil

        return TimelineLayout(
            metrics: metrics, groundStops: groundStops, bands: bands, grid: grid,
            ticks: ticks, notches: notches, blocks: blocks, landmarks: landmarks,
            scheduleOpacity: scheduleOpacity, nowY: nowY
        )
    }

    private static func buildBlocks(
        visible: [Event],
        scale: TimeScale,
        metrics: TimelineLayout.Metrics,
        tickCalendar: TickCalendar
    ) -> [TimelineLayout.Block] {
        let spans: [ClosedRange<CGFloat>] = visible.map { event in
            let y0 = scale.y(for: event.start)
            let minimum: CGFloat = event.isMoment ? 22 : 26
            return y0...max(scale.y(for: event.end), y0 + minimum)
        }
        let packed = Layout.packLanes(spans)

        var blocks: [TimelineLayout.Block] = []
        blocks.reserveCapacity(visible.count)
        for (index, event) in visible.enumerated() {
            let span = spans[index]
            guard span.upperBound > -10, span.lowerBound < metrics.size.height + 10 else { continue }
            let lanes = min(packed[index].lanes, 4)
            let lane = min(packed[index].lane, lanes - 1)
            let laneWidth = metrics.contentWidth / CGFloat(lanes)
            let frame = CGRect(
                x: metrics.contentX + CGFloat(lane) * laneWidth,
                y: span.lowerBound,
                width: laneWidth - 4,
                height: span.upperBound - span.lowerBound
            )
            let timeText = event.isMoment
                ? tickCalendar.clockLabel(event.start)
                : "\(tickCalendar.clockLabel(event.start))–\(tickCalendar.clockLabel(event.end))"
            blocks.append(.init(
                event: event, frame: frame, isStretch: !event.isMoment, timeText: timeText
            ))
        }
        return blocks
    }

    private static func buildLandmarks(
        visible: [Event],
        scale: TimeScale,
        metrics: TimelineLayout.Metrics,
        lifeline: Lifeline,
        calendar: Calendar,
        rulerTop: CGFloat,
        rulerBottom: CGFloat
    ) -> [TimelineLayout.Landmark] {
        let floor = Layout.minimumWeight(forSpan: scale.span)
        // Candidates run past the visible band so that something scrolling in
        // has already been competing for its slot before it appears.
        let approach: CGFloat = 150
        var candidates: [Layout.LabelCandidate] = []
        for (index, event) in visible.enumerated() {
            guard event.weight >= floor else { continue }
            let y = scale.y(for: event.anchor)
            guard y >= rulerTop - approach, y <= rulerBottom + approach else { continue }
            candidates.append(.init(index: index, y: y, weight: event.weight))
        }

        let chosen = Layout.placeLabels(candidates, gap: { $0 == .milestone ? 27 : 23 })

        // Age only once a year is small enough that "1992" stops being an
        // answer to how long ago that was.
        let showAge = scale.span > 360 * 86400
        let dotX = metrics.gutter + ribbonWidth + 9

        var landmarks: [TimelineLayout.Landmark] = []
        for index in chosen.sorted() {
            let event = visible[index]
            let y = scale.y(for: event.anchor)
            guard y >= rulerTop, y <= rulerBottom else { continue }
            let y0 = scale.y(for: event.start)
            let y1 = scale.y(for: event.end)
            let bracket = (y1 - y0) > 7 ? y0...y1 : nil
            var ageText: String?
            if showAge, let age = lifeline.age(at: event.start, calendar: calendar) {
                ageText = "age \(age)"
            }
            landmarks.append(.init(
                event: event,
                y: y,
                bracket: bracket,
                ageText: ageText,
                hitFrame: CGRect(
                    x: dotX - 10, y: y - 15,
                    width: metrics.size.width - dotX + 4, height: 30
                )
            ))
        }
        return landmarks
    }

    /// Stable under panning: derived from the calendar, never from where the
    /// enumeration happened to start, or the bands would flip as you scroll.
    static func parity(of date: Date, level: TickLevel, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        switch level.unit {
        case .minute:
            return ((parts.minute ?? 0) / level.count) % 2
        case .hour:
            return ((parts.hour ?? 0) / level.count) % 2
        case .day:
            return (calendar.ordinality(of: .day, in: .era, for: date) ?? 0) % 2
        case .week:
            return calendar.component(.weekOfYear, from: date) % 2
        case .month:
            let months = (parts.year ?? 0) * 12 + ((parts.month ?? 1) - 1)
            return (months / level.count) % 2
        case .year:
            return ((parts.year ?? 0) / level.count) % 2
        }
    }
}

public extension TickCalendar {
    /// 24-hour clock, matching the ruler, independent of locale so the two
    /// can never disagree on the same screen.
    func clockLabel(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
