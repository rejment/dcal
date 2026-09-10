// The whole screen: a canvas, a transparent layer of gesture recognisers,
// and two pieces of floating chrome.

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

public struct DcalRootView: View {
    @State private var model = TimelineModel()
    @State private var sheet: ActiveSheet?

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let insets = proxy.safeAreaInsets
            let layout = model.layout(for: size)
            let whereabouts = Whereabouts.describe(scale: model.scale, calendar: model.calendar)

            ZStack {
                TimelineCanvas(layout: layout)
                    .accessibilityElement()
                    .accessibilityLabel("Timeline")
                    .accessibilityValue("\(whereabouts.headline), showing \(whereabouts.spanWords)")
                    .accessibilityHint("Swipe up or down to zoom")
                    .accessibilityAdjustableAction { direction in
                        model.zoom(by: direction == .increment ? 1.8 : 1 / 1.8, around: size.height / 2)
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

                VStack(spacing: 0) {
                    Masthead(
                        whereabouts: whereabouts,
                        age: model.age(at: model.scale.centre),
                        onMenu: { sheet = .menu }
                    )
                    .padding(.top, insets.top)
                    Spacer(minLength: 0)
                    ControlRail(
                        active: model.activeStep,
                        onStep: { model.go(to: $0); nudge() },
                        onNow: { model.goToNow(); nudge() },
                        onZoom: { model.zoom(by: $0, around: size.height / 2) },
                        onNew: { sheet = .edit(newEvent(at: model.scale.centre), isNew: true) }
                    )
                    .padding(.bottom, insets.bottom)
                }
            }
            .onAppear { measure(size: size, insets: insets) }
            .onChange(of: size) { measure(size: size, insets: insets) }
        }
        .background(Theme.ground)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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

    /// The chrome floats over the timeline, so the ruler and the labels need
    /// to know how much of the top and bottom is spoken for.
    private func measure(size: CGSize, insets: EdgeInsets) {
        model.size = size
        model.height = size.height
        model.chromeTop = insets.top + 96
        model.chromeBottom = insets.bottom + 112
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
