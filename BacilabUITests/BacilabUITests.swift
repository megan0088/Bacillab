import XCTest

/// Walks the flow end to end: home → patient data → scan session.
///
/// Deliberately stops before Review: reviewing needs analysed fields, and running the real
/// models inside a UI test makes it slow and brittle. What this guards is the navigation —
/// that the screens connect and are titled correctly.
final class BacilabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The banner merges its title and subtitle `Text` into one accessibility element, so its
    /// label is "New Analysis, Input patient" rather than the bare title — match on the prefix
    /// instead of the exact string.
    private func tapNewAnalysis(in app: XCUIApplication) {
        let banner = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "New Analysis"))
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
    }

    @MainActor
    func testHomeShowsLabTitle() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Electra Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BTA Analyzer"].exists)
    }

    @MainActor
    func testNewAnalysisOpensPatientDataForm() throws {
        let app = XCUIApplication()
        app.launch()

        tapNewAnalysis(in: app)

        XCTAssertTrue(app.navigationBars["Patient Data"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCameraStaysLockedUntilRequiredFieldsAreFilled() throws {
        let app = XCUIApplication()
        app.launch()

        tapNewAnalysis(in: app)
        XCTAssertTrue(app.navigationBars["Patient Data"].waitForExistence(timeout: 5))

        let openCamera = app.buttons["Open Camera"]
        XCTAssertTrue(openCamera.exists)
        XCTAssertFalse(openCamera.isEnabled,
                       "A session must not start without a name and a medical record number")

        // Fill in the form's own top-to-bottom order (MRN, then Patient Name): typing into the
        // lower field first lifts it above the keyboard and scrolls the field above it
        // off-screen, so the second tap never receives focus.
        app.textFields["Medical Record Number (MRN)"].tap()
        app.typeText("RM 240724-001")
        app.textFields["Patient Name"].tap()
        app.typeText("Ahmad Rizki")

        XCTAssertTrue(openCamera.isEnabled)
    }
}
