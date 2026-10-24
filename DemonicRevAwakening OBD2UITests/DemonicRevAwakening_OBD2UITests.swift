//
//  DemonicRevAwakening_OBD2UITests.swift
//  DemonicRevAwakening OBD2UITests
//

import XCTest

final class DemonicRevAwakening_OBD2UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartScreenShowsConnectAndDemo() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Verbinden"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Demo"].exists)
        XCTAssertTrue(app.staticTexts["Nicht verbunden"].exists || app.otherElements["Verbindungsstatus: Nicht verbunden"].exists)
    }

    @MainActor
    func testDemoIsClearlyMarkedAndCanBeStopped() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Demo"].tap()
        let badge = app.staticTexts["Demo-Modus aktiv: simulierte Fahrzeugdaten"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5) || app.otherElements["Demo-Modus aktiv: simulierte Fahrzeugdaten"].exists)

        app.buttons["Demo beenden"].tap()
        XCTAssertTrue(app.buttons["Demo"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
