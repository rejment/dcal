// The colour of the timeline is the time.
//
// Three signals, each fading in exactly when it becomes legible and out when
// it stops being:
//
//   close in   the sky at that hour - deep blue at 3am, warm at sunrise,
//              pale at midday. You can tell night from afternoon without
//              reading a number.
//   year scale seasons - cold blue January swinging to gold July.
//   whole life decades as alternating strata, the way a core sample reads.
//
// Nothing here is decoration: every pixel of the column is answering "when
// is this?" before any label does.

import Foundation

public enum SkyPalette {
    /// Anchor colours through one day, in hours. Interpolated between.
    static let skyStops: [(hour: Double, colour: RGB)] = [
        (0.0, RGB(hex: 0x05070F)),
        (4.2, RGB(hex: 0x070C1C)),
        (5.8, RGB(hex: 0x162047)),
        (7.0, RGB(hex: 0x4A3450)),
        (8.4, RGB(hex: 0x1E325E)),
        (12.0, RGB(hex: 0x2A4B7C)),
        (16.0, RGB(hex: 0x26426E)),
        (18.6, RGB(hex: 0x52344C)),
        (20.6, RGB(hex: 0x161C38)),
        (24.0, RGB(hex: 0x05070F)),
    ]

    /// The ground colour with no time-of-day information left in it.
    public static let deepBase = RGB(hex: 0x0D1730)
    /// Behind everything, including the ruler.
    public static let voidBase = RGB(hex: 0x05070E)

    public static func sky(hour: Double) -> RGB {
        let h = Curve.clamp(hour, 0, 24)
        for index in 0..<(skyStops.count - 1) where h <= skyStops[index + 1].hour {
            let lower = skyStops[index]
            let upper = skyStops[index + 1]
            let t = (h - lower.hour) / (upper.hour - lower.hour)
            return lower.colour.mixed(with: upper.colour, amount: t)
        }
        return skyStops[skyStops.count - 1].colour
    }

    /// Cold in midwinter, warm at midsummer, continuous across New Year.
    /// `month` is 1...12; `dayFraction` moves smoothly through it.
    public static func seasonHue(month: Int, dayFraction: Double = 0) -> Double {
        let position = Double(month - 1) + Curve.clamp(dayFraction, 0, 1)
        let phase = (cos((position + 0.5 - 6.5) / 12 * 2 * .pi) + 1) / 2
        return 216 - 186 * phase
    }

    /// The colour of the column at one instant, at the current zoom.
    public static func ground(at date: Date, scale: TimeScale, calendar: Calendar) -> RGB {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let monthPoints = scale.points(for: 2_630_016)
        let dayPoints = scale.points(for: 86400)
        let yearPoints = scale.points(for: 31_556_952)

        let seasonAmount = Curve.smoothstep(1.0, 8.5, monthPoints) * 0.92
        let seasonal = RGB.hsl(
            hue: seasonHue(month: parts.month ?? 1, dayFraction: Double((parts.day ?? 1) - 1) / 30),
            saturation: 0.42,
            lightness: 0.155
        )
        var colour = deepBase.mixed(with: seasonal, amount: seasonAmount)

        // Once a year is thinner than a fingertip, seasons are noise. Decades
        // take over as the thing you can actually see.
        let decadeAmount = 1 - Curve.smoothstep(9, 42, yearPoints)
        if decadeAmount > 0.01 {
            let decade = Int((Double(parts.year ?? 2000) / 10).rounded(.down))
            let lift = decade % 2 == 0 ? 0.72 : 1.45
            colour = colour.mixed(with: colour.scaled(by: lift), amount: decadeAmount)
        }

        let skyAmount = Curve.smoothstep(55, 190, dayPoints)
        if skyAmount > 0.003 {
            let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            colour = colour.mixed(with: sky(hour: hour), amount: skyAmount)
        }
        return colour
    }

    /// How strongly the schedule view has taken over from the landmark view.
    /// Both are drawn during the crossfade, which is why a pinch never snaps.
    public static func scheduleOpacity(for scale: TimeScale) -> Double {
        Curve.smoothstep(95, 215, scale.points(for: 86400))
    }
}
