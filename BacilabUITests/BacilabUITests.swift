import XCTest

/// Menelusuri alur baru dari ujung ke ujung: beranda → data pasien → sesi scan.
///
/// Sengaja berhenti sebelum Review: review butuh lapang yang sudah dianalisis, dan
/// menjalankan model sungguhan di UI test membuatnya lambat dan rapuh. Yang dijaga di sini
/// adalah navigasinya — bahwa layar-layar itu tersambung dan judulnya benar.
final class BacilabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The banner combines a title and a subtitle `Text` into one accessibility element, so
    /// its label is "Analisis Baru, Mulai pemeriksaan BTA" rather than the bare title —
    /// match on the prefix instead of the exact string.
    private func tapAnalisisBaru(in app: XCUIApplication) {
        let banner = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Analisis Baru"))
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.tap()
    }

    @MainActor
    func testBerandaMenampilkanJudulLab() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Electra Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BTA Analyzer"].exists)
    }

    @MainActor
    func testAnalisisBaruMembukaFormDataPasien() throws {
        let app = XCUIApplication()
        app.launch()

        tapAnalisisBaru(in: app)

        XCTAssertTrue(app.navigationBars["Data Pasien"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testKameraTerkunciSampaiDataWajibTerisi() throws {
        let app = XCUIApplication()
        app.launch()

        tapAnalisisBaru(in: app)
        XCTAssertTrue(app.navigationBars["Data Pasien"].waitForExistence(timeout: 5))

        let openCamera = app.buttons["Buka Kamera"]
        XCTAssertTrue(openCamera.exists)
        XCTAssertFalse(openCamera.isEnabled,
                       "Sesi tidak boleh dimulai tanpa nama dan nomor rekam medis")

        // Fill in the form's top-to-bottom order (No. Rekam Medis, then Nama Pasien): typing
        // into the lower field first pulls it above the keyboard and scrolls the field above
        // it off-screen, so the second tap never gets keyboard focus.
        app.textFields["Contoh: RM 240724-001"].tap()
        app.typeText("RM 240724-001")
        app.textFields["Masukkan nama lengkap"].tap()
        app.typeText("Ahmad Rizki")

        XCTAssertTrue(openCamera.isEnabled)
    }
}
