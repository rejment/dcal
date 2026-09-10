// The palette, and the one type decision that gives the app its voice.
//
// Dark only, deliberately: the timeline paints its own ground with the colour
// of the hour, and a light chrome around it would fight that. The system
// serif carries the "where am I" header - a life reads as a book, not a
// scheduling grid - and SF Pro does everything else.

import DcalKit
import SwiftUI

enum Theme {
    static let ground = Color(rgb: SkyPalette.voidBase)
    static let chalk = Color(hex: 0xEEF2FA)
    static let fog = Color(hex: 0x7F8DAB)
    static let amber = Color(hex: 0xF5C46B)
    static let panel = Color(hex: 0x0B1122)
    static let panelRaised = Color(hex: 0x131C33)
    static let edge = Color(white: 0.75, opacity: 0.16)

    static func display(_ size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(rgb: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(rgb: RGB(hex: hex), opacity: opacity)
    }
}

/// The pill used for the zoom steps and the buttons beside them.
struct RailButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: square ? 19 : 14, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .frame(minWidth: square ? 44 : 0, minHeight: 44)
            .padding(.horizontal, square ? 0 : 14)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: square ? 13 : 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: square ? 13 : 22, style: .continuous)
                    .strokeBorder(selected || prominent ? .clear : Theme.edge)
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
    }

    private var foreground: Color {
        if selected { return Theme.ground }
        if prominent { return Color(hex: 0x2A1D05) }
        return Theme.chalk
    }

    private var background: Color {
        if selected { return Theme.chalk }
        if prominent { return Theme.amber }
        return Theme.panel.opacity(0.72)
    }
}

extension View {
    /// An inline title bar, which only exists on iOS. macOS builds of this
    /// package are for type-checking, so there it is a no-op.
    @ViewBuilder
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
