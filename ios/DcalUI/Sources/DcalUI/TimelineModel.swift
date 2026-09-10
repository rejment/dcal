// Where you are looking, what you are looking at, and how it moves.
//
// The view state is two plain Doubles rather than a TimeScale, because both
// have to be interpolated frame by frame - a fling decays through one, a
// pinch-to-a-preset tweens through the other - and a Double is the only thing
// an animation can meaningfully step.

import DcalKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class TimelineModel {
    public private(set) var lifeline: Lifeline
    /// Seconds since 1970 at the middle of the view.
    public var centreEpoch: Double
    /// Natural log of points-per-second, so zooming is linear in this number
    /// and a tween through it feels even at every scale.
    public var logScale: Double

    var height: CGFloat = 800
    var size: CGSize = CGSize(width: 390, height: 800)
    /// Measured screen positions of the floating chrome, so the ruler can
    /// stop clear of it. Absolute rather than inset, which keeps them correct
    /// even if they are measured before the canvas reports its height.
    var chromeTopY: CGFloat = 104
    var chromeBottomY: CGFloat = 690

    let tickCalendar = TickCalendar.standard()
    private let store: LifelineStore?

    /// Decaying pan, in seconds-of-timeline per second of real time.
    private var flingVelocity: Double = 0
    private var tween: Tween?

    private struct Tween {
        let fromCentre: Double, toCentre: Double
        let fromLog: Double, toLog: Double
        let duration: Double
        var elapsed: Double = 0
    }

    public init(store: LifelineStore? = try? LifelineStore(url: LifelineStore.defaultURL())) {
        self.store = store
        let calendar = TickCalendar.standard().calendar
        let loaded = (try? store?.load()) ?? nil
        lifeline = loaded ?? SampleLifeline.make(calendar: calendar)
        centreEpoch = Date().timeIntervalSince1970
        logScale = log(TimeScale.pointsPerSecond(height: 800, span: 15 * 3600))
        if loaded == nil { persist() }
    }

    // MARK: - Reading the view

    public var scale: TimeScale {
        TimeScale(
            centre: Date(timeIntervalSince1970: centreEpoch),
            pointsPerSecond: exp(logScale),
            height: height
        )
    }

    var calendar: Calendar { tickCalendar.calendar }

    func layout(for size: CGSize) -> TimelineLayout {
        TimelineLayoutBuilder.build(
            scale: TimeScale(
                centre: Date(timeIntervalSince1970: centreEpoch),
                pointsPerSecond: exp(logScale),
                height: size.height
            ),
            size: size,
            chromeTop: chromeTopY,
            chromeBottom: max(0, size.height - chromeBottomY),
            lifeline: lifeline,
            tickCalendar: tickCalendar,
            now: Date()
        )
    }

    func age(at date: Date) -> Int? { lifeline.age(at: date, calendar: calendar) }

    // MARK: - Moving

    func apply(_ next: TimeScale) {
        let clamped = next.clamped()
        centreEpoch = clamped.centre.timeIntervalSince1970
        logScale = log(clamped.pointsPerSecond)
    }

    func pan(byPoints dy: CGFloat) {
        stopMotion()
        apply(scale.panned(byPoints: dy))
    }

    func zoom(by factor: Double, around y: CGFloat) {
        stopMotion()
        apply(scale.zoomed(by: factor, around: y))
    }

    /// `velocity` is in points per second, the way a pan recogniser reports it.
    func fling(velocityPoints: CGFloat) {
        tween = nil
        flingVelocity = -Double(velocityPoints) / exp(logScale)
    }

    func stopMotion() {
        flingVelocity = 0
        tween = nil
    }

    var isMoving: Bool { tween != nil || abs(flingVelocity) > 0 }

    func glide(to centre: Date, pointsPerSecond: Double, duration: Double = 0.5) {
        flingVelocity = 0
        let limits = TimeScale.scaleLimits(height: height)
        let target = TimeScale(
            centre: centre,
            pointsPerSecond: Curve.clamp(pointsPerSecond, limits.lowerBound, limits.upperBound),
            height: height
        ).clamped()
        tween = Tween(
            fromCentre: centreEpoch,
            toCentre: target.centre.timeIntervalSince1970,
            fromLog: logScale,
            toLog: log(target.pointsPerSecond),
            duration: duration
        )
    }

    /// One frame of motion. Returns false once there is nothing left to do,
    /// which is the display link's cue to stop and give the CPU back.
    func step(_ dt: Double) -> Bool {
        if var running = tween {
            running.elapsed += dt
            let t = Curve.clamp(running.elapsed / running.duration, 0, 1)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            centreEpoch = Curve.lerp(running.fromCentre, running.toCentre, eased)
            logScale = Curve.lerp(running.fromLog, running.toLog, eased)
            if t >= 1 {
                tween = nil
            } else {
                tween = running
            }
            clampInPlace()
            return tween != nil
        }

        guard flingVelocity != 0 else { return false }
        centreEpoch += flingVelocity * dt
        // Matches UIScrollView's deceleration closely enough that a flick
        // ending on the timeline feels like a flick ending on a list.
        flingVelocity *= pow(0.998, dt * 1000)
        clampInPlace()
        // Below about twenty points a second the movement is invisible.
        if abs(flingVelocity) * exp(logScale) < 20 {
            flingVelocity = 0
            return false
        }
        return true
    }

    private func clampInPlace() {
        let clamped = scale.clamped()
        centreEpoch = clamped.centre.timeIntervalSince1970
        logScale = log(clamped.pointsPerSecond)
    }

    // MARK: - Zoom steps

    func window(for step: ZoomStep) -> (centre: Date, pointsPerSecond: Double) {
        if let span = step.span {
            return (
                Date(timeIntervalSince1970: centreEpoch),
                TimeScale.pointsPerSecond(height: height, span: span)
            )
        }
        // A life: from a little before the beginning to a few years past today,
        // with the birth clear of the header rather than tucked under it.
        let birth = lifeline.birth ?? Date().addingTimeInterval(-40 * 31_556_952)
        let far = Date().addingTimeInterval(6 * 31_556_952)
        let reach = far.timeIntervalSince(birth)
        let start = birth.addingTimeInterval(-0.17 * reach)
        return (
            Date(timeIntervalSince1970: (start.timeIntervalSince1970 + far.timeIntervalSince1970) / 2),
            TimeScale.pointsPerSecond(height: height, span: far.timeIntervalSince(start))
        )
    }

    var activeStep: ZoomStep? {
        let span = scale.span
        var best: ZoomStep?
        var closest = Double.greatestFiniteMagnitude
        for step in ZoomStep.allCases {
            let target = step.span ?? (Double(height) / window(for: step).pointsPerSecond)
            let distance = abs(log(span / target))
            if distance < closest {
                closest = distance
                best = step
            }
        }
        return closest < 0.62 ? best : nil
    }

    func go(to step: ZoomStep) {
        let target = window(for: step)
        glide(to: target.centre, pointsPerSecond: target.pointsPerSecond, duration: 0.55)
    }

    func goToNow() {
        let span = scale.span
        let pps = span > 90 * 86400
            ? TimeScale.pointsPerSecond(height: height, span: 15 * 3600)
            : exp(logScale)
        glide(to: Date(), pointsPerSecond: pps, duration: 0.6)
    }

    // MARK: - Editing

    func save(_ event: Event) {
        lifeline.upsert(event)
        persist()
        glide(to: event.anchor, pointsPerSecond: exp(logScale), duration: 0.4)
    }

    func delete(_ event: Event) {
        lifeline.remove(id: event.id)
        persist()
    }

    // MARK: - Import and export

    var document: LifelineDocument { LifelineDocument(calendar: calendar) }

    /// Writes the lifeline to a file in the temporary directory and hands
    /// back its URL, ready for the share sheet.
    func writeExport() throws -> URL {
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        let stamp = String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 1, parts.day ?? 1
        )
        let url = URL.temporaryDirectory.appending(path: "dcal-lifeline-\(stamp).json")
        try document.text(for: lifeline).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func read(fileAt url: URL) throws -> Lifeline {
        // A file coming from Files or iCloud arrives security-scoped.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try document.lifeline(from: text)
    }

    func replace(with incoming: Lifeline) {
        lifeline = incoming
        persist()
        go(to: .life)
    }

    /// Same id means the same event, so re-importing an edited export updates
    /// rather than duplicates.
    func add(_ incoming: Lifeline) {
        for event in incoming.events { lifeline.upsert(event) }
        persist()
    }

    func resetToSample() {
        lifeline = SampleLifeline.make(calendar: calendar)
        persist()
        goToNow()
    }

    private func persist() {
        try? store?.save(lifeline)
    }
}
