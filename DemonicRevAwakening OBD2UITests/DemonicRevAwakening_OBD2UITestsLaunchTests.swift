//
//  DemonicRevAwakening_OBD2UITestsLaunchTests.swift
//  DemonicRevAwakening OBD2UITests
//
//  Created by David Martens on 24.10.26.
//

import XCTest

final class DemonicRevAwakening_OBD2UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Demo starten, damit der Screenshot den erwachenden Dämon zeigt.
        if app.buttons["Demo"].waitForExistence(timeout: 5) {
            app.buttons["Demo"].tap()
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
