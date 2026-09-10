// One display link for the whole app.
//
// Both the gesture layer and the buttons start motion, and two display links
// stepping the same model would double every fling. This is the single
// driver: anything that starts something moving nudges it, and it switches
// itself off the moment the model says there is nothing left to do.

import DcalKit
import SwiftUI

#if os(iOS)
import UIKit

@MainActor
final class DisplayLinkPump {
    static let shared = DisplayLinkPump()

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private weak var model: TimelineModel?

    private init() {}

    func run(_ model: TimelineModel) {
        self.model = model
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        lastTimestamp = 0
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        // First frame has no previous timestamp; a long stall is clamped so a
        // backgrounded app does not resume with one enormous jump.
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(0.064, link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        guard let model, model.step(dt) else {
            stop()
            return
        }
    }
}
#endif
