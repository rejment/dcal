// The zoom transform, the packing, and the label survival rule.

import CoreGraphics
import Foundation
import Testing
@testable import DcalKit

@Test func screenPositionsRoundTrip() {
    let scale = TimeScale(
        centre: Fixture.date(2026, 9, 10, 12),
        pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: 15 * 3600),
        height: 800
    )
    #expect(abs(scale.y(for: scale.centre) - 400) < 1e-6)
    for y in stride(from: CGFloat(0), through: 800, by: 137) {
        #expect(abs(scale.y(for: scale.date(atY: y)) - y) < 1e-6)
    }
    #expect(abs(scale.span - 15 * 3600) < 1e-6)
}

@Test func zoomingKeepsTheInstantUnderYourFingers() {
    let scale = TimeScale(
        centre: Fixture.date(2026, 9, 10, 12),
        pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: 5 * 86400),
        height: 800
    )
    for anchorY in [CGFloat(90), 400, 720] {
        let pinned = scale.date(atY: anchorY)
        for factor in [0.4, 1.7, 6.0] {
            let zoomed = scale.zoomed(by: factor, around: anchorY)
            #expect(abs(zoomed.date(atY: anchorY).timeIntervalSince(pinned)) < 0.5)
            #expect(abs(zoomed.pointsPerSecond / scale.pointsPerSecond - factor) < 1e-9)
        }
    }
}

@Test func zoomStopsAtACoupleOfHoursAndAtALifetime() {
    let scale = TimeScale(
        centre: Fixture.date(2026, 9, 10, 12),
        pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: 86400),
        height: 800
    )
    let tooFarIn = scale.zoomed(by: 1e6, around: 400)
    #expect(abs(tooFarIn.span - TimeScale.shortestSpan) < 1)

    let tooFarOut = scale.zoomed(by: 1e-9, around: 400)
    #expect(abs(tooFarOut.span - TimeScale.longestSpan) < 1)
}

@Test func panningIsClampedToTheYearsTheAppKnowsAbout() {
    let scale = TimeScale(
        centre: Fixture.date(2026, 9, 10),
        pointsPerSecond: TimeScale.pointsPerSecond(height: 800, span: 86400),
        height: 800
    )
    #expect(scale.panned(byPoints: 1e12).centre == TimeScale.earliest)
    #expect(scale.panned(byPoints: -1e12).centre == TimeScale.latest)
}

@Test func overlappingThingsGetLanesAndSeparateOnesDoNot() {
    let packed = Layout.packLanes([0...10, 5...15, 20...30])
    #expect(packed[0] == (lane: 0, lanes: 2))
    #expect(packed[1] == (lane: 1, lanes: 2))
    #expect(packed[2] == (lane: 0, lanes: 1))
}

@Test func aBusyMorningDoesNotNarrowAQuietAfternoon() {
    // Three at once, then one alone: the lone one keeps the full width.
    let packed = Layout.packLanes([0...30, 2...28, 4...26, 100...120])
    #expect(packed[0].lanes == 3)
    #expect(packed[3] == (lane: 0, lanes: 1))
    #expect(Set([packed[0].lane, packed[1].lane, packed[2].lane]) == [0, 1, 2])
}

@Test func packingIsIndependentOfInputOrder() {
    let forwards = Layout.packLanes([0...10, 5...15, 20...30])
    let backwards = Layout.packLanes([20...30, 5...15, 0...10])
    #expect(forwards[0].lanes == backwards[2].lanes)
    #expect(forwards[2].lanes == backwards[0].lanes)
}

@Test func labelsSurviveByWeightAsYouZoomOut() {
    let day: TimeInterval = 86400
    let year: TimeInterval = 31_556_952
    #expect(Layout.minimumWeight(forSpan: 3 * day) == .everyday)
    #expect(Layout.minimumWeight(forSpan: 30 * day) == .worthRemembering)
    #expect(Layout.minimumWeight(forSpan: 2 * year) == .notable)
    #expect(Layout.minimumWeight(forSpan: 60 * year) == .milestone)
}

@Test func aHeavierLabelWinsTheSpaceAndTheLighterOneIsDropped() {
    let candidates = [
        Layout.LabelCandidate(index: 0, y: 100, weight: .everyday),
        Layout.LabelCandidate(index: 1, y: 110, weight: .milestone),
        Layout.LabelCandidate(index: 2, y: 300, weight: .notable),
    ]
    let placed = Layout.placeLabels(
        candidates, gap: { $0 == .milestone ? 27 : 23 }, centreY: 400
    ).sorted()
    // The milestone at 110 pushes the everyday label at 100 out entirely,
    // rather than nudging it to a moment it does not belong to.
    #expect(placed == [1, 2])
}

@Test func amongEqualsTheOnesNearestTheMiddleWin() {
    let candidates = (0..<6).map {
        Layout.LabelCandidate(index: $0, y: CGFloat(100 + $0 * 10), weight: .notable)
    }
    let placed = Layout.placeLabels(candidates, gap: { _ in 25 }, centreY: 150)
    #expect(placed.first == 5)  // y = 150, dead centre
}
