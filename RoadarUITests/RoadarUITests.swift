//
//  RoadarUITests.swift
//  RoadarUITests
//
//  Created by Nathan Mayo on 9/3/26.
//

import XCTest

final class RoadarUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testRedesignedMapAndRoadDetails() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["searchPlaces"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["recenter"].exists)
        XCTAssertTrue(app.buttons["walkingMode"].exists)
        XCTAssertTrue(app.buttons["drivingMode"].exists)
        attachScreenshot("Walking map", app: app)

        app.buttons["searchPlaces"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("Place search", app: app)
        app.buttons["Done"].tap()

        app.buttons["drivingMode"].tap()
        XCTAssertTrue(app.buttons["roadDetails"].waitForExistence(timeout: 5))
        attachScreenshot("Driving map", app: app)
        app.buttons["roadDetails"].tap()
        XCTAssertTrue(app.buttons["roadDownloads"].waitForExistence(timeout: 5))
        attachScreenshot("Road details", app: app)
        app.buttons["roadDownloads"].tap()
        XCTAssertTrue(app.navigationBars["Road downloads"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["importRoadPackage"].waitForExistence(timeout: 5))
        app.navigationBars["Road downloads"].buttons["Done"].tap()
        app.navigationBars["Road details"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["recenter"].exists)
    }

    @MainActor
    func testLocationSitsBelowMapCenter() throws {
        let app = XCUIApplication()
        app.launch()
        let marker = app.descendants(matching: .any)["userLocationMarker"].firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15), "Provide a simulated location before running this camera test")
        let toggle = app.buttons["toggleMapDetails"]
        if toggle.value as? String == "Minimized" { toggle.tap() }
        app.buttons["drivingMode"].tap()
        app.buttons["recenter"].tap()
        func assertLowerAnchor() {
            let lowerAnchor = NSPredicate { _, _ in
                let top = app.buttons["searchPlaces"].frame.maxY
                let bottom = app.buttons["recenter"].frame.minY
                let y = marker.frame.midY
                return y > top + (bottom - top) * 0.62 && y < bottom
            }
            let pending = XCTNSPredicateExpectation(predicate: lowerAnchor, object: app)
            let result = XCTWaiter.wait(for: [pending], timeout: 10)
            XCTAssertEqual(result, .completed, "Location \(marker.frame), search \(app.buttons["searchPlaces"].frame), recenter \(app.buttons["recenter"].frame)")
        }
        assertLowerAnchor()
        attachScreenshot("Lower location expanded", app: app)
        toggle.tap()
        assertLowerAnchor()
        attachScreenshot("Lower location compact", app: app)
        toggle.tap()
    }

    @MainActor
    func testCompactMapMenu() throws {
        let app = XCUIApplication()
        app.launch()
        let toggle = app.buttons["toggleMapDetails"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String == "Minimized" { toggle.tap() }
        let expandedTop = toggle.frame.minY
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Minimized")
        XCTAssertGreaterThan(toggle.frame.minY, expandedTop)
        XCTAssertTrue(app.buttons["walkingMode"].exists)
        XCTAssertTrue(app.buttons["recenter"].exists)
        attachScreenshot("Compact map", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "Minimized")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")
    }

    @MainActor
    func testRoutePreferencesPersistAfterRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["routePreferences"].waitForExistence(timeout: 10))
        app.buttons["routePreferences"].tap()
        XCTAssertTrue(app.buttons["restoreRouteDefaults"].waitForExistence(timeout: 5))
        app.buttons["restoreRouteDefaults"].tap()
        let stepper = app.steppers["secondsThreshold"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons["secondsThreshold-Increment"].tap()
        XCTAssertTrue(app.staticTexts["Save at least 90 seconds"].exists)
        attachScreenshot("Route preferences", app: app)
        app.terminate()
        app.launch()
        app.buttons["routePreferences"].tap()
        XCTAssertTrue(app.staticTexts["Save at least 90 seconds"].waitForExistence(timeout: 5))
        app.buttons["restoreRouteDefaults"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
