// The whole screen: a canvas, a transparent layer of gesture recognisers,
// and two pieces of floating chrome.
//
// The canvas ignores the safe area so the painted ground reaches the edges of
// the phone; the chrome does not, so it sits below the status bar and above
// the home indicator. Only the chrome's background gradients reach past it.
//
// Where the ruler has to stop is measured rather than assumed. Asking a
// GeometryReader for safeAreaInsets does not work here - once .ignoresSafeArea
// is applied there is no safe area left for it to report, and it answers zero -
// and a guessed height would be wrong anyway the moment Dynamic Type or a
// longer date makes the header taller.

import DcalKit
import SwiftUI

enum ActiveSheet: Identifiable {
    case detail(Event)
    case edit(Event, isNew: Bool)
    case menu

    var id: String {
        switch self {
        case .detail(let event): "detail-\(event.id)"
        case .edit(let event, _): "edit-\(event.id)"
        case .menu: "menu"
        }
    }
}

/// Where the masthead ends and where the control rail begins, both in the
/// canvas's own coordinates - which are the window's, since it ignores the
/// safe area.
private struct ChromeTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChromeBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

private struct MeasureEdge<Key: PreferenceKey>: ViewModifier where Key.Value == CGFloat {
    let key: Key.Type
    let edge: (CGRect) -> CGFloat

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: edge(proxy.frame(in: .global)))
            }
        )
    }
}

public struct DcalRootView: View {
    @State private var model = TimelineModel()
    @State private var sheet: ActiveSheet?

    public init() {}

    public var body: some View {
        ZStack {
            GeometryReader { proxy in
                let size = proxy.size
                let layout = model.layout(for: size)

                ZStack {
                    TimelineCanvas(layout: layout)
                        .accessibilityElement()
                        .accessibilityLabel("Timeline")
                        .accessibilityValue(accessibilityValue)
                        .accessibilityHint("Swipe up or down to zoom")
                        .accessibilityAdjustableAction { direction in
                            model.zoom(
                                by: direction == .increment ? 1.8 : 1 / 1.8,
                                around: size.height / 2
                            )
                        }

                    TimelineGestures(
                        model: model,
                        onTap: { point in
                            if let event = model.layout(for: size).event(at: point) {
                                sheet = .detail(event)
                            }
                        },
                        onLongPress: { point in
                            sheet = .edit(newEvent(at: model.scale.date(atY: point.y)), isNew: true)
                        }
                    )
                }
                .onAppear { adopt(size) }
                .onChange(of: size) { _, updated in adopt(updated) }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Masthead(
                    whereabouts: whereabouts,
                    age: model.age(at: model.scale.centre),
                    onMenu: { sheet = .menu }
                )
                .modifier(MeasureEdge(key: ChromeTopKey.self) { $0.maxY })

                Spacer(minLength: 0)

                ControlRail(
                    active: model.activeStep,
                    onStep: { model.go(to: $0); nudge() },
                    onNow: { model.goToNow(); nudge() },
                    onZoom: { model.zoom(by: $0, around: model.height / 2) },
                    onNew: { sheet = .edit(newEvent(at: model.scale.centre), isNew: true) }
                )
                .modifier(MeasureEdge(key: ChromeBottomKey.self) { $0.minY })
            }
        }
        .background(Theme.ground)
        .preferredColorScheme(.dark)
        .onPreferenceChange(ChromeTopKey.self) { edge in
            Task { @MainActor in model.chromeTopY = edge + 8 }
        }
        .onPreferenceChange(ChromeBottomKey.self) { edge in
            Task { @MainActor in model.chromeBottomY = edge - 8 }
        }
        .sheet(item: $sheet) { active in
            switch active {
            case .detail(let event):
                EventDetailSheet(
                    event: event,
                    age: model.age(at: event.start),
                    calendar: model.calendar,
                    onEdit: { sheet = .edit(event, isNew: false) },
                    onClose: { sheet = nil }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)

            case .edit(let event, let isNew):
                EventEditSheet(
                    event: event,
                    isNew: isNew,
                    onSave: { saved in
                        model.save(saved)
                        sheet = nil
                        nudge()
                    },
                    onDelete: isNew ? nil : {
                        model.delete(event)
                        sheet = nil
                    },
                    onCancel: { sheet = nil }
                )

            case .menu:
                MenuSheet(
                    jumpTo: model.scale.centre,
                    onJump: { date in
                        model.glide(to: date, pointsPerSecond: exp(model.logScale), duration: 0.6)
                        sheet = nil
                        nudge()
                    },
                    onReset: {
                        model.resetToSample()
                        sheet = nil
                        nudge()
                    },
                    onClose: { sheet = nil }
                )
            }
        }
    }

    private var whereabouts: Whereabouts {
        Whereabouts.describe(scale: model.scale, calendar: model.calendar)
    }

    private var accessibilityValue: String {
        let now = whereabouts
        return "\(now.headline), showing \(now.spanWords)"
    }

    private func adopt(_ size: CGSize) {
        model.size = size
        model.height = size.height
    }

    /// A new thing lands where you are looking, at a sensible grain: to the
    /// nearest quarter hour when the hours are visible, at midday when they
    /// are not, and as a milestone when you are looking at whole decades.
    private func newEvent(at date: Date) -> Event {
        let calendar = model.calendar
        let span = model.scale.span
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if span > 3 * 86400 {
            parts.hour = 12
            parts.minute = 0
        } else {
            let quarter = Int((Double(parts.minute ?? 0) / 15).rounded()) * 15
            if quarter >= 60 {
                parts.hour = (parts.hour ?? 0) + 1
                parts.minute = 0
            } else {
                parts.minute = quarter
            }
        }
        let start = calendar.date(from: parts) ?? date
        let far = span > 60 * 86400
        return Event(
            title: "",
            start: start,
            duration: far ? 0 : 3600,
            category: .life,
            weight: far ? .milestone : .worthRemembering
        )
    }

    /// Motion started from a button still needs the display link running.
    private func nudge() {
        #if os(iOS)
        DisplayLinkPump.shared.run(model)
        #endif
    }
}
