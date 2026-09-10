// Drawing one prepared frame. No decisions are taken here - TimelineLayout
// has already made them all - so this file stays a straight transcription of
// the layout into paint.

import DcalKit
import SwiftUI

struct TimelineCanvas: View {
    let layout: TimelineLayout

    var body: some View {
        // No .drawingGroup() here. A Canvas already draws into one layer, and
        // wrapping it rasterises into an offscreen buffer that snaps glyphs to
        // its own pixel grid - so while the timeline scrolls, text steps in
        // whole pixels against everything else moving smoothly, then settles
        // when the redraws stop.
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            draw(&context, size: size)
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let metrics = layout.metrics
        let whole = Path(CGRect(origin: .zero, size: size))

        context.fill(whole, with: .color(Theme.ground))

        // The ground is the data: an ambient wash across the whole width, and
        // the same colour at full strength inside the ribbon, which acts as
        // the key to it.
        let ground = GraphicsContext.Shading.linearGradient(
            Gradient(stops: layout.groundStops.map {
                Gradient.Stop(color: Color(rgb: $0.colour), location: $0.location)
            }),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        )
        context.opacity = 0.5
        context.fill(whole, with: ground)
        context.opacity = 1
        context.fill(Path(metrics.ribbon), with: ground)

        for band in layout.bands {
            context.fill(Path(band.rect), with: .color(.white.opacity(0.028)))
        }

        // One path per opacity bucket rather than one per line: a lifetime on
        // screen is several hundred lines, and they are all the same colour.
        let buckets = Dictionary(grouping: layout.grid) { Int($0.opacity * 400) }
        for (bucket, lines) in buckets {
            var path = Path()
            for line in lines {
                path.move(to: CGPoint(x: metrics.ribbon.maxX, y: line.y))
                path.addLine(to: CGPoint(x: size.width, y: line.y))
            }
            context.stroke(
                path,
                with: .color(Color(hex: 0xC6DCFF, opacity: Double(bucket) / 400)),
                lineWidth: 1
            )
        }

        var ribbonEdges = Path()
        ribbonEdges.move(to: CGPoint(x: metrics.ribbon.minX + 0.5, y: 0))
        ribbonEdges.addLine(to: CGPoint(x: metrics.ribbon.minX + 0.5, y: size.height))
        ribbonEdges.move(to: CGPoint(x: metrics.ribbon.maxX - 0.5, y: 0))
        ribbonEdges.addLine(to: CGPoint(x: metrics.ribbon.maxX - 0.5, y: size.height))
        context.stroke(ribbonEdges, with: .color(.black.opacity(0.45)), lineWidth: 1)

        drawRuler(&context, size: size)

        for notch in layout.notches {
            context.opacity = notch.opacity
            context.fill(Path(notch.rect), with: .color(Color(rgb: notch.colour)))
        }
        context.opacity = 1

        if layout.scheduleOpacity > 0.005 {
            context.opacity = layout.scheduleOpacity
            drawBlocks(&context)
            context.opacity = 1
        }
        if layout.scheduleOpacity < 0.995 {
            context.opacity = 1 - layout.scheduleOpacity
            drawLandmarks(&context, size: size)
            context.opacity = 1
        }

        drawNow(&context, size: size)
    }

    // MARK: - Ruler

    private func drawRuler(_ context: inout GraphicsContext, size: CGSize) {
        let x = layout.metrics.gutter - 8
        for tick in layout.ticks {
            let resolved: GraphicsContext.ResolvedText
            if tick.isMajor {
                resolved = context.resolve(Text(tick.text)
                    .font(.system(size: size.width < 420 ? 12 : 12.5, weight: .semibold))
                    .foregroundStyle(tick.isWeekend ? Theme.amber.opacity(0.82) : Theme.chalk.opacity(0.92)))
            } else {
                resolved = context.resolve(Text(tick.text)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(hex: 0xBECDE8, opacity: 0.42)))
            }
            context.draw(resolved, at: CGPoint(x: x, y: tick.y), anchor: .trailing)
        }
    }

    // MARK: - Close in: a calendar day

    private func drawBlocks(_ context: inout GraphicsContext) {
        for block in layout.blocks {
            let colour = Color(rgb: block.event.category.rgb)
            let frame = block.frame

            if block.isStretch {
                let shape = Path(roundedRect: frame, cornerRadius: 9, style: .continuous)
                context.fill(shape, with: .color(colour.opacity(0.16)))
                context.stroke(shape.strokedPath(.init(lineWidth: 1)), with: .color(colour.opacity(0.4)))
                context.fill(
                    Path(roundedRect: CGRect(x: frame.minX, y: frame.minY + 2,
                                             width: 3.5, height: max(0, frame.height - 4)),
                         cornerRadius: 2),
                    with: .color(colour)
                )
            } else {
                context.fill(
                    Path(ellipseIn: CGRect(x: frame.minX + 3.6, y: frame.midY - 3.4, width: 6.8, height: 6.8)),
                    with: .color(colour)
                )
            }

            // Clip per block so a long title cannot run into the next lane.
            context.drawLayer { layer in
                layer.clip(to: Path(frame.insetBy(dx: 0, dy: -1)))
                if block.isStretch {
                    let title = layer.resolve(Text(block.event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xEFF3FB)))
                    if frame.height >= 40 {
                        layer.draw(title, at: CGPoint(x: frame.minX + 12, y: frame.minY + 16), anchor: .leading)
                        let time = layer.resolve(Text(block.timeText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color(hex: 0xC6D4EC, opacity: 0.72)))
                        layer.draw(time, at: CGPoint(x: frame.minX + 12, y: frame.minY + 32), anchor: .leading)
                    } else {
                        layer.draw(title, at: CGPoint(x: frame.minX + 12, y: frame.midY), anchor: .leading)
                    }
                } else {
                    let time = layer.resolve(Text(block.timeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: 0xA0B0CD, opacity: 0.6)))
                    layer.draw(time, at: CGPoint(x: frame.maxX - 2, y: frame.midY), anchor: .trailing)
                    let title = layer.resolve(Text(block.event.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(hex: 0xCEDAF0, opacity: 0.78)))
                    layer.draw(title, at: CGPoint(x: frame.minX + 17, y: frame.midY), anchor: .leading)
                }
            }
        }
    }

    // MARK: - Far out: a map of milestones

    private func drawLandmarks(_ context: inout GraphicsContext, size: CGSize) {
        let dotX = layout.metrics.ribbon.maxX + 9
        let textX = dotX + 12
        let showsAge = layout.landmarks.contains { $0.ageText != nil }
        let textRight = size.width - (showsAge ? 62 : 14)

        for landmark in layout.landmarks {
            let event = landmark.event
            let colour = Color(rgb: event.category.rgb)

            if let bracket = landmark.bracket {
                context.opacity = (1 - layout.scheduleOpacity) * 0.55
                context.fill(
                    Path(roundedRect: CGRect(x: dotX - 2.5, y: bracket.lowerBound,
                                             width: 5, height: bracket.upperBound - bracket.lowerBound),
                         cornerRadius: 2.5),
                    with: .color(colour)
                )
                context.opacity = 1 - layout.scheduleOpacity
            }

            let radius: CGFloat = switch event.weight {
            case .milestone: 4.6
            case .notable: 3.6
            default: 2.6
            }
            context.fill(
                Path(ellipseIn: CGRect(x: dotX - radius, y: landmark.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(colour)
            )
            if event.weight == .milestone {
                context.stroke(
                    Path(ellipseIn: CGRect(x: dotX - 8.5, y: landmark.y - 8.5, width: 17, height: 17)),
                    with: .color(colour.opacity(0.35)),
                    lineWidth: 1.2
                )
            }
        }

        // All the titles share one clipped column, so none of them can reach
        // the age rail on the right.
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: textX, y: 0, width: max(0, textRight - textX), height: size.height)))
            for landmark in layout.landmarks {
                let (size, weight, colour): (CGFloat, Font.Weight, Color) = switch landmark.event.weight {
                case .milestone: (15.5, .semibold, Color(hex: 0xF3F6FC))
                case .notable: (13.5, .semibold, Color(hex: 0xE8EFFA, opacity: 0.9))
                default: (12.5, .medium, Color(hex: 0xC8D4E8, opacity: 0.72))
                }
                let title = layer.resolve(Text(landmark.event.title)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(colour))
                layer.draw(title, at: CGPoint(x: textX, y: landmark.y), anchor: .leading)
            }
        }

        for landmark in layout.landmarks {
            guard let ageText = landmark.ageText else { continue }
            let age = context.resolve(Text(ageText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.amber.opacity(0.62)))
            context.draw(age, at: CGPoint(x: size.width - 14, y: landmark.y), anchor: .trailing)
        }
    }

    // MARK: - Now

    private func drawNow(_ context: inout GraphicsContext, size: CGSize) {
        guard let y = layout.nowY else { return }
        let metrics = layout.metrics

        var line = Path()
        line.move(to: CGPoint(x: metrics.ribbon.maxX, y: y))
        line.addLine(to: CGPoint(x: size.width - 10, y: y))
        context.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 1.4)

        context.fill(
            Path(ellipseIn: CGRect(x: metrics.ribbon.midX - 4.2, y: y - 4.2, width: 8.4, height: 8.4)),
            with: .color(.white)
        )
        let label = context.resolve(Text("now")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75)))
        context.draw(label, at: CGPoint(x: size.width - 10, y: y - 9), anchor: .bottomTrailing)
    }
}
