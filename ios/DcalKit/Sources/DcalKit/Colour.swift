// Colours and the two easing helpers the whole layout leans on.
//
// RGB rather than SwiftUI.Color so the palette can be unit tested on a Mac
// with only the command line tools - DcalUI converts at the last moment.

import CoreGraphics
import Foundation

public struct RGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    public func mixed(with other: RGB, amount: Double) -> RGB {
        let t = Curve.clamp(amount, 0, 1)
        return RGB(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t
        )
    }

    /// Lighten (>1) or darken (<1) without leaving the representable range.
    public func scaled(by factor: Double) -> RGB {
        RGB(
            Curve.clamp(red * factor, 0, 1),
            Curve.clamp(green * factor, 0, 1),
            Curve.clamp(blue * factor, 0, 1)
        )
    }

    /// HSL is how the seasonal ramp is expressed - one hue that swings from
    /// cold to warm across the year - so it needs a way back to RGB.
    public static func hsl(hue: Double, saturation: Double, lightness: Double) -> RGB {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360
        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func channel(_ offset: Double) -> Double {
            var t = (h + offset).truncatingRemainder(dividingBy: 1)
            if t < 0 { t += 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return RGB(channel(1.0 / 3), channel(0), channel(-1.0 / 3))
    }
}

public enum Curve {
    public static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        value < low ? low : (value > high ? high : value)
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Hermite ramp from 0 at `edge0` to 1 at `edge1`. Every level of detail
    /// in this app fades in and out through one of these, which is what keeps
    /// a pinch from snapping between two different-looking timelines.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge1 != edge0 else { return value < edge0 ? 0 : 1 }
        let t = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }
}
