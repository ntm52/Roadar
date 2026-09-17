import MapKit
import SwiftUI
import CoreLocation
import Testing
@testable import Roadar

@MainActor
struct ForwardMapCameraTests {
    private func fix(speed: Double = 12, course: Double = 90) -> CLLocation {
        CLLocation(coordinate: .init(latitude: 42.3, longitude: -83.4), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, course: course, speed: speed, timestamp: .now)
    }

    @Test func walkingFacesCompassAndLooksAhead() {
        var policy = ForwardMapCamera()
        let location = fix()
        let camera = policy.camera(for: location, heading: 0, driving: false, forward: true)
        #expect(camera.heading == 0)
        #expect(camera.centerCoordinate.latitude > location.coordinate.latitude)
        let offset = CLLocation(latitude: camera.centerCoordinate.latitude, longitude: camera.centerCoordinate.longitude)
        #expect(abs(offset.distance(from: location) - 77) < 1)
    }

    @Test func drivingKeepsCourseAtStopRegardlessOfPhoneHeading() {
        var policy = ForwardMapCamera()
        let moving = policy.camera(for: fix(), heading: 180, driving: true, forward: true)
        #expect(moving.heading == 90)
        #expect(moving.centerCoordinate.longitude > fix().coordinate.longitude)
        let stopped = policy.camera(for: fix(speed: 0, course: -1), heading: 270, driving: true, forward: true)
        #expect(stopped.heading == 90)
    }

    @Test func unknownDirectionAndNorthUpStillLookAhead() {
        var policy = ForwardMapCamera()
        let location = fix(speed: 0, course: -1)
        let unknown = policy.camera(for: location, heading: 180, driving: true, forward: true)
        #expect(unknown.centerCoordinate.latitude > location.coordinate.latitude)
        #expect(abs(unknown.centerCoordinate.longitude - location.coordinate.longitude) < 0.000001)
        let north = policy.camera(for: fix(), heading: 90, driving: false, forward: false)
        #expect(north.heading == 0)
        #expect(abs(north.centerCoordinate.longitude - location.coordinate.longitude) < 0.000001)
        #expect(north.centerCoordinate.latitude > location.coordinate.latitude)
    }

    @Test func anchorAdaptsToPanelsAndSmallScreens() {
        for size in [CGSize(width: 375, height: 667), CGSize(width: 402, height: 874)] {
            for bottom in [CGFloat(170), CGFloat(340)] {
                let anchor = ForwardMapCamera.anchor(in: size, topInset: 150, bottomInset: bottom)
                let visibleHeight = size.height - 150 - bottom
                #expect(abs((anchor.y - 150) / visibleHeight - 0.74) < 0.001)
                #expect(anchor.y < size.height - bottom)
            }
        }
    }

    @Test func lookAheadWrapsAtDateLine() {
        let center = ForwardMapCamera.offset(.init(latitude: 0, longitude: 179.999), meters: 1000, bearing: 90)
        #expect(CLLocationCoordinate2DIsValid(center))
        #expect(center.longitude < -179)
    }
}
