// Reading the photo library, as little of it as possible.
//
// Only three fields per photo - when, where, and whether it was hearted - and
// never the image itself. Nothing is decoded, nothing is uploaded, and the
// scan works the same with the phone in aeroplane mode. The one exception is
// turning a coordinate into a place name, which asks Apple; that only happens
// for days the scan already flagged, and only when you open the list.

import DcalKit
import Foundation

enum PhotoAccess: Equatable {
    case notAsked
    case allowed
    /// You picked specific photos, so the scan only sees those.
    case limited
    case denied
}

#if os(iOS)
import CoreLocation
import Photos

enum PhotoLibrary {
    static var access: PhotoAccess {
        translate(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    static func request() async -> PhotoAccess {
        translate(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private static func translate(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .authorized: .allowed
        case .limited: .limited
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    /// Metadata only. Off the main actor, because a long life is a lot of rows.
    static func moments() async -> [PhotoMoment] {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var out: [PhotoMoment] = []
            out.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate else { return }
                out.append(PhotoMoment(
                    date: date,
                    coordinate: asset.location.map {
                        Coordinate(
                            latitude: $0.coordinate.latitude,
                            longitude: $0.coordinate.longitude
                        )
                    },
                    isFavourite: asset.isFavorite,
                    identifier: asset.localIdentifier
                ))
            }
            return out
        }.value
    }

    /// City and country, when Apple knows one. Geocoding is rate limited, so
    /// this asks for a handful at a time and gives up quietly - a trip with no
    /// name is still a trip worth showing.
    static func placeNames(for findings: [PhotoFinding], limit: Int = 40) async -> [String: String] {
        let geocoder = CLGeocoder()
        var names: [String: String] = [:]
        var asked = 0

        for finding in findings.sorted(by: { $0.score > $1.score }) {
            guard let where_ = finding.coordinate, asked < limit else { continue }
            asked += 1
            let location = CLLocation(latitude: where_.latitude, longitude: where_.longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
                continue
            }
            let town = placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea
            let country = placemark.country
            switch (town, country) {
            case let (town?, country?) where town != country: names[finding.id] = "\(town), \(country)"
            case let (town?, _): names[finding.id] = town
            case let (_, country?): names[finding.id] = country
            default: break
            }
        }
        return names
    }
}

#else

/// macOS builds exist to type-check the interface. Nothing here runs.
enum PhotoLibrary {
    static var access: PhotoAccess { .denied }
    static func request() async -> PhotoAccess { .denied }
    static func moments() async -> [PhotoMoment] { [] }
    static func placeNames(for findings: [PhotoFinding], limit: Int = 40) async -> [String: String] { [:] }
}

#endif
