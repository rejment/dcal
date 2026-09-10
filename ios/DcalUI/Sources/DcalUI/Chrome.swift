// The two floating pieces of chrome: where you are, and how to move.

import DcalKit
import SwiftUI

struct Masthead: View {
    let whereabouts: Whereabouts
    let age: Int?
    let onMenu: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: -2) {
                        if let context = whereabouts.context {
                            Text(context)
                                .font(Theme.display(26, weight: .light))
                                .foregroundStyle(Theme.chalk.opacity(0.85))
                        }
                        Text(whereabouts.headline)
                            .font(Theme.display(30, weight: .semibold))
                            .foregroundStyle(Theme.chalk)
                    }
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("Showing \(whereabouts.spanWords)")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.fog)
                        if let age {
                            Text("age \(age)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.amber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.35)))
                        }
                    }
                }
                Spacer(minLength: 46)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Theme.ground.opacity(0.94), Theme.ground.opacity(0.75), Theme.ground.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.panelRaised.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.edge))
            }
            .foregroundStyle(Theme.chalk)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .accessibilityLabel("More actions")
        }
    }
}

struct ControlRail: View {
    let active: ZoomStep?
    let onStep: (ZoomStep) -> Void
    let onNow: () -> Void
    let onZoom: (Double) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ZoomStep.allCases) { step in
                        Button(step.label) { onStep(step) }
                            .buttonStyle(RailButtonStyle(selected: active == step))
                            .accessibilityAddTraits(active == step ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            HStack(spacing: 8) {
                Button("Now", action: onNow)
                    .buttonStyle(RailButtonStyle())
                    .accessibilityHint("Jump to today")
                Spacer(minLength: 0)
                Button { onZoom(1 / 1.8) } label: { Image(systemName: "minus") }
                    .buttonStyle(RailButtonStyle(square: true))
                    .accessibilityLabel("Zoom out")
                Button { onZoom(1.8) } label: { Image(systemName: "plus") }
                    .buttonStyle(RailButtonStyle(square: true))
                    .accessibilityLabel("Zoom in")
                Button("New event", action: onNew)
                    .buttonStyle(RailButtonStyle(prominent: true))
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 26)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Theme.ground.opacity(0), Theme.ground.opacity(0.75), Theme.ground.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }
}
