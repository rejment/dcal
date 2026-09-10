// Touch handling, in UIKit rather than SwiftUI gestures.
//
// A timeline is a scroll view that happens to be drawn: it needs a pan that
// keeps its velocity, a pinch that stays anchored between the fingers while
// the other hand is still moving, and a fling that decelerates the way every
// other list on the phone does. UIKit's recognisers give all three; the
// SwiftUI equivalents drop velocity and fight each other over which one owns
// a two-finger drag.
//
// Motion runs off a display link, so it steps at whatever the screen does -
// 120Hz on a ProMotion phone - and stops the moment there is nothing moving.

import DcalKit
import SwiftUI

#if os(iOS)
import UIKit

struct TimelineGestures: UIViewRepresentable {
    let model: TimelineModel
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onTap: onTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIView {
        let view = TouchView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch))
        pinch.delegate = coordinator

        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap))
        tap.require(toFail: doubleTap)

        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleHold))
        hold.minimumPressDuration = 0.5
        hold.delegate = coordinator

        for recogniser in [pan, pinch, doubleTap, tap, hold] as [UIGestureRecognizer] {
            view.addGestureRecognizer(recogniser)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
    }

    /// A bare UIView would let a touch fall through to whatever is behind it
    /// on the first tap after a fling; owning the touch keeps the timeline in
    /// charge of its own gestures.
    private final class TouchView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: TimelineModel
        var onTap: (CGPoint) -> Void
        var onLongPress: (CGPoint) -> Void

        private var lastPanY: CGFloat = 0
        private var lastPinchScale: CGFloat = 1
        private var lastPinchY: CGFloat = 0
        private let bump = UIImpactFeedbackGenerator(style: .light)

        init(model: TimelineModel, onTap: @escaping (CGPoint) -> Void, onLongPress: @escaping (CGPoint) -> Void) {
            self.model = model
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        // Pinch and pan have to run together: a two-finger gesture is almost
        // never purely one or the other.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handlePan(_ recogniser: UIPanGestureRecognizer) {
            let y = recogniser.translation(in: recogniser.view).y
            switch recogniser.state {
            case .began:
                model.stopMotion()
                lastPanY = y
            case .changed:
                model.pan(byPoints: y - lastPanY)
                lastPanY = y
            case .ended, .cancelled:
                model.fling(velocityPoints: recogniser.velocity(in: recogniser.view).y)
                startDisplayLink()
            default:
                break
            }
        }

        @objc func handlePinch(_ recogniser: UIPinchGestureRecognizer) {
            let midpoint = recogniser.location(in: recogniser.view).y
            switch recogniser.state {
            case .began:
                model.stopMotion()
                lastPinchScale = recogniser.scale
                lastPinchY = midpoint
            case .changed:
                guard recogniser.numberOfTouches >= 2 else {
                    lastPinchY = midpoint
                    lastPinchScale = recogniser.scale
                    return
                }
                model.zoom(by: Double(recogniser.scale / lastPinchScale), around: midpoint)
                // Two fingers travelling together still pan.
                model.pan(byPoints: midpoint - lastPinchY)
                lastPinchScale = recogniser.scale
                lastPinchY = midpoint
            default:
                break
            }
        }

        @objc func handleTap(_ recogniser: UITapGestureRecognizer) {
            model.stopMotion()
            onTap(recogniser.location(in: recogniser.view))
        }

        @objc func handleDoubleTap(_ recogniser: UITapGestureRecognizer) {
            model.stopMotion()
            bump.impactOccurred()
            let point = recogniser.location(in: recogniser.view)
            let anchor = model.scale.date(atY: point.y)
            model.glide(
                to: anchor,
                pointsPerSecond: exp(model.logScale) * 3.2,
                duration: 0.42
            )
            startDisplayLink()
        }

        @objc func handleHold(_ recogniser: UILongPressGestureRecognizer) {
            guard recogniser.state == .began else { return }
            model.stopMotion()
            bump.impactOccurred()
            onLongPress(recogniser.location(in: recogniser.view))
        }

        // MARK: - Motion

        func startDisplayLink() {
            DisplayLinkPump.shared.run(model)
        }

        func stopDisplayLink() {
            DisplayLinkPump.shared.stop()
        }
    }
}

#else

/// macOS builds exist only so `swift build` type-checks the interface without
/// Xcode. Nothing here is ever run.
struct TimelineGestures: View {
    let model: TimelineModel
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void

    var body: some View { Color.clear }
}

#endif
