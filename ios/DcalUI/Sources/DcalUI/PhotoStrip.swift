// A few thumbnails, so a row is something you can judge.
//
// "40 photos, a Tuesday in 2011" is not a memory. Four pictures of it usually
// are - and the difference between a wedding and a flooded kitchen is obvious
// at 54 points across.

import DcalKit
import SwiftUI

#if os(iOS)
import Photos
import UIKit

struct PhotoStrip: View {
    let identifiers: [String]
    var side: CGFloat = 54

    var body: some View {
        HStack(spacing: 4) {
            ForEach(identifiers, id: \.self) { identifier in
                Thumbnail(identifier: identifier, side: side)
            }
        }
    }

    private struct Thumbnail: View {
        let identifier: String
        let side: CGFloat
        @State private var image: UIImage?

        var body: some View {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.panelRaised)
                .frame(width: side, height: side)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .task(id: identifier) {
                    image = await thumbnail(identifier, side: side)
                }
        }
    }

    /// One request, one answer. `.opportunistic` would call back twice with a
    /// blurry version first, which a checked continuation cannot survive.
    private static func thumbnail(_ identifier: String, side: CGFloat) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        // Libraries kept in iCloud have no full-size copy on the phone. This
        // fetches a thumbnail; nothing is ever sent the other way.
        options.isNetworkAccessAllowed = true

        let target = CGSize(width: side * 3, height: side * 3)
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

#else

struct PhotoStrip: View {
    let identifiers: [String]
    var side: CGFloat = 54
    var body: some View { Color.clear.frame(height: side) }
}

#endif
