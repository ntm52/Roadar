import SwiftUI

import CoreLocation
import MapKit

/// Shared framing policy for phone and future CarPlay map surfaces.
struct ForwardMapCamera {
    private(set) var drivingCourse: CLLocationDirection?

    mutating func camera(for fix: CLLocation, heading: CLLocationDirection?,
                         driving: Bool, forward: Bool) -> MapCamera {
        if driving && fix.speed > 1.5 && (0..<360).contains(fix.course) {
            drivingCourse = fix.course
        }
        // A stopped vehicle keeps its direction; the phone compass is only used on foot.
        let bearing = driving ? drivingCourse : heading
        let distance = driving ? min(2400, max(700, max(0, fix.speed) * 65)) : 550
        let direction = forward ? bearing ?? 0 : 0
        // Initial framing also stays below center when direction is unavailable.
        // The phone refines this with its measured, unobstructed map viewport.
        let center = Self.offset(fix.coordinate, meters: distance * 0.14, bearing: direction)
        return MapCamera(centerCoordinate: center, distance: distance, heading: direction, pitch: 0)
    }

    static func anchor(in size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> CGPoint {
        let availableHeight = max(0, size.height - topInset - bottomInset)
        return CGPoint(x: size.width / 2, y: topInset + availableHeight * 0.74)
    }

    static func offset(_ coordinate: CLLocationCoordinate2D, meters: Double,
                       bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let angularDistance = meters / 6_371_000
        let radians = Double.pi / 180
        let latitude = coordinate.latitude * radians
        let longitude = coordinate.longitude * radians
        let direction = bearing * radians
        let targetLatitude = asin(sin(latitude) * cos(angularDistance)
            + cos(latitude) * sin(angularDistance) * cos(direction))
        let targetLongitude = longitude + atan2(sin(direction) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(targetLatitude))
        return CLLocationCoordinate2D(latitude: targetLatitude / radians,
            longitude: (targetLongitude / radians + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
}
