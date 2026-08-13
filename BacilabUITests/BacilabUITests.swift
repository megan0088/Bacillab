//
//  BacilabUITests.swift
//  BacilabUITests
//
//  Created by Muhamad Ega Nugraha on 03/08/26.
//

import XCTest

final class BacilabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        print("=== SCREEN \(name) ===")
        print(app.debugDescription)
    }

    @MainActor
    func testFullFlow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["BTA Analyzer"].waitForExistence(timeout: 10))
        snap(app, "01-home")

        // FAB (bottom-right) opens the new-sample sheet
        app.buttons["Add"].tap()

        XCTAssertTrue(app.navigationBars["Data Pasien"].waitForExistence(timeout: 5))
        snap(app, "02-datainput")

        // Match on placeholder: index 0 is the search box on the list screen behind
        // the sheet, and the field order has changed before.
        let name = app.textFields
            .matching(NSPredicate(format: "placeholderValue == %@", "Masukkan nama lengkap"))
            .firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // Coordinate tap: the sheet's presentation animation leaves the field
        // briefly non-hittable, which makes a plain .tap() flaky here.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        name.typeText("Budi Santoso")
        snap(app, "03-datainput-filled")

        let go = app.buttons["Buka Kamera"]
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        XCTAssertTrue(go.isEnabled, "Tombol harus enabled setelah nama pasien diisi")
        go.tap()

        XCTAssertTrue(app.navigationBars["Capture Field"].waitForExistence(timeout: 5))
        snap(app, "04-capture")

        // Round shutter, centred near the bottom; it carries no accessibility label.
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
            .tap()

        XCTAssertTrue(app.staticTexts["1 of 100 Field"].waitForExistence(timeout: 15),
                      "Field counter tidak bertambah — capture gagal")
        // One field is far below the 20 that 3+ requires, so the grade must be
        // flagged provisional rather than presented as a conclusion.
        XCTAssertTrue(app.staticTexts["SEMENTARA"].exists,
                      "Grade dari 1 lapang pandang tidak ditandai sementara")
        XCTAssertTrue(app.staticTexts["Perlu 19 lapang lagi"].exists,
                      "Sisa lapang pandang tidak diberitahukan ke analis")
        snap(app, "05-capture-after-shot")

        // Moving to the next field must be a labelled action, not a bare circle
        let nextField = app.buttons["Ambil Lapang Berikutnya"]
        XCTAssertTrue(nextField.waitForExistence(timeout: 5),
                      "Tidak ada tombol jelas untuk pindah ke lapang pandang berikutnya")
        nextField.tap()

        XCTAssertTrue(app.staticTexts["2 of 100 Field"].waitForExistence(timeout: 15),
                      "Lapang pandang kedua tidak terekam")
        snap(app, "06-second-field")

        app.buttons["Selesai, Lanjut ke Review"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 5))
        snap(app, "07-review")

        // The old FAB read only "N"; the action now states its destination
        let toResult = app.buttons["Lihat Interpretasi"]
        XCTAssertTrue(toResult.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["N"].exists, "Tombol 'N' masih ada")
        toResult.tap()

        XCTAssertTrue(app.navigationBars["Interpretation"].waitForExistence(timeout: 5))
        snap(app, "08-interpretation")
    }
}
