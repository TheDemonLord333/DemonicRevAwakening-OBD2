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

    /// Erstellt Screenshots des Dämons bei verschiedenen simulierten Drehzahlen.
    @MainActor
    func testDemoStatesScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .portrait

        app.buttons["Demo"].tap()
        let manual = app.segmentedControls.buttons["Manuell"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        for (position, name) in [(0.0, "0-motor-aus"), (0.1, "1-leerlauf"), (0.2, "2-erwacht"),
                                 (0.36, "3-wach"), (0.8, "4-entfesselt")] {
            slider.adjust(toNormalizedSliderPosition: position)
            sleep(4)
            attachScreenshot(app, name: "Hochformat-\(name)")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        attachScreenshot(app, name: "Querformat-entfesselt")
        app.buttons["Reduzierter Vollbildmodus"].tap()
        sleep(2)
        attachScreenshot(app, name: "Querformat-vollbild")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
