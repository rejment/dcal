// Looking at the photos: a few small ones in the list, all of them large in
// the editor.
//
// Nothing here is loaded until it is on screen, and thumbnails are requested
// at the size they will be drawn - a day with three hundred photos in it
// should cost no more to scroll past than one with four.

import DcalKit
import SwiftUI

#if os(iOS)
import Photos
import UIKit

/// One photo, fetched at the size it is about to be drawn.
struct PhotoImage: View {
    let identifier: String
    let target: CGSize
    var fill = true

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Theme.panelRaised
            }
        }
        .task(id: identifier) { image = await load() }
    }

    /// One request, one answer. `.opportunistic` calls back twice - a blurry
    /// version first - which a checked continuation cannot survive.
    private func load() async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = fill ? .fastFormat : .highQualityFormat
        options.resizeMode = .fast
        // A library kept in iCloud has no full-size copy on the phone. This
        // fetches one; nothing is ever sent the other way.
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            var answered = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFill, options: options
            ) { image, _ in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: image)
            }
        }
    }
}

/// The handful under a row in the list.
struct PhotoStrip: View {
    let identifiers: [String]
    var side: CGFloat = 54

    var body: some View {
        HStack(spacing: 4) {
            ForEach(identifiers, id: \.self) { identifier in
                PhotoImage(identifier: identifier, target: CGSize(width: side * 3, height: side * 3))
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

/// Everything from the day, or from the fortnight, scrolling sideways.
struct PhotoGallery: View {
    let range: ClosedRange<Date>
    var height: CGFloat = 220

    @State private var identifiers: [String] = []
    @State private var viewing: Int?

    var body: some View {
        Group {
            if identifiers.isEmpty {
                Text("Looking for the photos…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(identifiers.enumerated()), id: \.element) { index, identifier in
                            Button { viewing = index } label: {
                                PhotoImage(
                                    identifier: identifier,
                                    target: CGSize(width: height * 2, height: height * 2)
                                )
                                .frame(width: height * 0.78, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: height + 4)
            }
        }
        .task {
            identifiers = await PhotoLibrary.identifiers(in: range)
        }
        .fullScreenCover(item: Binding(
            get: { viewing.map(Viewing.init) },
            set: { viewing = $0?.index }
        )) { start in
            PhotoViewer(identifiers: identifiers, start: start.index) { viewing = nil }
        }
    }

    private struct Viewing: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

/// Full screen, one at a time, swipe to move along.
private struct PhotoViewer: View {
    let identifiers: [String]
    let start: Int
    let onClose: () -> Void

    @State private var index: Int

    init(identifiers: [String], start: Int, onClose: @escaping () -> Void) {
        self.identifiers = identifiers
        self.start = start
        self.onClose = onClose
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(identifiers.enumerated()), id: \.offset) { position, identifier in
                    PhotoImage(
                        identifier: identifier,
                        target: PHImageManagerMaximumSize,
                        fill: false
                    )
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                Text("\(index + 1) of \(identifiers.count)")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Done", action: onClose)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
}

#else

struct PhotoStrip: View {
    let identifiers: [String]
    var side: CGFloat = 54
    var body: some View { Color.clear.frame(height: side) }
}

struct PhotoGallery: View {
    let range: ClosedRange<Date>
    var height: CGFloat = 220
    var body: some View { Color.clear.frame(height: height) }
}

#endif
