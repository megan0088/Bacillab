# Bacilab Flow Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mengganti wizard 4 layar (Data Pasien → Capture → Review → Interpretation) dengan alur Data Pasien → Sesi Scan → Review → Lembar Hasil, di mana setiap keputusan klinis punya tepat satu layar pemilik.

**Architecture:** Hitungan BTA berhenti disimpan sebagai akumulator dan menjadi turunan dari daftar lapang (`ExamSession.fields`). Sesi scan buta terhadap BTA — ia hanya memotret, menulis ke disk, dan mengantrekan analisis di latar. Semua keputusan (koreksi hitungan, grade, catatan, terbit) terjadi di Review.

**Tech Stack:** Swift 5.9+, SwiftUI, iOS 17+, `@Observable` / `@Bindable`, swift-testing (`import Testing`), ONNX Runtime 1.24.2, CoreML.

## Global Constraints

- iOS 17+. `@Observable` untuk ViewModel dan model sesi; `@Bindable` untuk meneruskannya.
- **Tidak boleh `@Environment(AppDependencies.self)` di view yang di-push** di dalam sheet/NavigationStack — akan crash saat runtime. Dependency diteruskan lewat properti `let` eksplisit. `@Environment` hanya aman di root (`SampleListView`).
- **Tidak ada Combine.** `async`/`await` di seluruh kode.
- Seluruh teks UI **Bahasa Indonesia**.
- Nama fasilitas di seluruh UI: **Electra Lab**.
- Warna kustom selalu dengan prefiks eksplisit: `foregroundStyle(Color.appPrimary)`, bukan `.appPrimary`.
- Setiap file View wajib punya minimal satu blok `#Preview`.
- `@State private var viewModel: ViewModel` diinisialisasi lewat `_viewModel = State(initialValue: ...)`.
- Semua kode kamera dijaga `#if targetEnvironment(simulator)`.
- Test framework: **swift-testing**, bukan XCTest. Nama test dalam Bahasa Indonesia, mengikuti `GradeThresholdTests`.
- Grading dan ambang lapang **tidak berubah**: `BTAGrade.grade(for:across:)` dan `BTAGrade.minimumFields` (3+ = 20, 2+ = 50, 1+/Scanty/Negatif = 100).
- Target batch scan: **20 lapang** (`ExamSession.batchTarget`). Angka ini **tidak pernah** ikut perhitungan grading.

## Urutan Eksekusi

Nomor task **bukan** urutan kerja. Layar saling merujuk ke depan — `PatientDataView` membuka
`ScanView`, `ScanView` membuka `ReviewView`, `ReviewView` membuka `ResultSheetView` — jadi
dibangun dari hilir ke hulu supaya setiap task ter-compile tanpa stub sementara.

**Kerjakan dengan urutan ini:**

```
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8      (model, penyimpanan, antrean, DI)
15                                  (ResultSheetView — tidak merujuk apa pun)
12 → 13 → 14                        (Review: view model, komponen, view)
10 → 11                             (Scan: view model, view)
9                                   (PatientDataView)
16 → 17 → 18                        (beranda, hapus alur lama, dokumen)
```

Setiap task tetap dirujuk dengan nomornya sendiri. Tidak ada task yang perlu menyulih tujuan
`NavigationLink` dengan `Text(...)` sementara.

**Perintah test (dipakai di setiap task):**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/<NamaSuite> 2>&1 | tail -25
```

---

## File Structure

### Dibuat

| File | Tanggung jawab |
|---|---|
| `Bacilab/Core/Domain/Entities/PatientInfo.swift` | Data pasien (8 field sesuai hi-fi) + validasi kelengkapan |
| `Bacilab/Core/Domain/Entities/FieldRecord.swift` | Satu lapang: berkas gambar, hasil analisis, koreksi manual, status dibuang |
| `Bacilab/Core/Domain/Entities/ExamSession.swift` | Sesi pemeriksaan + seluruh angka turunan (total BTA, penyebut, grade, gerbang) |
| `Bacilab/Core/Domain/Protocols/SessionStoreProtocol.swift` | Kontrak penyimpanan sesi |
| `Bacilab/Core/Services/SessionStore.swift` | Manifest JSON + berkas JPEG di Application Support |
| `Bacilab/Core/Services/FieldAnalysisQueue.swift` | Antrean serial: analisis lapang di latar sambil scan jalan |
| `Bacilab/Core/Services/FocusMetric.swift` | Ketajaman frame, tanpa detektor |
| `Bacilab/Features/PatientData/PatientDataView.swift` | Form 8 field |
| `Bacilab/Features/Scan/ScanView.swift` | Viewfinder kotak, hitungan lapang, peringatan fokus, kontrol scan |
| `Bacilab/Features/Scan/ScanViewModel.swift` | Loop auto-scan, tulis lapang, autosave, enqueue analisis |
| `Bacilab/Features/Review/ReviewView.swift` | Pager lapang, gambar + box, keypad, hapus lapang, grade, terbit |
| `Bacilab/Features/Review/ReviewViewModel.swift` | State review, muat gambar, koreksi, publish |
| `Bacilab/Features/Review/Components/FieldPager.swift` | Deretan dot bernomor + penanda perlu-verifikasi |
| `Bacilab/Features/Review/Components/CountKeypad.swift` | Keypad numerik untuk hitungan satu lapang |
| `Bacilab/Features/Review/Components/FieldCanvas.swift` | Gambar lapang + box tiap model, kotak dengan panduan lingkaran |
| `Bacilab/Features/ResultSheet/ResultSheetView.swift` | Lembar hasil read-only (juga tujuan tap dari beranda) |

### Diubah

| File | Perubahan |
|---|---|
| `Bacilab/Core/Domain/Entities/AnalysisResult.swift` | Tambah `Codable` pada `DetectedBox`, `DetectorKind`, `DetectorReading`, `BTAGrade` |
| `Bacilab/Core/Services/FieldFraming.swift` | Tambah `analysisJPEG(of:)` — crop persegi + encode pada resolusi analisis |
| `Bacilab/App/AppDependencies.swift` | Ganti `sampleRepository` dengan `sessionStore`, tambah `makeAnalysisQueue()` |
| `Bacilab/Features/SampleList/SampleListView.swift` | Daftar `ExamSession`, status Berjalan, navigasi ke sesi/lembar hasil |
| `Bacilab/Features/SampleList/SampleListViewModel.swift` | Baca dari `SessionStore` |
| `Bacilab/Core/Extensions/PreviewHelpers.swift` | Ganti `Sample.previews`/`SampleDraft.preview` dengan `ExamSession.preview*` |
| `CLAUDE.md` | Nama fasilitas, struktur file, aturan baru |

### Dihapus

`Bacilab/Core/Domain/Entities/SampleDraft.swift`, `Sample.swift`, `CapturedField.swift`,
`Bacilab/Core/Services/SampleRepository.swift`, `Bacilab/Core/Domain/Protocols/SampleRepositoryProtocol.swift`,
`Bacilab/Features/DataInput/`, `Bacilab/Features/Capture/`, `Bacilab/Features/Analysis/`, `Bacilab/Features/Result/`.

`Bacilab/Features/Capture/Components/CameraPreviewView.swift` **dipindahkan**, bukan dihapus — ke `Bacilab/Features/Scan/Components/CameraPreviewView.swift`.

---

## Task 1: Codable pada tipe deteksi

**Files:**
- Modify: `Bacilab/Core/Domain/Entities/AnalysisResult.swift`
- Test: `BacilabTests/DetectionCodableTests.swift`

**Interfaces:**
- Consumes: tipe yang sudah ada — `DetectedBox`, `DetectorKind`, `DetectorReading`, `BTAGrade`
- Produces: keempatnya `Codable`, sehingga `FieldRecord` (Task 2) dan manifest JSON (Task 4) bisa menyimpannya

Persistensi menyimpan hasil analisis per lapang ke JSON. Tanpa `Codable` di keempat tipe ini, manifest tidak bisa ditulis sama sekali. Perubahannya aditif — tidak ada yang berubah bagi pemakai lama.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/DetectionCodableTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Hasil analisis per lapang disimpan ke manifest JSON supaya sesi bisa dilanjutkan
/// setelah app ditutup. Round-trip harus utuh: box yang bergeser atau `failure` yang
/// hilang berarti angka di layar tidak lagi sama dengan yang tersimpan.
struct DetectionCodableTests {

    @Test("DetectorReading bolak-balik lewat JSON tanpa kehilangan apa pun")
    func readingRoundTrips() throws {
        let original = DetectorReading(
            detector: .resnet,
            btaCount: 7,
            confidence: 0.82,
            elapsed: 1.25,
            boxes: [DetectedBox(cx: 0.5, cy: 0.25, w: 0.1, h: 0.05, angle: 0.7)],
            failure: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectorReading.self, from: data)

        #expect(decoded == original)
    }

    @Test("Reading yang gagal tetap membawa pesan kegagalannya")
    func failureRoundTrips() throws {
        let original = DetectorReading(
            detector: .yolo11,
            btaCount: 0,
            confidence: 0,
            elapsed: 0.3,
            failure: "model tidak tersedia"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DetectorReading.self, from: data)

        #expect(decoded.failure == "model tidak tersedia")
        #expect(decoded.btaCount == 0)
    }

    @Test("BTAGrade bolak-balik lewat JSON")
    func gradeRoundTrips() throws {
        for grade in BTAGrade.allCases {
            let data = try JSONEncoder().encode(grade)
            #expect(try JSONDecoder().decode(BTAGrade.self, from: data) == grade)
        }
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/DetectionCodableTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE dengan pesan bahwa `DetectorReading` tidak konform ke `Encodable`.

- [ ] **Step 3: Tambahkan konformansi**

Di `Bacilab/Core/Domain/Entities/AnalysisResult.swift`, ubah empat deklarasi berikut — hanya baris deklarasinya, isinya tidak disentuh:

```swift
struct DetectedBox: Hashable, Sendable, Codable {
```

```swift
enum DetectorKind: String, Hashable, Sendable, CaseIterable, Codable {
```

```swift
struct DetectorReading: Hashable, Sendable, Codable {
```

```swift
enum BTAGrade: String, Hashable, CaseIterable, Sendable, Codable {
```

`DetectorReading` punya `init` kustom dengan nilai default, tapi synthesized `Codable` memakai stored properties langsung — jadi tidak ada yang perlu ditulis manual.

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/DetectionCodableTests 2>&1 | tail -25
```

Diharapkan: LULUS, 3 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Core/Domain/Entities/AnalysisResult.swift BacilabTests/DetectionCodableTests.swift
git commit -m "feat: make detection types Codable for session persistence"
```

---

## Task 2: PatientInfo dan FieldRecord

**Files:**
- Create: `Bacilab/Core/Domain/Entities/PatientInfo.swift`
- Create: `Bacilab/Core/Domain/Entities/FieldRecord.swift`
- Test: `BacilabTests/FieldRecordTests.swift`

**Interfaces:**
- Consumes: `DetectorReading`, `DetectorKind` (Codable sejak Task 1)
- Produces:
  - `PatientInfo` dengan 8 properti var dan `var isComplete: Bool`
  - `FieldAnalysis(readings: [DetectorReading], primary: DetectorKind)` dengan `var count: Int?` dan `var confidence: Double?`
  - `FieldRecord(id:index:imageFileName:analysis:correctedCount:isExcluded:)` dengan `effectiveCount: Int?`, `isCounted: Bool`, `needsManualCount: Bool`, `isPending: Bool`

Titik paling penting di task ini: `effectiveCount` bertipe **optional**. Lapang yang analisisnya gagal atau belum jalan bukan lapang bernilai nol — kalau ia dipaksa jadi `Int`, model yang rusak akan terlihat persis seperti model yang tidak melihat apa-apa, dan lapang itu akan menyeret grade turun.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/FieldRecordTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Satu lapang boleh berada dalam empat keadaan: belum dianalisis, dianalisis dengan
/// hasil, dianalisis tapi gagal, atau dibuang analis. Hanya keadaan kedua dan lapang
/// yang dikoreksi manual yang boleh masuk hitungan.
struct FieldRecordTests {

    private func reading(_ count: Int, failure: String? = nil) -> DetectorReading {
        DetectorReading(detector: .resnet, btaCount: count, confidence: 0.8,
                        elapsed: 0.5, failure: failure)
    }

    private func field(
        index: Int = 0,
        analysis: FieldAnalysis? = nil,
        corrected: Int? = nil,
        excluded: Bool = false
    ) -> FieldRecord {
        FieldRecord(index: index, imageFileName: "field-000.jpg",
                    analysis: analysis, correctedCount: corrected, isExcluded: excluded)
    }

    @Test("Lapang tanpa analisis belum punya hitungan")
    func pendingFieldHasNoCount() {
        let f = field()
        #expect(f.effectiveCount == nil)
        #expect(f.isPending)
        #expect(!f.isCounted)
    }

    @Test("Hitungan model dipakai ketika tidak ada koreksi")
    func modelCountUsedWhenNotCorrected() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .resnet))
        #expect(f.effectiveCount == 9)
        #expect(f.isCounted)
    }

    @Test("Koreksi analis mengalahkan hitungan model")
    func correctionWins() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .resnet),
                      corrected: 4)
        #expect(f.effectiveCount == 4)
    }

    @Test("Koreksi nol adalah nol, bukan 'belum dikoreksi'")
    func zeroCorrectionIsRespected() {
        let f = field(analysis: FieldAnalysis(readings: [reading(9)], primary: .resnet),
                      corrected: 0)
        #expect(f.effectiveCount == 0, "Nol dari analis harus menang atas 9 dari model")
        #expect(f.isCounted)
    }

    @Test("Analisis gagal tidak pernah bernilai nol")
    func failedAnalysisHasNoCount() {
        let f = field(analysis: FieldAnalysis(
            readings: [reading(0, failure: "ORT gagal")], primary: .resnet))
        #expect(f.effectiveCount == nil, "Kegagalan tidak boleh terbaca sebagai 'tidak lihat apa-apa'")
        #expect(f.needsManualCount)
        #expect(!f.isCounted)
    }

    @Test("Lapang gagal yang dikoreksi manual kembali terhitung")
    func failedFieldRecoveredByCorrection() {
        let f = field(analysis: FieldAnalysis(
            readings: [reading(0, failure: "ORT gagal")], primary: .resnet), corrected: 3)
        #expect(f.effectiveCount == 3)
        #expect(f.isCounted)
        #expect(!f.needsManualCount)
    }

    @Test("Lapang yang dibuang tidak terhitung meski punya angka")
    func excludedFieldIsNotCounted() {
        let f = field(analysis: FieldAnalysis(readings: [reading(12)], primary: .resnet),
                      excluded: true)
        #expect(!f.isCounted)
        #expect(!f.needsManualCount, "Lapang yang dibuang tidak perlu dihitung manual")
    }

    @Test("Data pasien lengkap butuh nama dan nomor rekam medis")
    func patientCompleteness() {
        var p = PatientInfo()
        #expect(!p.isComplete)
        p.name = "Ahmad Rizki"
        #expect(!p.isComplete)
        p.medicalRecordNumber = "RM 240724-001"
        #expect(p.isComplete)
        p.name = "   "
        #expect(!p.isComplete, "Spasi saja bukan nama")
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldRecordTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `PatientInfo` dan `FieldRecord` belum ada.

- [ ] **Step 3: Buat PatientInfo**

`Bacilab/Core/Domain/Entities/PatientInfo.swift`:

```swift
import Foundation

/// Identitas pasien dan sampelnya, sesuai form hi-fi.
///
/// Tidak ada nama dokter dan nomor akses di sini: keduanya dikumpulkan oleh form lama
/// tapi tidak pernah ditampilkan di layar mana pun.
struct PatientInfo: Codable, Hashable, Sendable {
    var medicalRecordNumber = ""
    var nationalID = ""
    var name = ""
    var dateOfBirth = Date()
    var address = ""
    var phone = ""
    var examinationDate = Date()
    var sampleCollectedAt = Date()

    /// Cukup untuk memulai sesi. Nama dan nomor rekam medis wajib karena keduanya yang
    /// dipakai menemukan kembali hasil ini; sisanya boleh menyusul.
    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !medicalRecordNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
```

- [ ] **Step 4: Buat FieldRecord**

`Bacilab/Core/Domain/Entities/FieldRecord.swift`:

```swift
import Foundation

/// Apa yang dibuat model atas satu lapang.
struct FieldAnalysis: Codable, Hashable, Sendable {
    let readings: [DetectorReading]
    /// Model yang hitungannya dipakai. Model lain ikut tersimpan untuk dibandingkan,
    /// tapi tidak pernah menjadi angka yang dipakai.
    let primary: DetectorKind

    var primaryReading: DetectorReading? {
        readings.first { $0.detector == primary }
    }

    /// Hitungan model utama, atau nil kalau model itu gagal pada lapang ini.
    var count: Int? {
        guard let r = primaryReading, r.failure == nil else { return nil }
        return r.btaCount
    }

    var confidence: Double? {
        guard let r = primaryReading, r.failure == nil else { return nil }
        return r.confidence
    }
}

/// Satu lapang pandang yang sudah direkam.
///
/// `imageFileName` relatif terhadap direktori sesi, bukan URL absolut: path kontainer
/// aplikasi iOS berubah antar-instalasi, jadi URL absolut yang tersimpan akan menunjuk
/// ke berkas yang tidak ada lagi setelah app diperbarui.
struct FieldRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let imageFileName: String
    var analysis: FieldAnalysis?
    var correctedCount: Int?
    var isExcluded: Bool

    init(
        id: UUID = UUID(),
        index: Int,
        imageFileName: String,
        analysis: FieldAnalysis? = nil,
        correctedCount: Int? = nil,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.index = index
        self.imageFileName = imageFileName
        self.analysis = analysis
        self.correctedCount = correctedCount
        self.isExcluded = isExcluded
    }

    /// Hitungan yang berlaku, atau nil kalau belum ada.
    ///
    /// Optional dengan sengaja: lapang tanpa hitungan bukan lapang bernilai nol. Memaksanya
    /// jadi 0 akan membuat model yang gagal terlihat sama persis dengan model yang tidak
    /// menemukan apa-apa, dan lapang itu akan menyeret grade turun tanpa jejak.
    var effectiveCount: Int? {
        if let correctedCount { return correctedCount }
        return analysis?.count
    }

    /// Masuk ke pembilang dan penyebut grading.
    var isCounted: Bool { !isExcluded && effectiveCount != nil }

    /// Analisis sudah jalan tapi tidak menghasilkan angka, dan analis belum mengisinya.
    var needsManualCount: Bool {
        !isExcluded && analysis != nil && analysis?.count == nil && correctedCount == nil
    }

    /// Masih menunggu giliran di antrean analisis.
    var isPending: Bool { analysis == nil && correctedCount == nil }
}
```

- [ ] **Step 5: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldRecordTests 2>&1 | tail -25
```

Diharapkan: LULUS, 8 test.

- [ ] **Step 6: Commit**

```bash
git add Bacilab/Core/Domain/Entities/PatientInfo.swift \
        Bacilab/Core/Domain/Entities/FieldRecord.swift \
        BacilabTests/FieldRecordTests.swift
git commit -m "feat: add PatientInfo and FieldRecord with optional effective count"
```

---

## Task 3: ExamSession dan seluruh angka turunan

**Files:**
- Create: `Bacilab/Core/Domain/Entities/ExamSession.swift`
- Test: `BacilabTests/ExamSessionTests.swift`

**Interfaces:**
- Consumes: `PatientInfo`, `FieldRecord`, `FieldAnalysis` (Task 2), `BTAGrade` (sudah ada)
- Produces:
  - `ExamSession(id:patient:createdAt:)`, `static let batchTarget = 20`
  - Mutasi: `appendField(imageFileName:) -> FieldRecord`, `setAnalysis(_:for:)`, `setCorrectedCount(_:for:)`, `setExcluded(_:for:)`, `chooseGrade(_:)`
  - Turunan: `countedFields`, `examinedFieldCount`, `totalBTA`, `suggestedGrade`, `reportedGrade`, `isGradeConfirmed`, `fieldsRemainingForGrade`, `pendingAnalysisCount`, `fieldsNeedingManualCount`, `displayStatus`
  - `enum SessionStatus: String, Codable { case scanning, reviewing, published }`
  - `enum SessionDisplayStatus { case running, negative, positive }`

Inti seluruh rewrite. Tidak ada satu pun angka yang disimpan: `totalBTA` dan `examinedFieldCount` dihitung ulang dari `fields` setiap kali dibaca. Ini yang membuat kelas bug lama — akumulator yang dilabeli ulang saat model berganti — mustahil terjadi, bukan sekadar dijaga.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/ExamSessionTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Seluruh angka sesi adalah turunan dari daftar lapang. Tidak ada akumulator terpisah
/// yang bisa menyimpang dari isinya.
struct ExamSessionTests {

    private func analysis(_ count: Int, failure: String? = nil) -> FieldAnalysis {
        FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5, failure: failure)],
            primary: .resnet
        )
    }

    /// Menambahkan `count` lapang, masing-masing dengan hitungan `bta`.
    @discardableResult
    private func fill(_ session: ExamSession, count: Int, bta: Int) -> [FieldRecord] {
        (0..<count).map { _ in
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(analysis(bta), for: field.id)
            return field
        }
    }

    @Test("Setiap lapang terhitung, termasuk yang tidak berisi BTA")
    func everyFieldCountsIncludingEmpty() {
        let session = ExamSession()
        fill(session, count: 5, bta: 0)

        #expect(session.examinedFieldCount == 5,
                "Lapang kosong wajib masuk penyebut — tanpa itu Negatif tidak pernah tercapai")
        #expect(session.totalBTA == 0)
        #expect(session.suggestedGrade == .negative)
    }

    @Test("Total BTA dan penyebut dihitung dari lapang")
    func totalsDerivedFromFields() {
        let session = ExamSession()
        fill(session, count: 4, bta: 3)

        #expect(session.examinedFieldCount == 4)
        #expect(session.totalBTA == 12)
    }

    @Test("Koreksi analis langsung mengubah total")
    func correctionChangesTotal() {
        let session = ExamSession()
        let fields = fill(session, count: 3, bta: 5)
        #expect(session.totalBTA == 15)

        session.setCorrectedCount(1, for: fields[0].id)

        #expect(session.totalBTA == 11, "5+5+5 dengan lapang pertama dikoreksi jadi 1")
        #expect(session.examinedFieldCount == 3, "Koreksi tidak mengubah jumlah lapang")
    }

    @Test("Lapang yang dibuang hilang dari pembilang dan penyebut")
    func excludedFieldLeavesBothSides() {
        let session = ExamSession()
        let fields = fill(session, count: 4, bta: 5)

        session.setExcluded(true, for: fields[0].id)

        #expect(session.totalBTA == 15)
        #expect(session.examinedFieldCount == 3,
                "Lapang yang dibuang harus keluar dari penyebut juga, bukan cuma pembilang")
    }

    @Test("Lapang gagal-analisis tidak menyumbang nol ke mana pun")
    func failedFieldContributesToNeither() {
        let session = ExamSession()
        fill(session, count: 3, bta: 6)
        let broken = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(0, failure: "ORT gagal"), for: broken.id)

        #expect(session.examinedFieldCount == 3,
                "Lapang gagal tidak boleh menggelembungkan penyebut")
        #expect(session.totalBTA == 18)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Lapang yang masih diantre belum masuk hitungan")
    func pendingFieldNotCountedYet() {
        let session = ExamSession()
        fill(session, count: 2, bta: 4)
        _ = session.appendField(imageFileName: "f.jpg")

        #expect(session.examinedFieldCount == 2)
        #expect(session.pendingAnalysisCount == 1)
        #expect(session.fields.count == 3, "Lapang tetap tercatat meski analisisnya belum selesai")
    }

    @Test("Grade pilihan analis mengalahkan grade usulan")
    func chosenGradeWins() {
        let session = ExamSession()
        fill(session, count: 10, bta: 20)      // 200 per 100 lapang → 2+

        #expect(session.suggestedGrade == .plus2)
        #expect(session.reportedGrade == .plus2)

        session.chooseGrade(.scanty)

        #expect(session.reportedGrade == .scanty)
        #expect(session.suggestedGrade == .plus2, "Usulan model tidak ikut berubah")
    }

    @Test("Negatif belum final sebelum 100 lapang")
    func negativeNeedsFullReading() {
        let session = ExamSession()
        fill(session, count: 20, bta: 0)

        #expect(session.reportedGrade == .negative)
        #expect(!session.isGradeConfirmed)
        #expect(session.fieldsRemainingForGrade == 80)
    }

    @Test("3+ sudah final di 20 lapang")
    func heavySmearConfirmsAtTwenty() {
        let session = ExamSession()
        fill(session, count: 20, bta: 15)      // 1500 per 100 lapang → 3+

        #expect(session.reportedGrade == .plus3)
        #expect(session.isGradeConfirmed)
        #expect(session.fieldsRemainingForGrade == 0)
    }

    @Test("Gerbang mengikuti grade yang dipilih, bukan yang diusulkan")
    func gateFollowsChosenGrade() {
        let session = ExamSession()
        fill(session, count: 20, bta: 15)      // usulan 3+, sudah final
        #expect(session.isGradeConfirmed)

        session.chooseGrade(.scanty)

        #expect(!session.isGradeConfirmed, "Scanty butuh 100 lapang meski usulannya 3+")
        #expect(session.fieldsRemainingForGrade == 80)
    }

    @Test("Membuang lapang bisa membatalkan status final")
    func exclusionCanUnconfirmGrade() {
        let session = ExamSession()
        let fields = fill(session, count: 20, bta: 15)
        #expect(session.isGradeConfirmed)

        session.setExcluded(true, for: fields[0].id)

        #expect(session.examinedFieldCount == 19)
        #expect(!session.isGradeConfirmed,
                "19 lapang tidak cukup untuk 3+ — status final harus ikut turun")
    }

    @Test("Status beranda diturunkan dari status sesi")
    func displayStatusDerivation() {
        let session = ExamSession()
        #expect(session.displayStatus == .running)

        fill(session, count: 20, bta: 15)
        session.status = .reviewing
        #expect(session.displayStatus == .running)

        session.status = .published
        #expect(session.displayStatus == .positive)

        session.chooseGrade(.negative)
        #expect(session.displayStatus == .negative)
    }

    @Test("Sesi kosong tidak meledak")
    func emptySessionIsSafe() {
        let session = ExamSession()

        #expect(session.examinedFieldCount == 0)
        #expect(session.totalBTA == 0)
        #expect(session.suggestedGrade == .negative)
        #expect(!session.isGradeConfirmed)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ExamSessionTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `ExamSession` belum ada.

- [ ] **Step 3: Buat ExamSession**

`Bacilab/Core/Domain/Entities/ExamSession.swift`:

```swift
import Foundation
import Observation

enum SessionStatus: String, Codable, Hashable, Sendable {
    case scanning
    case reviewing
    case published
}

/// Bagaimana sebuah sesi tampil di beranda.
enum SessionDisplayStatus: Hashable, Sendable {
    case running
    case negative
    case positive

    var label: String {
        switch self {
        case .running:  return "Berjalan"
        case .negative: return "Negatif"
        case .positive: return "Positif"
        }
    }
}

/// Satu pemeriksaan, dari data pasien sampai hasil terbit.
///
/// **Tidak ada angka yang disimpan.** `totalBTA` dan `examinedFieldCount` dihitung ulang dari
/// `fields` setiap kali dibaca. Model lama menyimpan `manualBTACount` terpisah dari daftar
/// lapang, sehingga keduanya bisa menyimpang — dan yang menentukan grade pasien adalah yang
/// tersimpan, bukan yang terlihat. Di sini penyimpangan itu tidak punya tempat untuk terjadi.
@Observable
final class ExamSession: Identifiable {

    /// Berapa lapang yang dituju satu batch scan. **Tidak pernah** ikut perhitungan grading —
    /// ia hanya mengisi teks "n dari 20" di layar scan. Penyebut grading adalah
    /// `examinedFieldCount`.
    static let batchTarget = 20

    let id: UUID
    let createdAt: Date
    var patient: PatientInfo
    var notes: String
    var status: SessionStatus

    /// Grade yang dipilih analis. `nil` berarti belum ada yang memutuskan, sehingga
    /// `reportedGrade` jatuh ke usulan model. Optional inilah yang menggantikan
    /// `hasManualGrade` lama — tidak perlu flag terpisah untuk membedakan "belum diputuskan"
    /// dari "diputuskan manusia".
    private(set) var chosenGrade: BTAGrade?

    private(set) var fields: [FieldRecord]

    init(
        id: UUID = UUID(),
        patient: PatientInfo = PatientInfo(),
        notes: String = "",
        status: SessionStatus = .scanning,
        chosenGrade: BTAGrade? = nil,
        fields: [FieldRecord] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.patient = patient
        self.notes = notes
        self.status = status
        self.chosenGrade = chosenGrade
        self.fields = fields
        self.createdAt = createdAt
    }

    // MARK: - Mutasi

    /// Mencatat satu lapang baru. Selalu bertambah — apa pun isinya, termasuk lapang kosong.
    ///
    /// Inilah perbaikan atas cacat lama: auto-scan dulu hanya menambah hitungan ketika
    /// `btaCount > 0`, sehingga lapang kosong tidak pernah masuk penyebut dan grade Negatif
    /// secara struktural tidak bisa dicapai.
    @discardableResult
    func appendField(imageFileName: String) -> FieldRecord {
        let field = FieldRecord(index: fields.count, imageFileName: imageFileName)
        fields.append(field)
        return field
    }

    func setAnalysis(_ analysis: FieldAnalysis, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].analysis = analysis
    }

    /// `nil` mengembalikan lapang ke hitungan model.
    func setCorrectedCount(_ count: Int?, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].correctedCount = count.map { max(0, $0) }
    }

    func setExcluded(_ excluded: Bool, for fieldID: UUID) {
        guard let i = fields.firstIndex(where: { $0.id == fieldID }) else { return }
        fields[i].isExcluded = excluded
    }

    func chooseGrade(_ grade: BTAGrade) {
        chosenGrade = grade
    }

    func field(withID id: UUID) -> FieldRecord? {
        fields.first { $0.id == id }
    }

    // MARK: - Turunan

    /// Lapang yang masuk hitungan: tidak dibuang, dan punya angka.
    var countedFields: [FieldRecord] { fields.filter(\.isCounted) }

    /// Penyebut grading — berapa lapang benar-benar terbaca.
    var examinedFieldCount: Int { countedFields.count }

    var totalBTA: Int { countedFields.compactMap(\.effectiveCount).reduce(0, +) }

    /// Grade yang dihitung dari lapang. `max(_, 1)` hanya menjaga pembagian nol; dengan
    /// nol lapang `totalBTA` juga nol, jadi hasilnya tetap Negatif.
    var suggestedGrade: BTAGrade {
        BTAGrade.grade(for: totalBTA, across: max(examinedFieldCount, 1))
    }

    /// Grade yang dilaporkan: pilihan analis kalau ada, usulan model kalau tidak.
    var reportedGrade: BTAGrade { chosenGrade ?? suggestedGrade }

    /// Apakah lapang sudah cukup untuk grade ini berdiri sebagai laporan final (WHO/IUATLD).
    var isGradeConfirmed: Bool { examinedFieldCount >= reportedGrade.minimumFields }

    var fieldsRemainingForGrade: Int {
        max(0, reportedGrade.minimumFields - examinedFieldCount)
    }

    var pendingAnalysisCount: Int { fields.filter(\.isPending).count }

    var fieldsNeedingManualCount: [FieldRecord] { fields.filter(\.needsManualCount) }

    var displayStatus: SessionDisplayStatus {
        switch status {
        case .scanning, .reviewing:
            return .running
        case .published:
            return reportedGrade == .negative ? .negative : .positive
        }
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ExamSessionTests 2>&1 | tail -25
```

Diharapkan: LULUS, 13 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Core/Domain/Entities/ExamSession.swift BacilabTests/ExamSessionTests.swift
git commit -m "feat: add ExamSession with counts derived from field list"
```

---

## Task 4: FieldFraming.analysisJPEG

**Files:**
- Modify: `Bacilab/Core/Services/FieldFraming.swift`
- Test: `BacilabTests/FieldFramingTests.swift`

**Interfaces:**
- Consumes: `FieldFraming.uprightCenteredSquare(of:)` yang sudah ada
- Produces: `static func analysisJPEG(of image: UIImage) -> Data?` — persegi tegak, sisi maksimum 1600 px, JPEG kualitas 0.9

Analisis sekarang berjalan **belakangan**, dari berkas di disk. Berkas itu karena itu harus pada resolusi analisis, bukan thumbnail 640 px seperti `freeze()` lama.

Batas 1600 px bukan angka sembarangan: transform Faster R-CNN memakai `min_size=1200, max_size=1600`, jadi apa pun di atas 1600 akan dikecilkan lagi oleh model. Menyimpan lebih besar hanya memakan disk tanpa menambah satu piksel pun yang dilihat model. Gambar yang lebih kecil dari itu **tidak** diperbesar — memperbesar tidak menambah informasi, hanya ukuran berkas.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/FieldFramingTests.swift`:

```swift
import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Berkas lapang adalah satu-satunya salinan yang dilihat model, karena analisis berjalan
/// setelah scan selesai. Ukurannya karena itu terikat pada transform model, bukan pada
/// kenyamanan tampilan.
struct FieldFramingTests {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { ctx in
                UIColor.blue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor.magenta.setFill()
                ctx.fill(CGRect(x: width / 3, y: height / 3, width: 40, height: 12))
            }
    }

    @Test("Foto besar dipotong persegi dan dikecilkan ke 1600 px")
    func largePhotoIsCappedAt1600() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 3024, height: 4032)))
        let decoded = try #require(UIImage(data: data))

        #expect(decoded.size.width == decoded.size.height, "Harus persegi")
        #expect(decoded.size.width == 1600,
                "Di atas 1600 px tidak menambah apa pun yang dilihat model (max_size=1600)")
    }

    @Test("Gambar kecil tidak diperbesar")
    func smallPhotoIsNotUpscaled() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 800, height: 600)))
        let decoded = try #require(UIImage(data: data))

        #expect(decoded.size.width == 600, "Sisi persegi mengikuti sisi terpendek")
        #expect(decoded.size.height == 600)
    }

    @Test("Hasilnya JPEG yang bisa dibaca ulang")
    func outputIsDecodable() throws {
        let data = try #require(FieldFraming.analysisJPEG(of: image(width: 2000, height: 2000)))

        #expect(!data.isEmpty)
        #expect(UIImage(data: data) != nil)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldFramingTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `analysisJPEG` belum ada.

- [ ] **Step 3: Tambahkan analysisJPEG**

Tambahkan di dalam `enum FieldFraming` di `Bacilab/Core/Services/FieldFraming.swift`, setelah `uprightCenteredSquare(of:)`:

```swift
    /// Sisi maksimum berkas lapang yang disimpan.
    ///
    /// Transform Faster R-CNN memakai `min_size=1200, max_size=1600`, jadi apa pun di atas
    /// 1600 px akan dikecilkan lagi oleh model sendiri. Menyimpan lebih besar hanya memakan
    /// disk — dan sesi 20 lapang sudah puluhan megabita.
    static let maxAnalysisSide: CGFloat = 1600

    /// Berkas lapang siap-analisis: tegak, persegi, dan tidak lebih besar dari yang dipakai model.
    ///
    /// Analisis berjalan belakangan dari berkas ini, jadi ia harus berisi piksel yang sama
    /// dengan yang akan dilihat detektor. Thumbnail tidak cukup.
    static func analysisJPEG(of image: UIImage) -> Data? {
        guard let square = uprightCenteredSquare(of: image) else { return nil }

        let sourceSide = CGFloat(square.width)
        // Tidak pernah memperbesar: menaikkan resolusi tidak menambah informasi apa pun.
        let side = min(sourceSide, maxAnalysisSide)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side),
            format: format
        ).image { _ in
            UIImage(cgImage: square).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        return resized.jpegData(compressionQuality: 0.9)
    }
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldFramingTests 2>&1 | tail -25
```

Diharapkan: LULUS, 3 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Core/Services/FieldFraming.swift BacilabTests/FieldFramingTests.swift
git commit -m "feat: add analysis-resolution JPEG framing for stored fields"
```

---

## Task 5: SessionStore — persistensi ke disk

**Files:**
- Create: `Bacilab/Core/Domain/Protocols/SessionStoreProtocol.swift`
- Create: `Bacilab/Core/Services/SessionStore.swift`
- Test: `BacilabTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `ExamSession`, `FieldRecord`, `PatientInfo` (Task 2–3)
- Produces:
  - `protocol SessionStoreProtocol: AnyObject` dengan `allSessions() async throws -> [ExamSession]`, `save(_:) async throws`, `delete(_:) async throws`, `writeFieldImage(_:fileName:for:) throws`, `fieldImageURL(fileName:for:) -> URL`
  - `final class SessionStore: SessionStoreProtocol` dengan `init(root: URL? = nil)` — `root` dapat disuntik untuk test

Sesi 20 lapang adalah puluhan menit kerja. Penyimpanan in-memory yang sekarang berarti telepon masuk, app di-kill, atau memori habis menghapus semuanya tanpa jejak. Manifest ditulis ulang setiap kali sebuah lapang direkam atau dianalisis.

Struktur di disk:

```
<Application Support>/Sessions/<session-uuid>/
    manifest.json
    field-000.jpg
    field-001.jpg
    ...
```

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/SessionStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Sesi harus selamat dari app yang ditutup di tengah scan. Yang diuji di sini adalah
/// round-trip penuh: apa yang tersimpan harus sama persis dengan apa yang dibaca kembali,
/// termasuk koreksi analis dan lapang yang dibuang.
struct SessionStoreTests {

    /// Direktori sementara per test, supaya test tidak saling mengotori dan tidak
    /// menyentuh data asli di Application Support.
    private func makeStore() throws -> (SessionStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)")
        return (SessionStore(root: root), root)
    }

    private func analysis(_ count: Int) -> FieldAnalysis {
        FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5)],
            primary: .resnet
        )
    }

    @Test("Sesi tersimpan dan terbaca kembali utuh")
    func sessionRoundTrips() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        session.patient.name = "Ahmad Rizki"
        session.patient.medicalRecordNumber = "RM 240724-001"
        session.notes = "Batuk lebih dari 3 minggu"
        let field = session.appendField(imageFileName: "field-000.jpg")
        session.setAnalysis(analysis(6), for: field.id)

        try await store.save(session)
        let loaded = try await store.allSessions()

        let restored = try #require(loaded.first { $0.id == session.id })
        #expect(restored.patient.name == "Ahmad Rizki")
        #expect(restored.patient.medicalRecordNumber == "RM 240724-001")
        #expect(restored.notes == "Batuk lebih dari 3 minggu")
        #expect(restored.fields.count == 1)
        #expect(restored.totalBTA == 6)
        #expect(restored.examinedFieldCount == 1)
    }

    @Test("Koreksi dan lapang yang dibuang ikut tersimpan")
    func correctionsAndExclusionsSurvive() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        let a = session.appendField(imageFileName: "field-000.jpg")
        let b = session.appendField(imageFileName: "field-001.jpg")
        session.setAnalysis(analysis(10), for: a.id)
        session.setAnalysis(analysis(10), for: b.id)
        session.setCorrectedCount(2, for: a.id)
        session.setExcluded(true, for: b.id)

        try await store.save(session)
        let restored = try #require(try await store.allSessions().first { $0.id == session.id })

        #expect(restored.totalBTA == 2)
        #expect(restored.examinedFieldCount == 1)
    }

    @Test("Grade pilihan analis dan status ikut tersimpan")
    func gradeAndStatusSurvive() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        session.chooseGrade(.scanty)
        session.status = .published

        try await store.save(session)
        let restored = try #require(try await store.allSessions().first { $0.id == session.id })

        #expect(restored.chosenGrade == .scanty)
        #expect(restored.status == .published)
        #expect(restored.displayStatus == .positive)
    }

    @Test("Menyimpan sesi yang sama dua kali tidak menggandakannya")
    func saveIsIdempotent() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        try await store.save(session)
        session.notes = "diperbarui"
        try await store.save(session)

        let loaded = try await store.allSessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].notes == "diperbarui")
    }

    @Test("Gambar lapang tersimpan dan bisa dibaca lewat URL-nya")
    func fieldImageIsWrittenAndReadable() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        try await store.save(session)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

        try store.writeFieldImage(bytes, fileName: "field-000.jpg", for: session)
        let url = store.fieldImageURL(fileName: "field-000.jpg", for: session)

        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("Menghapus sesi menghapus gambarnya juga")
    func deleteRemovesImages() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        try await store.save(session)
        try store.writeFieldImage(Data([0x01]), fileName: "field-000.jpg", for: session)
        let url = store.fieldImageURL(fileName: "field-000.jpg", for: session)

        try await store.delete(session)

        #expect(try await store.allSessions().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "Gambar yatim akan menumpuk diam-diam sampai disk penuh")
    }

    @Test("Sesi terbaru muncul lebih dulu")
    func newestSessionFirst() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = ExamSession(createdAt: Date(timeIntervalSince1970: 1_000_000))
        let newer = ExamSession(createdAt: Date(timeIntervalSince1970: 2_000_000))
        try await store.save(older)
        try await store.save(newer)

        let loaded = try await store.allSessions()
        #expect(loaded.first?.id == newer.id)
    }

    @Test("Manifest rusak dilewati, bukan menjatuhkan seluruh daftar")
    func corruptManifestIsSkipped() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let good = ExamSession()
        try await store.save(good)

        let brokenDir = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
        try Data("bukan json".utf8)
            .write(to: brokenDir.appendingPathComponent("manifest.json"))

        let loaded = try await store.allSessions()
        #expect(loaded.count == 1, "Satu sesi rusak tidak boleh menyembunyikan sesi lain")
        #expect(loaded[0].id == good.id)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/SessionStoreTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `SessionStore` belum ada.

- [ ] **Step 3: Buat protokolnya**

`Bacilab/Core/Domain/Protocols/SessionStoreProtocol.swift`:

```swift
import Foundation

protocol SessionStoreProtocol: AnyObject {
    func allSessions() async throws -> [ExamSession]
    func save(_ session: ExamSession) async throws
    func delete(_ session: ExamSession) async throws

    /// Menulis berkas gambar satu lapang ke direktori sesi.
    func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws

    /// Lokasi berkas gambar satu lapang. Dibentuk dari direktori sesi + nama berkas relatif,
    /// bukan dari URL absolut yang tersimpan — path kontainer app berubah antar-instalasi.
    func fieldImageURL(fileName: String, for session: ExamSession) -> URL
}
```

- [ ] **Step 4: Buat SessionStore**

`Bacilab/Core/Services/SessionStore.swift`:

```swift
import Foundation

/// Sesi di disk: satu direktori per sesi, berisi manifest JSON dan berkas gambar lapang.
///
/// JSON dan bukan SwiftData: yang dibutuhkan hanya menulis dan membaca kembali sebuah daftar,
/// dan manifest yang bisa dibuka dengan editor teks jauh lebih mudah diperiksa ketika sebuah
/// sesi tampak salah.
final class SessionStore: SessionStoreProtocol {

    private let root: URL
    private let fileManager = FileManager.default

    /// `root` bisa disuntik supaya test tidak menyentuh data asli.
    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.root = (base ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Sessions", isDirectory: true)
        }
    }

    // MARK: - Bentuk tersimpan

    /// `ExamSession` adalah kelas `@Observable`, jadi ia tidak bisa langsung `Codable`.
    /// Snapshot ini yang ditulis; ia juga menjadi batas eksplisit antara bentuk di memori
    /// dan bentuk di disk.
    private struct Snapshot: Codable {
        let id: UUID
        let createdAt: Date
        let patient: PatientInfo
        let notes: String
        let status: SessionStatus
        let chosenGrade: BTAGrade?
        let fields: [FieldRecord]
    }

    private func snapshot(_ session: ExamSession) -> Snapshot {
        Snapshot(
            id: session.id,
            createdAt: session.createdAt,
            patient: session.patient,
            notes: session.notes,
            status: session.status,
            chosenGrade: session.chosenGrade,
            fields: session.fields
        )
    }

    private func session(from snapshot: Snapshot) -> ExamSession {
        ExamSession(
            id: snapshot.id,
            patient: snapshot.patient,
            notes: snapshot.notes,
            status: snapshot.status,
            chosenGrade: snapshot.chosenGrade,
            fields: snapshot.fields,
            createdAt: snapshot.createdAt
        )
    }

    // MARK: - Lokasi

    private func directory(for session: ExamSession) -> URL {
        root.appendingPathComponent(session.id.uuidString, isDirectory: true)
    }

    private func manifestURL(for session: ExamSession) -> URL {
        directory(for: session).appendingPathComponent("manifest.json")
    }

    func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
        directory(for: session).appendingPathComponent(fileName)
    }

    // MARK: - SessionStoreProtocol

    func save(_ session: ExamSession) async throws {
        let dir = directory(for: session)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot(session))

        // Tulis atomik: app yang mati di tengah penulisan tidak boleh meninggalkan manifest
        // separuh jadi, karena itu akan menghapus seluruh sesi saat dibaca kembali.
        try data.write(to: manifestURL(for: session), options: .atomic)
    }

    func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {
        let dir = directory(for: session)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
    }

    func delete(_ session: ExamSession) async throws {
        let dir = directory(for: session)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    func allSessions() async throws -> [ExamSession] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let dirs = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let sessions: [ExamSession] = dirs.compactMap { dir in
            let manifest = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let snapshot = try? decoder.decode(Snapshot.self, from: data)
            else {
                // Satu manifest rusak tidak boleh menyembunyikan sesi lain. Dilewati diam-diam
                // di sini; direktorinya tetap ada untuk diperiksa.
                return nil
            }
            return session(from: snapshot)
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }
}
```

- [ ] **Step 5: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/SessionStoreTests 2>&1 | tail -25
```

Diharapkan: LULUS, 8 test.

- [ ] **Step 6: Commit**

```bash
git add Bacilab/Core/Domain/Protocols/SessionStoreProtocol.swift \
        Bacilab/Core/Services/SessionStore.swift \
        BacilabTests/SessionStoreTests.swift
git commit -m "feat: persist exam sessions as JSON manifest plus field images"
```

---

## Task 6: FieldAnalysisQueue — analisis di latar

**Files:**
- Create: `Bacilab/Core/Services/FieldAnalysisQueue.swift`
- Test: `BacilabTests/FieldAnalysisQueueTests.swift`

**Interfaces:**
- Consumes: `AnalysisServiceProtocol.analyze(imageData:using:)`, `ExamSession.setAnalysis(_:for:)`, `DetectorSelection.all`
- Produces: `@MainActor @Observable final class FieldAnalysisQueue` dengan `init(analysisService:)`, `enqueue(fieldID:imageData:into:)`, `waitUntilIdle() async`, `cancelAll()`, `private(set) var remaining: Int`

Scan tidak boleh menunggu model. Setiap lapang yang tersimpan masuk antrean; pekerja tunggal menghabiskannya satu per satu di latar. Saat teknisi menekan Selesai, sebagian besar sudah rampung.

**Serial, bukan paralel.** ResNet berjalan dalam hitungan detik di perangkat; menjalankan beberapa lapang sekaligus akan menggilas CPU dan memicu throttling termal di tengah sesi — tepat ketika teknisi paling tidak ingin diperlambat.

Antrean di-`@MainActor` karena ia memutasi `ExamSession` yang `@Observable` dan menggerakkan UI. Kerja beratnya sendiri tetap di luar: `MultiDetectorService` sudah menjalankan ORT pada `DispatchQueue` privatnya.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/FieldAnalysisQueueTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Antrean adalah satu-satunya jalan hasil model masuk ke sesi. Yang diuji: semua lapang
/// terlayani, satu per satu, dan kegagalan satu lapang tidak menjatuhkan sisanya.
@MainActor
struct FieldAnalysisQueueTests {

    /// Mencatat berapa banyak analisis berjalan bersamaan, supaya sifat serial bisa dibuktikan
    /// dan bukan sekadar diasumsikan.
    private final class StubAnalysisService: AnalysisServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private(set) var maxConcurrent = 0
        private(set) var callCount = 0

        var countPerField = 4
        var failEveryCall = false

        func analyze(imageData: Data) async throws -> AnalysisResult {
            lock.lock()
            active += 1
            maxConcurrent = max(maxConcurrent, active)
            callCount += 1
            let shouldFail = failEveryCall
            lock.unlock()

            try? await Task.sleep(for: .milliseconds(10))

            lock.lock()
            active -= 1
            lock.unlock()

            if shouldFail { throw AnalysisError.modelUnavailable }

            return AnalysisResult(
                btaCount: countPerField,
                confidence: 0.8,
                grade: .scanty,
                analyzedAt: Date(),
                detectedBoxes: [],
                readings: [DetectorReading(detector: .resnet, btaCount: countPerField,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    @Test("Semua lapang yang diantre akhirnya teranalisis")
    func allQueuedFieldsGetAnalysed() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        for _ in 0..<5 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        await queue.waitUntilIdle()

        #expect(service.callCount == 5)
        #expect(session.pendingAnalysisCount == 0)
        #expect(session.examinedFieldCount == 5)
        #expect(session.totalBTA == 20)
        #expect(queue.remaining == 0)
    }

    @Test("Analisis berjalan satu per satu, bukan bersamaan")
    func analysisRunsSerially() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        for _ in 0..<6 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        await queue.waitUntilIdle()

        #expect(service.maxConcurrent == 1,
                "Beberapa lapang berjalan bersamaan — CPU akan tergilas dan telepon memanas")
    }

    @Test("Model yang gagal menjadi lapang perlu-hitung-manual, bukan nol")
    func failureBecomesManualCountField() async {
        let service = StubAnalysisService()
        service.failEveryCall = true
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        let field = session.appendField(imageFileName: "f.jpg")
        queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        await queue.waitUntilIdle()

        let stored = session.field(withID: field.id)
        #expect(stored?.analysis != nil, "Lapang harus punya hasil, meski hasilnya kegagalan")
        #expect(stored?.effectiveCount == nil, "Kegagalan tidak boleh terbaca sebagai 0 BTA")
        #expect(session.examinedFieldCount == 0)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Satu lapang gagal tidak menghentikan sisanya")
    func oneFailureDoesNotStopTheQueue() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        let first = session.appendField(imageFileName: "f.jpg")
        service.failEveryCall = true
        queue.enqueue(fieldID: first.id, imageData: Data([0x01]), into: session)
        await queue.waitUntilIdle()

        service.failEveryCall = false
        for _ in 0..<3 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }
        await queue.waitUntilIdle()

        #expect(session.examinedFieldCount == 3)
        #expect(session.fieldsNeedingManualCount.count == 1)
    }

    @Test("Sisa antrean turun sampai nol")
    func remainingDropsToZero() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        for _ in 0..<3 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }
        #expect(queue.remaining > 0)

        await queue.waitUntilIdle()
        #expect(queue.remaining == 0)
    }

    @Test("Membatalkan antrean menghentikan pekerjaan yang belum jalan")
    func cancelStopsPendingWork() async {
        let service = StubAnalysisService()
        let queue = FieldAnalysisQueue(analysisService: service)
        let session = ExamSession()

        for _ in 0..<10 {
            let field = session.appendField(imageFileName: "f.jpg")
            queue.enqueue(fieldID: field.id, imageData: Data([0x01]), into: session)
        }

        queue.cancelAll()
        await queue.waitUntilIdle()

        #expect(queue.remaining == 0)
        #expect(service.callCount < 10, "Antrean yang dibatalkan tetap menghabiskan semua pekerjaan")
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldAnalysisQueueTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `FieldAnalysisQueue` belum ada.

- [ ] **Step 3: Buat FieldAnalysisQueue**

`Bacilab/Core/Services/FieldAnalysisQueue.swift`:

```swift
import Foundation
import Observation

private let queueLog = Diag("antrean")

/// Menjalankan model atas lapang yang sudah tersimpan, di latar, sementara scan terus berjalan.
///
/// Scan mengambil frame tiap ~1,5 detik sedangkan satu lapang butuh beberapa detik di perangkat.
/// Kalau scan menunggu model, laju itu mustahil. Karena itu lapang ditulis ke disk lebih dulu
/// dan analisisnya menyusul — saat teknisi menekan Selesai, sebagian besar sudah rampung.
///
/// **Serial dengan sengaja.** Menjalankan beberapa lapang sekaligus menggilas CPU dan memicu
/// throttling termal di tengah sesi. Satu pekerja, satu lapang pada satu waktu.
///
/// Di-`@MainActor` karena ia memutasi `ExamSession` yang `@Observable` dan menggerakkan UI.
/// Kerja beratnya tetap di luar: `MultiDetectorService` menjalankan ORT di antrean privatnya.
@MainActor
@Observable
final class FieldAnalysisQueue {

    private struct Job {
        let fieldID: UUID
        let imageData: Data
    }

    private let analysisService: any AnalysisServiceProtocol
    private var jobs: [Job] = []
    private var worker: Task<Void, Never>?

    /// Berapa lapang masih menunggu, untuk ditampilkan sebagai "menganalisis n dari m".
    private(set) var remaining = 0

    init(analysisService: any AnalysisServiceProtocol) {
        self.analysisService = analysisService
    }

    func enqueue(fieldID: UUID, imageData: Data, into session: ExamSession) {
        jobs.append(Job(fieldID: fieldID, imageData: imageData))
        remaining = jobs.count
        startWorkerIfNeeded(session: session)
    }

    /// Menunggu antrean habis. Dipakai Review sebelum menampilkan angka final, dan oleh test.
    func waitUntilIdle() async {
        await worker?.value
    }

    func cancelAll() {
        worker?.cancel()
        jobs.removeAll()
        remaining = 0
    }

    // MARK: - Pekerja

    private func startWorkerIfNeeded(session: ExamSession) {
        guard worker == nil else { return }

        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let job = self.takeNextJob() {
                let analysis = await self.analyse(job)
                session.setAnalysis(analysis, for: job.fieldID)
                self.remaining = self.jobs.count
            }
            self.remaining = self.jobs.isEmpty ? 0 : self.jobs.count
            self.worker = nil
        }
    }

    private func takeNextJob() -> Job? {
        jobs.isEmpty ? nil : jobs.removeFirst()
    }

    private func analyse(_ job: Job) async -> FieldAnalysis {
        do {
            let result = try await analysisService.analyze(imageData: job.imageData, using: .all)
            return FieldAnalysis(readings: result.readings, primary: .resnet)
        } catch {
            queueLog.error("Analisis lapang gagal: \(error.localizedDescription)")
            // Kegagalan disimpan sebagai bacaan bertanda `failure`, bukan sebagai hitungan 0.
            // Nol berarti "model melihat lapang bersih"; keduanya tidak boleh tertukar.
            return FieldAnalysis(
                readings: [DetectorReading(
                    detector: .resnet,
                    btaCount: 0,
                    confidence: 0,
                    elapsed: 0,
                    failure: error.localizedDescription
                )],
                primary: .resnet
            )
        }
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FieldAnalysisQueueTests 2>&1 | tail -25
```

Diharapkan: LULUS, 6 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Core/Services/FieldAnalysisQueue.swift BacilabTests/FieldAnalysisQueueTests.swift
git commit -m "feat: analyse fields serially in the background while scanning continues"
```

---

## Task 7: FocusMetric — peringatan fokus tanpa detektor

**Files:**
- Create: `Bacilab/Core/Services/FocusMetric.swift`
- Test: `BacilabTests/FocusMetricTests.swift`

**Interfaces:**
- Consumes: `CGImage`, `UIImage`
- Produces: `enum FocusMetric` dengan `static func sharpness(of: CGImage) -> Double`, `static func sharpness(of: UIImage) -> Double`, `static let blurThreshold: Double`, `static func isBlurry(_ sharpness: Double) -> Bool`

Hi-fi menampilkan "Camera out of focus" di layar kamera. Itu **tidak butuh detektor sama sekali** — ketajaman bisa dihitung langsung dari frame, murah, tiap frame. `focusCheckBadge` yang ada sekarang selalu menampilkan "Focus Check ✓" tanpa memeriksa apa pun, jadi lapang buram tetap terekam dan baru ketahuan di review.

Ukurannya: rata-rata kuadrat selisih piksel bertetangga pada gambar abu-abu 128×128. Gambar tajam punya banyak tepi tajam, gambar buram tidak.

**Ambangnya belum dikalibrasi.** `blurThreshold` di bawah adalah titik awal dari gambar sintetis, bukan dari preparat sungguhan di bawah okuler. Ia harus diukur dengan slide asli sebelum peringatannya dipercaya — sampai itu terjadi, peringatan hanya boleh memberi saran, tidak boleh memblokir capture.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/FocusMetricTests.swift`:

```swift
import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Peringatan fokus berjalan tiap frame, jadi ia harus murah dan tidak melibatkan model.
/// Yang diuji di sini sifat urutannya — gambar tajam harus selalu menilai lebih tinggi
/// daripada gambar rata — bukan angka mutlaknya, yang memang belum dikalibrasi.
struct FocusMetricTests {

    private func checkerboard(size: CGFloat = 256, cell: CGFloat = 8) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
                UIColor.black.setFill()
                var row = 0
                var y: CGFloat = 0
                while y < size {
                    var x: CGFloat = (row % 2 == 0) ? 0 : cell
                    while x < size {
                        ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
                        x += cell * 2
                    }
                    y += cell
                    row += 1
                }
            }
    }

    private func flat(size: CGFloat = 256) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
            .image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            }
    }

    @Test("Gambar bertepi tajam menilai lebih tinggi daripada gambar rata")
    func sharpScoresHigherThanFlat() {
        let sharp = FocusMetric.sharpness(of: checkerboard())
        let blurry = FocusMetric.sharpness(of: flat())

        #expect(sharp > blurry)
        #expect(blurry >= 0, "Ketajaman tidak pernah negatif")
    }

    @Test("Bidang rata dinilai buram")
    func flatFieldIsBlurry() {
        #expect(FocusMetric.isBlurry(FocusMetric.sharpness(of: flat())))
    }

    @Test("Bidang bertepi tajam tidak dinilai buram")
    func sharpFieldIsNotBlurry() {
        #expect(!FocusMetric.isBlurry(FocusMetric.sharpness(of: checkerboard())))
    }

    @Test("Petak lebih halus menilai lebih tinggi daripada petak lebih kasar")
    func finerDetailScoresHigher() {
        let fine = FocusMetric.sharpness(of: checkerboard(cell: 4))
        let coarse = FocusMetric.sharpness(of: checkerboard(cell: 32))

        #expect(fine > coarse, "Detail halus adalah yang pertama hilang saat fokus meleset")
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FocusMetricTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `FocusMetric` belum ada.

- [ ] **Step 3: Buat FocusMetric**

`Bacilab/Core/Services/FocusMetric.swift`:

```swift
import CoreGraphics
import UIKit

/// Seberapa tajam sebuah frame, tanpa menjalankan model apa pun.
///
/// Peringatan fokus harus jalan tiap frame, jadi ia tidak boleh menyentuh detektor — satu
/// lapang ResNet butuh hitungan detik. Yang dipakai di sini rata-rata kuadrat selisih piksel
/// bertetangga: gambar tajam punya banyak tepi tajam, gambar buram tidak.
enum FocusMetric {

    /// Sisi gambar kerja. Cukup kecil untuk berjalan tiap frame, cukup besar untuk
    /// mempertahankan tepi yang jadi kabur ketika fokus meleset.
    private static let workingSide = 128

    /// Di bawah ini frame dianggap buram.
    ///
    /// **Belum dikalibrasi.** Angka ini berasal dari gambar sintetis, bukan dari preparat
    /// sungguhan di bawah okuler. Sampai diukur dengan slide asli, peringatannya hanya boleh
    /// memberi saran — jangan pernah dipakai memblokir capture.
    static let blurThreshold: Double = 0.0015

    static func isBlurry(_ sharpness: Double) -> Bool {
        sharpness < blurThreshold
    }

    static func sharpness(of image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        return sharpness(of: cgImage)
    }

    static func sharpness(of image: CGImage) -> Double {
        let side = workingSide
        var pixels = [UInt8](repeating: 0, count: side * side)

        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Rata-rata kuadrat gradien, horizontal dan vertikal. Dinormalisasi ke [0, 1] supaya
        // ambangnya tidak bergantung pada kedalaman bit.
        var total = 0.0
        var samples = 0
        for y in 0..<(side - 1) {
            for x in 0..<(side - 1) {
                let i = y * side + x
                let dx = Double(pixels[i + 1]) - Double(pixels[i])
                let dy = Double(pixels[i + side]) - Double(pixels[i])
                total += (dx * dx + dy * dy) / (255.0 * 255.0)
                samples += 1
            }
        }

        guard samples > 0 else { return 0 }
        return total / Double(samples)
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/FocusMetricTests 2>&1 | tail -25
```

Diharapkan: LULUS, 4 test. Kalau `flatFieldIsBlurry` atau `sharpFieldIsNotBlurry` gagal, sesuaikan `blurThreshold` sehingga ia jatuh di antara kedua nilai — cetak keduanya dulu, jangan menebak.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Core/Services/FocusMetric.swift BacilabTests/FocusMetricTests.swift
git commit -m "feat: add detector-free focus metric for the scan viewfinder"
```

---

## Task 8: Wiring AppDependencies

**Files:**
- Modify: `Bacilab/App/AppDependencies.swift`
- Test: `BacilabTests/AppDependenciesTests.swift`

**Interfaces:**
- Consumes: `SessionStore` (Task 5), `FieldAnalysisQueue` (Task 6), `MultiDetectorService` (sudah ada)
- Produces: `AppDependencies.sessionStore: any SessionStoreProtocol`, `AppDependencies.makeAnalysisQueue() -> FieldAnalysisQueue`

`sampleRepository` masih ada di sini sampai Task 16 supaya layar lama tetap ter-compile selama migrasi. Antrean dibuat lewat pabrik, bukan disimpan sebagai properti tunggal, karena setiap sesi butuh antreannya sendiri — antrean bersama akan mencampur lapang dari dua sesi berbeda ke dalam satu urutan.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/AppDependenciesTests.swift`:

```swift
import Testing
@testable import Bacilab

struct AppDependenciesTests {

    @Test("Penyimpanan sesi tersedia dari container")
    func sessionStoreIsWired() {
        #expect(AppDependencies().sessionStore is SessionStore)
    }

    @Test("Setiap sesi mendapat antrean analisisnya sendiri")
    @MainActor
    func eachSessionGetsItsOwnQueue() {
        let deps = AppDependencies()
        let a = deps.makeAnalysisQueue()
        let b = deps.makeAnalysisQueue()

        #expect(a !== b,
                "Antrean bersama akan mencampur lapang dari dua sesi ke dalam satu urutan")
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/AppDependenciesTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `sessionStore` dan `makeAnalysisQueue` belum ada.

- [ ] **Step 3: Perbarui AppDependencies**

Ganti seluruh isi `Bacilab/App/AppDependencies.swift`:

```swift
import Foundation
import Observation

@Observable
final class AppDependencies {
    let cameraService: any CameraServiceProtocol
    let analysisService: any AnalysisServiceProtocol
    let sessionStore: any SessionStoreProtocol

    /// Masih dipakai layar lama selama migrasi; dihapus di task terakhir.
    let sampleRepository: any SampleRepositoryProtocol

    init() {
        cameraService = CameraService()
        // Semua model membaca setiap lapang. ResNet yang hitungannya dipakai; dua YOLO ikut
        // tersimpan untuk dibandingkan, dan tidak pernah menjadi angka yang dipakai.
        analysisService = MultiDetectorService()
        sessionStore = SessionStore()
        sampleRepository = SampleRepository()
    }

    /// Satu antrean per sesi.
    ///
    /// Bukan properti tunggal: antrean bersama akan menempatkan lapang dari dua sesi berbeda
    /// dalam satu urutan, dan membatalkan salah satunya akan membatalkan keduanya.
    @MainActor
    func makeAnalysisQueue() -> FieldAnalysisQueue {
        FieldAnalysisQueue(analysisService: analysisService)
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/AppDependenciesTests 2>&1 | tail -25
```

Diharapkan: LULUS, 2 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/App/AppDependencies.swift BacilabTests/AppDependenciesTests.swift
git commit -m "feat: wire session store and per-session analysis queue into DI container"
```

---

## Task 9: PatientDataView

**Files:**
- Create: `Bacilab/Features/PatientData/PatientDataView.swift`
- Test: build + `#Preview` (tidak ada logika baru — `PatientInfo.isComplete` sudah diuji di Task 2)

**Interfaces:**
- Consumes: `PatientInfo`, `ExamSession`, `AppDependencies`
- Produces: `PatientDataView(session: ExamSession, dependencies: AppDependencies)` — meneruskan ke `ScanView` (Task 11) lewat `NavigationLink`

Delapan field sesuai hi-fi, dua bagian. Nama dokter dan nomor akses **tidak ada** di sini: keduanya dikumpulkan form lama tapi tidak pernah ditampilkan di layar mana pun.

Dikerjakan setelah Task 11 (lihat Urutan Eksekusi), jadi `ScanView` sudah ada saat task ini dimulai.

- [ ] **Step 1: Buat view-nya**

`Bacilab/Features/PatientData/PatientDataView.swift`:

```swift
import SwiftUI

/// Data pasien dan sampel, sebelum sesi scan dimulai.
///
/// Dependency diterima sebagai `let` eksplisit, bukan `@Environment`: view ini di-push di
/// dalam `NavigationStack` sebuah sheet, dan `@Environment(AppDependencies.self)` di sana
/// akan crash saat runtime.
struct PatientDataView: View {
    @Bindable var session: ExamSession
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("Informasi Pasien")

                formField(label: "No. Rekam Medis", text: $session.patient.medicalRecordNumber,
                          placeholder: "Contoh: RM 240724-001")
                formField(label: "NIK", text: $session.patient.nationalID,
                          placeholder: "16 digit")
                formField(label: "Nama Pasien", text: $session.patient.name,
                          placeholder: "Masukkan nama lengkap")
                dateField(label: "Tanggal Lahir", date: $session.patient.dateOfBirth)
                formField(label: "Alamat", text: $session.patient.address,
                          placeholder: "Alamat pasien")
                formField(label: "No. Telepon", text: $session.patient.phone,
                          placeholder: "08xx-xxxx-xxxx")

                sectionHeader("Informasi Pemeriksaan")

                dateField(label: "Tanggal Pemeriksaan", date: $session.patient.examinationDate)
                dateField(label: "Waktu Pengambilan Sampel", date: $session.patient.sampleCollectedAt,
                          components: [.date, .hourAndMinute])

                Spacer(minLength: 24)

                NavigationLink {
                    ScanView(session: session, dependencies: dependencies)
                } label: {
                    Label("Buka Kamera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(!session.patient.isComplete)

                if !session.patient.isComplete {
                    Text("Nama pasien dan nomor rekam medis wajib diisi.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Data Pasien")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Batal") { dismiss() }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(Color.accentColor)
    }

    private func formField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .padding(14)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
        }
    }

    private func dateField(
        label: String,
        date: Binding<Date>,
        components: DatePickerComponents = .date
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                DatePicker("", selection: date, displayedComponents: components)
                    .labelsHidden()
                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

#Preview("Data Pasien – kosong") {
    NavigationStack {
        PatientDataView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Data Pasien – terisi") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.patient.nationalID = "3204012509900001"
    return NavigationStack {
        PatientDataView(session: session, dependencies: AppDependencies())
    }
}
```

- [ ] **Step 2: Build dan pastikan seluruh test lama tetap lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Diharapkan: BUILD SUCCEEDED dan seluruh test lulus.

- [ ] **Step 3: Periksa kedua `#Preview` di Xcode**

Buka `PatientDataView.swift`, jalankan preview. Yang dilihat: tombol "Buka Kamera" mati pada preview kosong dan hidup pada preview terisi.

- [ ] **Step 4: Commit**

```bash
git add Bacilab/Features/PatientData/PatientDataView.swift
git commit -m "feat: add patient data form matching the hi-fi field set"
```

---

## Task 10: ScanViewModel — setiap lapang terhitung

**Files:**
- Create: `Bacilab/Features/Scan/ScanViewModel.swift`
- Test: `BacilabTests/ScanViewModelTests.swift`

**Interfaces:**
- Consumes: `CameraServiceProtocol`, `SessionStoreProtocol`, `FieldAnalysisQueue`, `FieldFraming.analysisJPEG(of:)`, `FocusMetric`
- Produces: `@MainActor @Observable final class ScanViewModel` dengan `init(cameraService:store:queue:)`, `startCamera() async`, `stopCamera()`, `captureField(session:) async`, `toggleScan(session:)`, `stopScan()`, dan properti `isScanning`, `errorMessage`, `permissionDenied`, `isBlurry`, `lastSharpness`, `scanIntervalMilliseconds`

Task inti perbaikan cacat lama. Dua aturan yang harus dipegang persis:

1. **Setiap lapang yang berhasil direkam bertambah** — ada BTA maupun tidak. Auto-scan lama hanya menambah ketika `btaCount > 0`, sehingga lapang kosong tidak pernah masuk penyebut dan Negatif secara struktural mustahil.
2. **Capture yang gagal tidak menambah apa pun.** Lapang baru dicatat hanya setelah berkasnya benar-benar tertulis ke disk — kalau tidak, sesi akan berisi lapang yang gambarnya tidak ada.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/ScanViewModelTests.swift`:

```swift
import Testing
import Foundation
import UIKit
import AVFoundation
@testable import Bacilab

/// Sesi scan buta terhadap BTA: ia hanya menghasilkan lapang. Yang diuji di sini adalah
/// penyebut grading — lapang mana yang bertambah dan mana yang tidak.
@MainActor
struct ScanViewModelTests {

    // MARK: - Stub

    private func jpegBytes(side: CGFloat = 1200) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { ctx in
                UIColor.blue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private final class StubCamera: CameraServiceProtocol, @unchecked Sendable {
        var isRunning = true
        let session = AVCaptureSession()
        var payload: Data
        var error: Error?
        var startError: Error?

        init(payload: Data) { self.payload = payload }

        func startSession() async throws { if let startError { throw startError } }
        func stopSession() {}
        func captureImage() async throws -> Data {
            if let error { throw error }
            return payload
        }
    }

    private final class SpyStore: SessionStoreProtocol, @unchecked Sendable {
        var savedCount = 0
        var writtenFiles: [String] = []
        var writeError: Error?
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanViewModelTests-\(UUID().uuidString)")

        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ session: ExamSession) async throws { savedCount += 1 }
        func delete(_ session: ExamSession) async throws {}
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {
            if let writeError { throw writeError }
            writtenFiles.append(fileName)
        }
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            root.appendingPathComponent(fileName)
        }
    }

    private final class SilentAnalysis: AnalysisServiceProtocol, @unchecked Sendable {
        var btaCount = 0
        func analyze(imageData: Data) async throws -> AnalysisResult {
            AnalysisResult(
                btaCount: btaCount, confidence: 0.8, grade: .negative, analyzedAt: Date(),
                detectedBoxes: [],
                readings: [DetectorReading(detector: .resnet, btaCount: btaCount,
                                           confidence: 0.8, elapsed: 0.01)]
            )
        }
    }

    private func makeViewModel(
        camera: CameraServiceProtocol,
        store: SessionStoreProtocol,
        analysis: AnalysisServiceProtocol = SilentAnalysis()
    ) -> ScanViewModel {
        ScanViewModel(
            cameraService: camera,
            store: store,
            queue: FieldAnalysisQueue(analysisService: analysis)
        )
    }

    // MARK: - Test

    @Test("Lapang tanpa BTA tetap terhitung")
    func emptyFieldStillCounts() async {
        let store = SpyStore()
        let analysis = SilentAnalysis()
        analysis.btaCount = 0
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store,
                               analysis: analysis)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.queue.waitUntilIdle()

        #expect(session.fields.count == 1)
        #expect(session.examinedFieldCount == 1,
                "Lapang kosong wajib masuk penyebut — inilah cacat yang membuat Negatif mustahil")
        #expect(session.totalBTA == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("Sepuluh lapang kosong menghasilkan sepuluh lapang, bukan nol")
    func tenEmptyFieldsCountAsTen() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        for _ in 0..<10 { await vm.captureField(session: session) }
        await vm.queue.waitUntilIdle()

        #expect(session.examinedFieldCount == 10)
        #expect(session.suggestedGrade == .negative)
    }

    @Test("Capture yang gagal tidak menambah lapang")
    func failedCaptureAddsNothing() async {
        let store = SpyStore()
        let camera = StubCamera(payload: jpegBytes())
        camera.error = CameraError.captureFailed
        let vm = makeViewModel(camera: camera, store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty,
                "Lapang bertambah padahal tidak ada gambar — penyebut jadi menggelembung")
        #expect(store.writtenFiles.isEmpty)
        #expect(vm.errorMessage != nil, "Kegagalan harus dilaporkan ke analis")
    }

    @Test("Data kamera kosong diperlakukan sebagai kegagalan")
    func emptyDataIsAFailure() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: Data()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("Gagal menulis ke disk tidak meninggalkan lapang tanpa gambar")
    func diskFailureLeavesNoOrphanField() async {
        let store = SpyStore()
        store.writeError = CocoaError(.fileWriteOutOfSpace)
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)

        #expect(session.fields.isEmpty,
                "Lapang hanya boleh dicatat setelah gambarnya benar-benar tersimpan")
        #expect(vm.errorMessage != nil)
    }

    @Test("Setiap lapang menulis berkas dan menyimpan sesi")
    func eachFieldIsPersisted() async {
        let store = SpyStore()
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.captureField(session: session)

        #expect(store.writtenFiles == ["field-000.jpg", "field-001.jpg"])
        #expect(store.savedCount == 2, "Autosave tiap lapang — sesi 20 lapang tidak boleh hilang")
    }

    @Test("Izin ditolak dibedakan dari error biasa")
    func deniedPermissionIsDistinguished() async {
        let camera = StubCamera(payload: jpegBytes())
        camera.startError = CameraError.permissionDenied
        let vm = makeViewModel(camera: camera, store: SpyStore())

        await vm.startCamera()

        #expect(vm.permissionDenied)
        #expect(vm.errorMessage == nil, "Jangan tampilkan alert generik untuk kasus izin")
    }

    @Test("Lapang yang direkam diantrekan untuk dianalisis")
    func capturedFieldIsQueued() async {
        let store = SpyStore()
        let analysis = SilentAnalysis()
        analysis.btaCount = 7
        let vm = makeViewModel(camera: StubCamera(payload: jpegBytes()), store: store,
                               analysis: analysis)
        let session = ExamSession()

        await vm.captureField(session: session)
        await vm.queue.waitUntilIdle()

        #expect(session.totalBTA == 7, "Hasil antrean tidak sampai ke sesi")
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ScanViewModelTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `ScanViewModel` belum ada.

- [ ] **Step 3: Buat ScanViewModel**

`Bacilab/Features/Scan/ScanViewModel.swift`:

```swift
import AVFoundation
import Foundation
import Observation
import UIKit

private let scanLog = Diag("scan")

/// Menjalankan sesi scan. **Tidak tahu apa-apa tentang BTA.**
///
/// Tugasnya hanya menghasilkan lapang: memotret, memotong persegi, menulis ke disk,
/// mencatatnya ke sesi, lalu mengantrekan analisisnya. Hitungan, grade, dan perbandingan
/// model semuanya milik layar Review.
@MainActor
@Observable
final class ScanViewModel {

    private let cameraService: any CameraServiceProtocol
    private let store: any SessionStoreProtocol
    let queue: FieldAnalysisQueue

    var isScanning = false
    var errorMessage: String?
    var permissionDenied = false

    /// Ketajaman frame terakhir dan apakah ia dianggap buram. Peringatan saja — tidak pernah
    /// memblokir capture, karena ambangnya belum dikalibrasi terhadap preparat sungguhan.
    private(set) var lastSharpness: Double = 0
    private(set) var isBlurry = false

    /// Jeda antar lapang. Dapat diperkecil oleh test supaya loop tidak menunggu 1,5 detik.
    var scanIntervalMilliseconds = 1500

    private var scanTask: Task<Void, Never>?

    var session: AVCaptureSession { cameraService.session }

    init(
        cameraService: any CameraServiceProtocol,
        store: any SessionStoreProtocol,
        queue: FieldAnalysisQueue
    ) {
        self.cameraService = cameraService
        self.store = store
        self.queue = queue
    }

    // MARK: - Kamera

    func startCamera() async {
        do {
            try await cameraService.startSession()
        } catch CameraError.permissionDenied {
            permissionDenied = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopCamera() {
        stopScan()
        cameraService.stopSession()
    }

    // MARK: - Loop scan

    func toggleScan(session: ExamSession) {
        if isScanning { stopScan() } else { startScan(session: session) }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    private func startScan(session: ExamSession) {
        guard !isScanning else { return }
        isScanning = true

        scanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, session.fields.count < ExamSession.batchTarget {
                await self.captureField(session: session)
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(self.scanIntervalMilliseconds))
            }
            self.isScanning = false
        }
    }

    // MARK: - Satu lapang

    /// Merekam satu lapang: potret → potong → tulis → catat → antre.
    ///
    /// Urutannya penting. Lapang baru dicatat ke sesi **setelah** berkasnya tertulis, supaya
    /// disk yang penuh tidak meninggalkan lapang yang gambarnya tidak ada. Dan lapang selalu
    /// dicatat kalau berkasnya tersimpan — ada BTA maupun tidak. Auto-scan lama hanya menambah
    /// ketika modelnya menemukan sesuatu, sehingga lapang kosong tidak pernah masuk penyebut
    /// dan grade Negatif secara struktural tidak bisa dicapai.
    func captureField(session: ExamSession) async {
        do {
            let raw = try await cameraService.captureImage()
            guard !raw.isEmpty else { throw CameraError.captureFailed }

            guard let image = UIImage(data: raw),
                  let jpeg = FieldFraming.analysisJPEG(of: image)
            else { throw CameraError.captureFailed }

            updateFocus(from: jpeg)

            let fileName = String(format: "field-%03d.jpg", session.fields.count)
            try store.writeFieldImage(jpeg, fileName: fileName, for: session)

            let field = session.appendField(imageFileName: fileName)
            try await store.save(session)
            queue.enqueue(fieldID: field.id, imageData: jpeg, into: session)

            scanLog.note("lapang \(field.index) direkam, \(jpeg.count) bita")
        } catch {
            errorMessage = error.localizedDescription
            scanLog.error("Rekam lapang gagal: \(error.localizedDescription)")
        }
    }

    private func updateFocus(from jpeg: Data) {
        guard let image = UIImage(data: jpeg) else { return }
        lastSharpness = FocusMetric.sharpness(of: image)
        isBlurry = FocusMetric.isBlurry(lastSharpness)
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ScanViewModelTests 2>&1 | tail -25
```

Diharapkan: LULUS, 8 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Features/Scan/ScanViewModel.swift BacilabTests/ScanViewModelTests.swift
git commit -m "fix: count every scanned field, including empty ones"
```

---

## Task 11: ScanView

**Files:**
- Create: `Bacilab/Features/Scan/ScanView.swift`
- Move: `Bacilab/Features/Capture/Components/CameraPreviewView.swift` → `Bacilab/Features/Scan/Components/CameraPreviewView.swift`
- Test: build + `#Preview`

**Interfaces:**
- Consumes: `ScanViewModel` (Task 10), `ExamSession`, `AppDependencies`
- Produces: `ScanView(session: ExamSession, dependencies: AppDependencies)` — meneruskan ke `ReviewView` (Task 14)

Layar paling sedikit isinya di seluruh app, dan itu disengaja. Yang tampil hanya: viewfinder, hitungan lapang, peringatan fokus, kontrol scan, dan Selesai. **Tidak ada** hitungan BTA, grade pill, confidence, picker model, atau kolom perbandingan — semuanya milik Review.

Viewfinder **kotak** dengan lingkaran tipis sebagai panduan. Kotak itu persis crop yang diterima model, jadi semua yang ditampilkan dianalisis dan semua yang dianalisis ditampilkan. Masker lingkaran akan menutupi π/4 ≈ 78,5% luasnya, menyisakan 21,5% area yang tetap dihitung tapi tidak pernah terlihat.

Dikerjakan setelah Task 14 (lihat Urutan Eksekusi), jadi `ReviewView` sudah ada saat task ini dimulai.

- [ ] **Step 1: Pindahkan CameraPreviewView**

```bash
mkdir -p Bacilab/Features/Scan/Components
git mv Bacilab/Features/Capture/Components/CameraPreviewView.swift \
       Bacilab/Features/Scan/Components/CameraPreviewView.swift
```

Isinya tidak diubah. Di Xcode, pastikan berkas yang dipindahkan tetap menjadi anggota target `Bacilab` — `git mv` tidak memperbarui `project.pbxproj`, jadi hapus referensi merahnya lalu tambahkan kembali dari lokasi baru.

- [ ] **Step 2: Buat ScanView**

`Bacilab/Features/Scan/ScanView.swift`:

```swift
import SwiftUI

/// Sesi scan. Menghasilkan lapang, dan tidak tahu apa-apa tentang BTA.
///
/// Kekosongan layar ini disengaja: teknisi sedang menempel di okuler, bukan menatap layar.
/// Hitungan, grade, perbandingan model, dan confidence semuanya ada di Review, tempat ia
/// sudah duduk dan sedang memutuskan.
struct ScanView: View {
    @Bindable var session: ExamSession
    @State private var viewModel: ScanViewModel
    let dependencies: AppDependencies
    @State private var goToReview = false

    init(session: ExamSession, dependencies: AppDependencies) {
        self.session = session
        self.dependencies = dependencies
        _viewModel = State(initialValue: ScanViewModel(
            cameraService: dependencies.cameraService,
            store: dependencies.sessionStore,
            queue: dependencies.makeAnalysisQueue()
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width - 32, 360)

            VStack(spacing: 0) {
                fieldCounter
                Spacer(minLength: 20)
                viewfinder(side: side)
                focusBadge.padding(.top, 14)
                Spacer(minLength: 20)
                controls
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 32))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Sesi Pemeriksaan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToReview) {
            ReviewView(session: session, queue: viewModel.queue, dependencies: dependencies)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Izin Kamera Diperlukan", isPresented: $viewModel.permissionDenied) {
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Aplikasi tidak dapat mengakses kamera untuk memindai preparat. "
                 + "Aktifkan izin kamera di Pengaturan, lalu buka kembali layar ini.")
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    // MARK: - Bagian

    private var fieldCounter: some View {
        VStack(spacing: 4) {
            Text("\(session.fields.count) dari \(ExamSession.batchTarget) lapang")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())

            ProgressView(
                value: Double(min(session.fields.count, ExamSession.batchTarget)),
                total: Double(ExamSession.batchTarget)
            )
            .tint(Color.accentColor)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    /// Kotak, bukan lingkaran.
    ///
    /// Preview layer memakai `resizeAspectFill`, jadi kotak ini persis crop yang diterima
    /// model. Lingkaran putus-putus di dalamnya hanya panduan mengarahkan okuler — ia tidak
    /// memotong apa pun. Masker lingkaran akan menyembunyikan sudut-sudut kotak ini (sekitar
    /// 21% luasnya), padahal area itu tetap dibaca dan dihitung model.
    private func viewfinder(side: CGFloat) -> some View {
        ZStack {
            #if targetEnvironment(simulator)
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center, startRadius: 0, endRadius: side * 0.53
            )
            Text("Simulator")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            #else
            CameraPreviewView(session: viewModel.session)
            #endif

            Circle()
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                        lineWidth: viewModel.isScanning ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
    }

    private var focusBadge: some View {
        Group {
            if viewModel.isBlurry {
                Label("Fokus belum tajam", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Fokus tajam", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBlurry)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.toggleScan(session: session)
            } label: {
                ZStack {
                    Circle()
                        .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                                lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(viewModel.isScanning ? Color.accentColor : Color(.systemGray6))
                        .frame(width: 68, height: 68)
                    Image(systemName: viewModel.isScanning ? "stop.fill" : "viewfinder.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.isScanning ? .white : Color.accentColor)
                }
            }

            Text(viewModel.isScanning ? "Ketuk untuk berhenti" : "Mulai Scan")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if !session.fields.isEmpty {
                Button {
                    viewModel.stopScan()
                    session.status = .reviewing
                    goToReview = true
                } label: {
                    Text("Selesai · Lanjut ke Review")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
        }
    }
}

#Preview("Sesi – belum ada lapang") {
    NavigationStack {
        ScanView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Sesi – 8 lapang") {
    let session = ExamSession()
    for _ in 0..<8 { session.appendField(imageFileName: "f.jpg") }
    return NavigationStack {
        ScanView(session: session, dependencies: AppDependencies())
    }
}
```

- [ ] **Step 3: Build dan jalankan seluruh test**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Diharapkan: BUILD SUCCEEDED, semua test lulus.

- [ ] **Step 4: Periksa `#Preview`**

Yang dilihat: viewfinder **persegi** dengan lingkaran putus-putus di dalamnya, progress "0 dari 20" / "8 dari 20", dan tidak ada satu pun angka BTA atau grade di layar.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Features/Scan/ Bacilab/Features/PatientData/PatientDataView.swift Bacilab.xcodeproj
git commit -m "feat: add BTA-blind scan screen with square viewfinder"
```

---

## Task 12: ReviewViewModel

**Files:**
- Create: `Bacilab/Features/Review/ReviewViewModel.swift`
- Test: `BacilabTests/ReviewViewModelTests.swift`

**Interfaces:**
- Consumes: `ExamSession`, `SessionStoreProtocol`, `FieldAnalysisQueue`
- Produces: `@MainActor @Observable final class ReviewViewModel` dengan `init(session:store:queue:)` dan:
  - navigasi: `selectedFieldID`, `selectedField`, `selectedIndex`, `select(_:)`, `selectNext()`, `selectPrevious()`
  - keypad: `keypadText`, `isKeypadPresented`, `openKeypad()`, `appendDigit(_:)`, `deleteDigit()`, `commitKeypad()`, `cancelKeypad()`, `clearCorrection()`
  - lapang: `toggleExcludedOnSelected()`
  - grade: `chooseGrade(_:)`
  - terbit: `unresolvedFields`, `publish() async`, `isPublished`, `isPublishing`, `errorMessage`
  - gambar: `imageData(for:) -> Data?`

Satu-satunya layar yang memutuskan. Semua koreksi langsung tersimpan — tidak ada tombol simpan yang bisa terlewat, dan karenanya tidak ada keadaan di mana angka di layar berbeda dari angka yang tersimpan.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/ReviewViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

/// Review adalah satu-satunya pemilik hitungan dan grade. Yang diuji: koreksi tersimpan
/// tanpa langkah tambahan, dan terbit tidak pernah diam-diam menelan lapang yang belum
/// punya angka.
@MainActor
struct ReviewViewModelTests {

    private final class SpyStore: SessionStoreProtocol, @unchecked Sendable {
        var savedCount = 0
        var saveError: Error?
        func allSessions() async throws -> [ExamSession] { [] }
        func save(_ session: ExamSession) async throws {
            if let saveError { throw saveError }
            savedCount += 1
        }
        func delete(_ session: ExamSession) async throws {}
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {}
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    private final class SilentAnalysis: AnalysisServiceProtocol, @unchecked Sendable {
        func analyze(imageData: Data) async throws -> AnalysisResult {
            AnalysisResult(btaCount: 0, confidence: 0, grade: .negative, analyzedAt: Date())
        }
    }

    private func analysis(_ count: Int, failure: String? = nil) -> FieldAnalysis {
        FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5, failure: failure)],
            primary: .resnet
        )
    }

    private func makeSession(counts: [Int]) -> ExamSession {
        let session = ExamSession()
        for c in counts {
            let f = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(analysis(c), for: f.id)
        }
        return session
    }

    private func makeViewModel(_ session: ExamSession, store: SpyStore = SpyStore()) -> ReviewViewModel {
        ReviewViewModel(
            session: session,
            store: store,
            queue: FieldAnalysisQueue(analysisService: SilentAnalysis())
        )
    }

    @Test("Lapang pertama terpilih saat review dibuka")
    func firstFieldSelectedInitially() {
        let vm = makeViewModel(makeSession(counts: [3, 5, 1]))
        #expect(vm.selectedIndex == 0)
        #expect(vm.selectedField?.index == 0)
    }

    @Test("Navigasi maju-mundur berhenti di ujung")
    func navigationClampsAtEnds() {
        let vm = makeViewModel(makeSession(counts: [1, 2, 3]))

        vm.selectPrevious()
        #expect(vm.selectedIndex == 0, "Tidak boleh lewat dari lapang pertama")

        vm.selectNext(); vm.selectNext(); vm.selectNext(); vm.selectNext()
        #expect(vm.selectedIndex == 2, "Tidak boleh lewat dari lapang terakhir")
    }

    @Test("Keypad menulis koreksi ke lapang terpilih")
    func keypadWritesCorrection() {
        let session = makeSession(counts: [9, 9])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.appendDigit("1"); vm.appendDigit("2")
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == 12)
        #expect(session.totalBTA == 21, "12 + 9")
        #expect(!vm.isKeypadPresented)
    }

    @Test("Koreksi nol tersimpan sebagai nol, bukan diabaikan")
    func zeroCorrectionIsStored() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.appendDigit("0")
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == 0)
        #expect(session.totalBTA == 0)
        #expect(session.examinedFieldCount == 1, "Nol tetap lapang yang terbaca")
    }

    @Test("Keypad kosong yang dikonfirmasi tidak mengubah apa pun")
    func emptyKeypadIsNoop() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.commitKeypad()

        #expect(session.fields[0].correctedCount == nil)
        #expect(session.totalBTA == 7)
    }

    @Test("Hapus digit dan batal tidak menyentuh lapang")
    func deleteAndCancel() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad()
        vm.appendDigit("5"); vm.appendDigit("5")
        vm.deleteDigit()
        #expect(vm.keypadText == "5")

        vm.cancelKeypad()
        #expect(session.fields[0].correctedCount == nil)
        #expect(!vm.isKeypadPresented)
    }

    @Test("Koreksi bisa dikembalikan ke hitungan model")
    func correctionCanBeCleared() {
        let session = makeSession(counts: [7])
        let vm = makeViewModel(session)

        vm.openKeypad(); vm.appendDigit("2"); vm.commitKeypad()
        #expect(session.totalBTA == 2)

        vm.clearCorrection()
        #expect(session.fields[0].correctedCount == nil)
        #expect(session.totalBTA == 7, "Kembali ke angka model")
    }

    @Test("Membuang lapang mengubah total dan penyebut sekaligus")
    func excludingChangesBothSides() {
        let session = makeSession(counts: [4, 4, 4])
        let vm = makeViewModel(session)

        vm.toggleExcludedOnSelected()

        #expect(session.totalBTA == 8)
        #expect(session.examinedFieldCount == 2)

        vm.toggleExcludedOnSelected()
        #expect(session.examinedFieldCount == 3, "Bisa dikembalikan")
    }

    @Test("Grade yang dipilih tersimpan di sesi")
    func gradeIsRecorded() {
        let session = makeSession(counts: [1])
        let vm = makeViewModel(session)

        vm.chooseGrade(.plus2)

        #expect(session.chosenGrade == .plus2)
        #expect(session.reportedGrade == .plus2)
    }

    @Test("Lapang gagal terdaftar sebagai belum selesai")
    func unresolvedFieldsAreListed() {
        let session = ExamSession()
        let ok = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(3), for: ok.id)
        let broken = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(analysis(0, failure: "ORT gagal"), for: broken.id)
        _ = session.appendField(imageFileName: "f.jpg")   // masih diantre

        let vm = makeViewModel(session)

        #expect(vm.unresolvedFields.count == 2,
                "Yang gagal maupun yang belum dianalisis sama-sama belum punya angka")
    }

    @Test("Terbit mengubah status dan menyimpan sesi")
    func publishSavesAndMarksPublished() async {
        let store = SpyStore()
        let session = makeSession(counts: [2, 2])
        let vm = makeViewModel(session, store: store)

        await vm.publish()

        #expect(session.status == .published)
        #expect(vm.isPublished)
        #expect(store.savedCount == 1)
        #expect(vm.errorMessage == nil)
    }

    @Test("Terbit yang gagal disimpan tidak berpura-pura berhasil")
    func failedPublishIsReported() async {
        let store = SpyStore()
        store.saveError = CocoaError(.fileWriteOutOfSpace)
        let session = makeSession(counts: [2])
        let vm = makeViewModel(session, store: store)

        await vm.publish()

        #expect(!vm.isPublished, "Hasil yang tidak tersimpan tidak boleh tampak terbit")
        #expect(vm.errorMessage != nil)
        #expect(session.status != .published)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ReviewViewModelTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `ReviewViewModel` belum ada.

- [ ] **Step 3: Buat ReviewViewModel**

`Bacilab/Features/Review/ReviewViewModel.swift`:

```swift
import Foundation
import Observation

private let reviewLog = Diag("review")

/// Satu-satunya layar yang memutuskan: berapa BTA di tiap lapang, lapang mana yang dibuang,
/// grade apa yang dilaporkan, dan kapan hasilnya terbit.
///
/// Setiap koreksi langsung mengubah sesi dan langsung tersimpan. Tidak ada tombol simpan yang
/// bisa terlewat, jadi tidak pernah ada keadaan di mana angka di layar berbeda dari angka
/// yang tersimpan.
@MainActor
@Observable
final class ReviewViewModel {

    let session: ExamSession
    let queue: FieldAnalysisQueue
    private let store: any SessionStoreProtocol

    var selectedFieldID: UUID?
    var keypadText = ""
    var isKeypadPresented = false
    var errorMessage: String?
    var isPublishing = false
    private(set) var isPublished = false

    /// Hitungan satu lapang tidak pernah mencapai lima digit; batas ini hanya menahan
    /// ketukan beruntun yang tidak disengaja.
    private let maxKeypadDigits = 4

    init(
        session: ExamSession,
        store: any SessionStoreProtocol,
        queue: FieldAnalysisQueue
    ) {
        self.session = session
        self.store = store
        self.queue = queue
        self.selectedFieldID = session.fields.first?.id
    }

    // MARK: - Navigasi

    var selectedField: FieldRecord? {
        guard let selectedFieldID else { return session.fields.first }
        return session.field(withID: selectedFieldID)
    }

    var selectedIndex: Int {
        guard let selectedField else { return 0 }
        return session.fields.firstIndex { $0.id == selectedField.id } ?? 0
    }

    func select(_ id: UUID) { selectedFieldID = id }

    func selectNext() {
        let next = min(selectedIndex + 1, session.fields.count - 1)
        guard next >= 0, session.fields.indices.contains(next) else { return }
        selectedFieldID = session.fields[next].id
    }

    func selectPrevious() {
        let previous = max(selectedIndex - 1, 0)
        guard session.fields.indices.contains(previous) else { return }
        selectedFieldID = session.fields[previous].id
    }

    // MARK: - Keypad

    func openKeypad() {
        keypadText = ""
        isKeypadPresented = true
    }

    func appendDigit(_ digit: String) {
        guard keypadText.count < maxKeypadDigits else { return }
        keypadText.append(digit)
    }

    func deleteDigit() {
        guard !keypadText.isEmpty else { return }
        keypadText.removeLast()
    }

    func cancelKeypad() {
        keypadText = ""
        isKeypadPresented = false
    }

    /// Menyimpan angka yang diketik sebagai hitungan lapang terpilih.
    ///
    /// Keypad kosong sengaja tidak melakukan apa-apa: mengosongkan lalu menekan konfirmasi
    /// bukan cara menyatakan "nol". Untuk nol, ketik `0` — dan nol itu memang tersimpan
    /// sebagai nol, bukan diabaikan sebagai "tidak ada koreksi".
    func commitKeypad() {
        defer { isKeypadPresented = false }
        guard let field = selectedField, let value = Int(keypadText) else {
            keypadText = ""
            return
        }
        session.setCorrectedCount(value, for: field.id)
        keypadText = ""
        persist()
    }

    /// Mengembalikan lapang ke hitungan model.
    func clearCorrection() {
        guard let field = selectedField else { return }
        session.setCorrectedCount(nil, for: field.id)
        persist()
    }

    // MARK: - Lapang

    func toggleExcludedOnSelected() {
        guard let field = selectedField else { return }
        session.setExcluded(!field.isExcluded, for: field.id)
        persist()
    }

    // MARK: - Grade

    func chooseGrade(_ grade: BTAGrade) {
        session.chooseGrade(grade)
        persist()
    }

    // MARK: - Terbit

    /// Lapang yang belum punya angka: gagal dianalisis, atau masih menunggu antrean.
    /// Keduanya keluar dari pembilang dan penyebut, jadi analis harus tahu sebelum terbit.
    var unresolvedFields: [FieldRecord] {
        session.fields.filter { !$0.isExcluded && $0.effectiveCount == nil }
    }

    func publish() async {
        isPublishing = true
        defer { isPublishing = false }

        let previousStatus = session.status
        session.status = .published
        do {
            try await store.save(session)
            isPublished = true
        } catch {
            // Kembalikan statusnya: hasil yang gagal tersimpan tidak boleh tampak terbit.
            session.status = previousStatus
            errorMessage = error.localizedDescription
            reviewLog.error("Terbit gagal: \(error.localizedDescription)")
        }
    }

    // MARK: - Gambar

    func imageData(for field: FieldRecord) -> Data? {
        try? Data(contentsOf: store.fieldImageURL(fileName: field.imageFileName, for: session))
    }

    // MARK: - Simpan

    /// Autosave setelah setiap perubahan. Kegagalannya dilaporkan tapi tidak membatalkan
    /// perubahan di memori — analis tetap melihat apa yang baru saja ia ketik.
    private func persist() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.save(self.session)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 4: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/ReviewViewModelTests 2>&1 | tail -25
```

Diharapkan: LULUS, 13 test.

- [ ] **Step 5: Commit**

```bash
git add Bacilab/Features/Review/ReviewViewModel.swift BacilabTests/ReviewViewModelTests.swift
git commit -m "feat: add review view model owning counts, grade and publish"
```

---

## Task 13: Komponen Review

**Files:**
- Create: `Bacilab/Features/Review/Components/DetectorStyle.swift`
- Create: `Bacilab/Features/Review/Components/FieldCanvas.swift`
- Create: `Bacilab/Features/Review/Components/FieldPager.swift`
- Create: `Bacilab/Features/Review/Components/CountKeypad.swift`
- Test: `BacilabTests/DetectorStyleTests.swift` + `#Preview`

**Interfaces:**
- Consumes: `FieldRecord`, `DetectorKind`, `DetectedBox`, `BTAGrade`
- Produces:
  - `enum DetectorStyle` dengan `static func tint(for:) -> Color`, `static func dash(for:scale:) -> [CGFloat]`
  - `FieldCanvas(image: UIImage?, readings: [DetectorReading], side: CGFloat)`
  - `FieldPager(fields: [FieldRecord], selectedID: UUID?, onSelect: (UUID) -> Void)`
  - `CountKeypad(text: String, onDigit: (String) -> Void, onDelete: () -> Void, onConfirm: () -> Void, onCancel: () -> Void)`

Tiga komponen kecil supaya `ReviewView` tetap bisa dibaca utuh. Aturan penting di `FieldCanvas`: box dari semua model diratakan ke **satu** `ForEach` dengan id eksplisit seperti `"ResNet-3"`. Setiap model menomori box-nya dari 0, jadi `ForEach` bersarang membuat id di lapisan dalam bertabrakan dan SwiftUI menggambar kotak yang salah.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/DetectorStyleTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Bacilab

/// Tiga model digambar di atas lapang yang sama. Warna saja tidak cukup memisahkan tiga
/// kategori — pembaca buta warna dan tangkapan layar hitam-putih tetap harus bisa
/// membedakannya, jadi tiap model juga punya pola garis sendiri.
struct DetectorStyleTests {

    @Test("Setiap model punya warna berbeda")
    func tintsAreDistinct() {
        let tints = DetectorKind.allCases.map { DetectorStyle.tint(for: $0).description }
        #expect(Set(tints).count == DetectorKind.allCases.count)
    }

    @Test("Setiap model punya pola garis berbeda")
    func dashesAreDistinct() {
        let dashes = DetectorKind.allCases.map { DetectorStyle.dash(for: $0) }
        #expect(dashes[0] != dashes[1])
        #expect(dashes[1] != dashes[2])
        #expect(dashes[0] != dashes[2])
    }

    @Test("Pola garis ikut diperkecil bersama skalanya")
    func dashScales() {
        let full = DetectorStyle.dash(for: .yolo, scale: 1)
        let half = DetectorStyle.dash(for: .yolo, scale: 0.5)
        #expect(half == full.map { $0 * 0.5 })
    }

    /// Setiap model menomori kotaknya dari 0. Kalau id kotak hanya nomor itu, kotak ResNet
    /// nomor 3 dan kotak YOLO nomor 3 punya id yang sama, dan SwiftUI akan menggambar salah
    /// satunya di tempat yang lain.
    @Test("Id kotak tidak bertabrakan antar model")
    func markerIdentitiesAreUniqueAcrossModels() {
        let box = DetectedBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.05, angle: 0)
        let readings = DetectorKind.allCases.map { kind in
            DetectorReading(detector: kind, btaCount: 4, confidence: 0.8, elapsed: 0.1,
                            boxes: Array(repeating: box, count: 4))
        }

        let ids = FieldCanvas.markers(for: readings).map(\.id)

        #expect(ids.count == 12)
        #expect(Set(ids).count == 12, "Ada id kotak yang bertabrakan antar model")
    }

    @Test("Jumlah kotak yang digambar dibatasi per model")
    func boxesAreCappedPerModel() {
        let box = DetectedBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.05, angle: 0)
        let reading = DetectorReading(
            detector: .resnet, btaCount: 500, confidence: 0.8, elapsed: 0.1,
            boxes: Array(repeating: box, count: 500)
        )

        #expect(FieldCanvas.markers(for: [reading]).count == FieldCanvas.boxDisplayLimit)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/DetectorStyleTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `DetectorStyle` belum ada.

- [ ] **Step 3: Buat DetectorStyle**

`Bacilab/Features/Review/Components/DetectorStyle.swift`:

```swift
import SwiftUI

/// Satu warna dan satu pola garis per model, dipakai baik oleh box di atas gambar maupun
/// oleh angka di bawahnya — supaya analis tidak perlu menebak box mana milik angka mana.
///
/// Pola garis bukan hiasan: warna saja tidak bisa memisahkan tiga kategori untuk pembaca
/// buta warna, dan tangkapan layar hitam-putih sering jadi satu-satunya yang tersisa ketika
/// sebuah hasil dipertanyakan.
enum DetectorStyle {

    static func tint(for detector: DetectorKind) -> Color {
        switch detector {
        case .resnet: return .red
        case .yolo:   return .cyan
        case .yolo11: return .yellow
        }
    }

    static func dash(for detector: DetectorKind, scale: CGFloat = 1) -> [CGFloat] {
        switch detector {
        case .resnet: return []
        case .yolo:   return [4 * scale, 3 * scale]
        case .yolo11: return [1.5 * scale, 2.5 * scale]
        }
    }
}
```

- [ ] **Step 4: Buat FieldCanvas**

`Bacilab/Features/Review/Components/FieldCanvas.swift`:

```swift
import SwiftUI

/// Gambar satu lapang dengan box tiap model di atasnya.
///
/// Gambar yang ditampilkan adalah crop persegi yang persis diterima model, jadi koordinat box
/// yang ternormalisasi jatuh tepat di tempatnya. Menggambar box di atas gambar lain — foto
/// mentah, atau preview langsung — akan menempatkannya di atas basil yang bukan itu.
///
/// Bingkainya **kotak**, dengan lingkaran putus-putus sebagai panduan okuler. Masker lingkaran
/// akan menyembunyikan sudut-sudutnya, sekitar 21% dari luas yang tetap dibaca model.
struct FieldCanvas: View {
    let image: UIImage?
    let readings: [DetectorReading]
    let side: CGFloat

    /// Satu box siap gambar, ditandai model asalnya.
    ///
    /// Semua model diratakan ke satu daftar dengan id eksplisit. `ForEach` bersarang —
    /// satu per bacaan, satu per box di dalamnya — membuat id lapisan dalam (`0, 1, 2…`)
    /// berulang untuk tiap model, dan SwiftUI akan menggambar kotak yang salah.
    struct Marker: Identifiable {
        let id: String
        let detector: DetectorKind
        let box: DetectedBox
    }

    /// Berapa banyak box per model yang digambar.
    ///
    /// Batas tampilan murni supaya lapang yang sangat padat tidak menaruh ribuan bentuk di
    /// layar. **Tidak pernah menyentuh hitungan** — angka BTA tetap dari model, bukan dari
    /// berapa kotak yang sempat digambar.
    static let boxDisplayLimit = 120

    /// Dibuat sebagai fungsi statis, bukan properti privat, supaya invarian id-nya bisa diuji
    /// tanpa merender view.
    static func markers(for readings: [DetectorReading]) -> [Marker] {
        readings.flatMap { reading in
            reading.boxes.prefix(boxDisplayLimit).enumerated().map { index, box in
                Marker(id: "\(reading.detector.rawValue)-\(index)",
                       detector: reading.detector, box: box)
            }
        }
    }

    private var markers: [Marker] { Self.markers(for: readings) }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        ProgressView()
                    }
            }

            ForEach(markers) { marker in
                Rectangle()
                    .stroke(
                        DetectorStyle.tint(for: marker.detector),
                        style: StrokeStyle(lineWidth: 2,
                                           dash: DetectorStyle.dash(for: marker.detector))
                    )
                    .frame(
                        width: max(CGFloat(marker.box.w) * side, 8),
                        height: max(CGFloat(marker.box.h) * side, 8)
                    )
                    .rotationEffect(.radians(Double(marker.box.angle)))
                    .offset(
                        x: CGFloat(marker.box.cx - 0.5) * side,
                        y: CGFloat(marker.box.cy - 0.5) * side
                    )
            }

            Circle()
                .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray3), lineWidth: 1))
    }
}

#Preview("Field canvas") {
    FieldCanvas(
        image: nil,
        readings: [
            DetectorReading(detector: .resnet, btaCount: 2, confidence: 0.9, elapsed: 0.6,
                            boxes: [DetectedBox(cx: 0.35, cy: 0.4, w: 0.08, h: 0.03, angle: 0.5),
                                    DetectedBox(cx: 0.6, cy: 0.65, w: 0.07, h: 0.03, angle: -0.3)])
        ],
        side: 300
    )
    .padding()
}
```

- [ ] **Step 5: Buat FieldPager**

`Bacilab/Features/Review/Components/FieldPager.swift`:

```swift
import SwiftUI

/// Deretan nomor lapang, satu dot per lapang.
///
/// Dot bertanda oranye adalah lapang yang belum punya angka — gagal dianalisis atau masih
/// diantre. Keduanya keluar dari pembilang dan penyebut, jadi analis harus bisa menemukannya
/// tanpa membuka satu per satu.
struct FieldPager: View {
    let fields: [FieldRecord]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(fields) { field in
                        dot(for: field)
                            .id(field.id)
                            .onTapGesture { onSelect(field.id) }
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedID) { _, new in
                guard let new else { return }
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func dot(for field: FieldRecord) -> some View {
        let isSelected = field.id == selectedID
        let needsAttention = !field.isExcluded && field.effectiveCount == nil

        return ZStack(alignment: .topTrailing) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color(.systemGray5))
                .frame(width: 34, height: 34)
                .overlay {
                    Text("\(field.index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .overlay {
                    // Lapang yang dibuang tetap terlihat, tapi dicoret — menghilangkannya
                    // akan membuat penomoran melompat dan analis kehilangan jejak.
                    if field.isExcluded {
                        Circle().stroke(Color(.systemGray), lineWidth: 1)
                        Rectangle()
                            .fill(Color(.systemGray))
                            .frame(width: 24, height: 1.5)
                            .rotationEffect(.degrees(-45))
                    }
                }
                .opacity(field.isExcluded ? 0.45 : 1)

            if needsAttention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .frame(width: 38, height: 38)
    }
}

#Preview("Field pager") {
    let session = ExamSession()
    for i in 0..<8 {
        let f = session.appendField(imageFileName: "f.jpg")
        if i != 3 {
            session.setAnalysis(FieldAnalysis(
                readings: [DetectorReading(detector: .resnet, btaCount: i,
                                           confidence: 0.8, elapsed: 0.4)],
                primary: .resnet), for: f.id)
        }
        if i == 5 { session.setExcluded(true, for: f.id) }
    }
    return FieldPager(fields: session.fields,
                      selectedID: session.fields.first?.id,
                      onSelect: { _ in })
        .padding(.vertical)
}
```

- [ ] **Step 6: Buat CountKeypad**

`Bacilab/Features/Review/Components/CountKeypad.swift`:

```swift
import SwiftUI

/// Keypad numerik untuk mengganti hitungan satu lapang.
///
/// Mengganti angka, bukan menaik-turunkannya: layar lama memakai tombol ± pada total lintas
/// seluruh lapang, sehingga mengoreksi hitungan 400 berarti 400 ketukan.
struct CountKeypad: View {
    let text: String
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 14) {
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .frame(height: 54)
                .contentTransition(.numericText())

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        key(digit) { onDigit(digit) }
                    }
                }
            }

            HStack(spacing: 10) {
                key("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(.primary)
            }

            HStack(spacing: 10) {
                Button("Batal", action: onCancel)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.secondary)

                Button("Simpan", action: onConfirm)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
            }
        }
        .padding(20)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.primary)
    }
}

#Preview("Keypad") {
    CountKeypad(text: "12", onDigit: { _ in }, onDelete: {}, onConfirm: {}, onCancel: {})
}
```

- [ ] **Step 7: Jalankan test dan periksa preview**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/DetectorStyleTests 2>&1 | tail -25
```

Diharapkan: LULUS, 5 test. Lalu periksa ketiga `#Preview` di Xcode — pada `FieldPager` yang dilihat: dot ke-4 bertanda oranye (belum dianalisis) dan dot ke-6 tercoret (dibuang).

- [ ] **Step 8: Commit**

```bash
git add Bacilab/Features/Review/Components/ BacilabTests/DetectorStyleTests.swift
git commit -m "feat: add review components — pager, canvas, keypad"
```

---

## Task 14: ReviewView

**Files:**
- Create: `Bacilab/Features/Review/ReviewView.swift`
- Test: build + `#Preview`

**Interfaces:**
- Consumes: `ReviewViewModel` (Task 12), komponen (Task 13), `FieldAnalysisQueue`, `AppDependencies`
- Produces: `ReviewView(session: ExamSession, queue: FieldAnalysisQueue, dependencies: AppDependencies)` — meneruskan ke `ResultSheetView` (Task 15)

Dikerjakan setelah Task 15 (lihat Urutan Eksekusi), jadi `ResultSheetView` sudah ada saat task ini dimulai.

**Lanjut Scan:** menyetel `session.status = .scanning` lalu `dismiss()`. Review selalu di-push dari `ScanView`, jadi menutupnya mengembalikan analis ke sesi yang sama, dengan lapang yang sudah ada tetap utuh.

- [ ] **Step 1: Buat ReviewView**

`Bacilab/Features/Review/ReviewView.swift`:

```swift
import SwiftUI

/// Satu-satunya layar yang memutuskan.
///
/// Di sini analis memeriksa tiap lapang, mengoreksi hitungannya, membuang lapang yang tidak
/// layak, memilih grade, dan menerbitkan hasil. Sesi scan tidak punya satu pun dari itu.
struct ReviewView: View {
    @State private var viewModel: ReviewViewModel
    let dependencies: AppDependencies

    @Environment(\.dismiss) private var dismiss
    @State private var goToResult = false
    @State private var showUnresolvedWarning = false

    init(session: ExamSession, queue: FieldAnalysisQueue, dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ReviewViewModel(
            session: session,
            store: dependencies.sessionStore,
            queue: queue
        ))
    }

    private var session: ExamSession { viewModel.session }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.queue.remaining > 0 {
                    analysisProgress
                }

                FieldPager(
                    fields: session.fields,
                    selectedID: viewModel.selectedField?.id,
                    onSelect: { viewModel.select($0) }
                )

                fieldCanvas
                fieldCountRow
                fieldActions

                Divider().padding(.vertical, 4)

                totalsSection
                gradeSection
                notesSection
                publishButton
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToResult) {
            ResultSheetView(session: session, dependencies: dependencies)
        }
        .sheet(isPresented: $viewModel.isKeypadPresented) {
            CountKeypad(
                text: viewModel.keypadText,
                onDigit: { viewModel.appendDigit($0) },
                onDelete: { viewModel.deleteDigit() },
                onConfirm: { viewModel.commitKeypad() },
                onCancel: { viewModel.cancelKeypad() }
            )
            .presentationDetents([.medium])
        }
        .alert("Masih ada lapang tanpa hitungan", isPresented: $showUnresolvedWarning) {
            Button("Terbitkan Saja", role: .destructive) { publish() }
            Button("Periksa Dulu", role: .cancel) {}
        } message: {
            Text("\(viewModel.unresolvedFields.count) lapang belum punya angka dan tidak ikut "
                 + "dihitung — baik pembilang maupun penyebutnya. Isi lewat keypad, atau buang "
                 + "lapangnya, supaya hasilnya mewakili apa yang benar-benar dibaca.")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Antrean

    private var analysisProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Menganalisis \(session.fields.count - viewModel.queue.remaining) "
                 + "dari \(session.fields.count) lapang…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    // MARK: - Lapang terpilih

    private var fieldCanvas: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 40, 320)
            HStack {
                Spacer()
                FieldCanvas(
                    image: viewModel.selectedField.flatMap { field in
                        viewModel.imageData(for: field).flatMap(UIImage.init(data:))
                    },
                    readings: viewModel.selectedField?.analysis?.readings ?? [],
                    side: side
                )
                Spacer()
            }
        }
        .frame(height: min(UIScreen.main.bounds.width - 40, 320))
    }

    private var fieldCountRow: some View {
        VStack(spacing: 8) {
            Button {
                viewModel.openKeypad()
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(countLabel)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .contentTransition(.numericText())
                    Text("BTA")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .foregroundStyle(.primary)

            confidenceLine
        }
    }

    private var countLabel: String {
        guard let field = viewModel.selectedField else { return "—" }
        if field.isExcluded { return "—" }
        guard let count = field.effectiveCount else { return "—" }
        return "\(count)"
    }

    /// Confidence ditampilkan sebagai milik model, bukan sebagai kepastian hasil.
    ///
    /// Grafik ONNX sudah membuang deteksi di bawah 0,70, jadi angka ini tidak pernah bisa
    /// terbaca di bawah 70% betapapun lemahnya sebuah lapang. Ia menyatakan seberapa yakin
    /// model terhadap basil yang **ia simpan** — bukan seberapa yakin siapa pun terhadap
    /// hitungannya.
    @ViewBuilder
    private var confidenceLine: some View {
        if let field = viewModel.selectedField {
            if field.correctedCount != nil {
                Label("Dikoreksi analis", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if field.analysis == nil {
                Text("Menunggu analisis…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if field.effectiveCount == nil {
                Label("Model gagal membaca lapang ini — isi manual",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let confidence = field.analysis?.confidence {
                Text("Model yakin \(Int((confidence * 100).rounded()))% atas basil yang ia tandai")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fieldActions: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.selectPrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 40)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(viewModel.selectedIndex == 0)

            Button {
                viewModel.toggleExcludedOnSelected()
            } label: {
                Label(
                    viewModel.selectedField?.isExcluded == true ? "Pakai Lagi" : "Buang Lapang",
                    systemImage: viewModel.selectedField?.isExcluded == true
                        ? "arrow.uturn.backward" : "trash"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .foregroundStyle(viewModel.selectedField?.isExcluded == true ? Color.accentColor : .red)

            Button {
                viewModel.selectNext()
            } label: {
                Text("Simpan & Lanjut")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .disabled(viewModel.selectedIndex >= session.fields.count - 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Total

    private var totalsSection: some View {
        HStack(spacing: 0) {
            statCell(label: "Lapang Terbaca", value: "\(session.examinedFieldCount)")
            Divider().frame(height: 44)
            statCell(label: "Total BTA", value: "\(session.totalBTA)")
            Divider().frame(height: 44)
            statCell(label: "Usulan Model", value: session.suggestedGrade.rawValue)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grade

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tentukan Grade")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        Button {
                            viewModel.chooseGrade(grade)
                        } label: {
                            Text(grade.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(session.reportedGrade == grade
                                            ? Color.accentColor : Color(.systemGray5),
                                            in: Capsule())
                                .foregroundStyle(session.reportedGrade == grade ? .white : .primary)
                        }
                    }
                }
            }

            if !session.isGradeConfirmed {
                provisionalNotice
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    /// Di bawah ambang WHO/IUATLD grade ini belum boleh berdiri sebagai laporan.
    private var provisionalNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "\(session.reportedGrade.rawValue) memerlukan \(session.reportedGrade.minimumFields) "
                + "lapang (WHO/IUATLD). Kurang \(session.fieldsRemainingForGrade) lapang lagi — "
                + "hasil akan bercap SEMENTARA.",
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                session.status = .scanning
                dismiss()
            } label: {
                Label("Lanjut Scan", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Catatan

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catatan Laboratorium")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))

            TextEditor(text: Bindable(session).notes)
                .frame(minHeight: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    // MARK: - Terbit

    private var publishButton: some View {
        Button {
            if viewModel.unresolvedFields.isEmpty {
                publish()
            } else {
                showUnresolvedWarning = true
            }
        } label: {
            HStack {
                if viewModel.isPublishing { ProgressView().tint(.white) }
                Text("Terbitkan Hasil")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(viewModel.isPublishing || session.fields.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func publish() {
        Task {
            await viewModel.publish()
            if viewModel.isPublished { goToResult = true }
        }
    }
}

#Preview("Review – 6 lapang") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    for i in 0..<6 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: i * 2,
                                       confidence: 0.86, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    let deps = AppDependencies()
    return NavigationStack {
        ReviewView(session: session, queue: deps.makeAnalysisQueue(), dependencies: deps)
    }
}
```

- [ ] **Step 2: Build dan jalankan seluruh test**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Diharapkan: BUILD SUCCEEDED, semua test lulus.

- [ ] **Step 3: Periksa `#Preview`**

Yang dilihat: pager 6 dot, kanvas persegi, hitungan lapang yang bisa diketuk, total, pill grade, dan — karena 6 lapang jauh di bawah semua ambang — kotak peringatan SEMENTARA berisi tombol "Lanjut Scan".

- [ ] **Step 4: Commit**

```bash
git add Bacilab/Features/Review/ReviewView.swift Bacilab/Features/Scan/ScanView.swift
git commit -m "feat: add per-field review screen owning counts and grade"
```

---

## Task 15: ResultSheetView — lembar hasil read-only

**Files:**
- Create: `Bacilab/Features/ResultSheet/ResultSheetView.swift`
- Test: build + `#Preview`

**Interfaces:**
- Consumes: `ExamSession`, `AppDependencies`
- Produces: `ResultSheetView(session: ExamSession, dependencies: AppDependencies)`

Layar ini **dokumen, bukan langkah**. Ia juga tujuan ketika sebuah sampel diketuk dari beranda — layar yang sama, bukan sepupunya. Itu yang menghapus peran ganda `ResultView` lama, yang menampilkan tombol "Simpan Hasil" bahkan saat sedang membuka riwayat lama.

Tidak ada tombol simpan, tidak ada pill grade, tidak ada editor catatan. Semuanya sudah diputuskan di Review.

- [ ] **Step 1: Buat ResultSheetView**

`Bacilab/Features/ResultSheet/ResultSheetView.swift`:

```swift
import SwiftUI

/// Lembar hasil. Read-only, dan sengaja demikian.
///
/// Grade, hitungan, dan catatan semuanya diputuskan di Review. Kalau layar ini bisa mengubah
/// salah satunya, akan ada dua tempat yang menentukan grade lagi — persis tabrakan yang
/// rancangan ini hilangkan.
struct ResultSheetView: View {
    let session: ExamSession
    let dependencies: AppDependencies

    private var grade: BTAGrade { session.reportedGrade }

    private var gradeColor: Color {
        switch grade {
        case .negative:              return .green
        case .scanty:                return .orange
        case .plus1, .plus2, .plus3: return .red
        }
    }

    private var gradeLabel: String {
        switch grade {
        case .negative: return "Negatif"
        case .scanty:   return "Scanty (Borderline)"
        case .plus1:    return "Positif (1+)"
        case .plus2:    return "Positif (2+)"
        case .plus3:    return "Positif (3+)"
        }
    }

    private var gradeDescription: String {
        switch grade {
        case .negative: return "Tidak ditemukan BTA dalam 100 lapang pandang."
        case .scanty:   return "Ditemukan 1–9 BTA dalam 100 lapang pandang. Perlu pemeriksaan ulang."
        case .plus1:    return "Ditemukan 10–99 BTA dalam 100 lapang pandang."
        case .plus2:    return "Ditemukan 1–10 BTA per lapang pandang dalam setidaknya 50 lapang."
        case .plus3:    return "Ditemukan lebih dari 10 BTA per lapang pandang dalam setidaknya 20 lapang."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientSection
                resultSection
                statsSection
                if !session.notes.isEmpty { notesSection }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Lembar Hasil")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pasien

    private var patientSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Informasi Pasien")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 12)

            infoRow("Laboratorium", "Electra Lab")
            Divider().padding(.leading, 120)
            infoRow("No. Rekam Medis", session.patient.medicalRecordNumber)
            Divider().padding(.leading, 120)
            infoRow("NIK", session.patient.nationalID)
            Divider().padding(.leading, 120)
            infoRow("Nama", session.patient.name)
            Divider().padding(.leading, 120)
            infoRow("Tanggal Lahir", formatted(session.patient.dateOfBirth))
            Divider().padding(.leading, 120)
            infoRow("Tgl. Pemeriksaan", formatted(session.patient.examinationDate))
            Divider().padding(.leading, 120)
            infoRow("Waktu Ambil Sampel", formatted(session.patient.sampleCollectedAt, withTime: true))
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatted(_ date: Date, withTime: Bool = false) -> String {
        let locale = Locale(identifier: "id_ID")
        return withTime
            ? date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(locale))
            : date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Hasil

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hasil")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Label("Analisis AI bukan diagnosis medis", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: grade == .negative
                          ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                    Text(gradeLabel)
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Spacer()
                    if !session.isGradeConfirmed {
                        Text("SEMENTARA")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                }
                Text(gradeDescription)
                    .font(.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradeColor, in: RoundedRectangle(cornerRadius: 14))

            if !session.isGradeConfirmed {
                Label(
                    "Baru \(session.examinedFieldCount) lapang terbaca. \(grade.rawValue) memerlukan "
                    + "\(grade.minimumFields) lapang (WHO/IUATLD), jadi hasil ini belum final.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Statistik

    private var statsSection: some View {
        HStack(spacing: 0) {
            statCell(icon: "scope", label: "Lapang Terbaca", value: "\(session.examinedFieldCount)")
            Divider().frame(height: 56)
            statCell(icon: "microbe.fill", label: "Total BTA", value: "\(session.totalBTA)")
            Divider().frame(height: 56)
            statCell(icon: "hand.raised.fill", label: "Dikoreksi Analis",
                     value: "\(session.fields.filter { $0.correctedCount != nil }.count)")
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Catatan

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catatan Laboratorium")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(session.notes)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Lembar Hasil – 3+ final") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.status = .published
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 15,
                                       confidence: 0.9, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}

#Preview("Lembar Hasil – Negatif sementara") {
    let session = ExamSession()
    session.patient.name = "Siti Rahma"
    session.patient.medicalRecordNumber = "RM 240724-002"
    session.notes = "Sputum encer, kualitas sampel kurang baik."
    session.status = .published
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 0,
                                       confidence: 0.8, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}
```

- [ ] **Step 2: Build dan jalankan seluruh test**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```

Diharapkan: BUILD SUCCEEDED, semua test lulus.

- [ ] **Step 3: Periksa kedua `#Preview`**

Yang dilihat: preview pertama tanpa cap SEMENTARA (3+ butuh 20 lapang, dan ada 20). Preview kedua **dengan** cap SEMENTARA dan keterangan kurang 80 lapang, karena Negatif butuh 100.

- [ ] **Step 4: Commit**

```bash
git add Bacilab/Features/ResultSheet/ResultSheetView.swift Bacilab/Features/Review/ReviewView.swift
git commit -m "feat: add read-only result sheet shared with history"
```

---

## Task 16: Beranda memakai sesi

**Files:**
- Modify: `Bacilab/Features/SampleList/SampleListViewModel.swift`
- Modify: `Bacilab/Features/SampleList/SampleListView.swift`
- Test: `BacilabTests/SessionListViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionStoreProtocol`, `ExamSession`, `SessionDisplayStatus`
- Produces: `@MainActor @Observable final class SampleListViewModel` dengan `init(sessionStore:)`, `sessions`, `isLoading`, `errorMessage`, `searchText`, `statusFilter`, `filteredSessions`, `load() async`, `delete(_:) async`

Beranda sekarang menampilkan sesi, bukan `Sample`. Sesi yang belum terbit muncul sebagai **Berjalan** dan bisa dilanjutkan — chip filter yang dulu bernama "Pending" akhirnya bisa terisi, karena statusnya kini diturunkan dari `ExamSession.status` dan bukan dari ada-tidaknya hasil analisis.

Tombol "Lihat semua" yang aksinya kosong dihapus.

- [ ] **Step 1: Tulis test yang gagal**

Buat `BacilabTests/SessionListViewModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Bacilab

@MainActor
struct SessionListViewModelTests {

    private final class StubStore: SessionStoreProtocol, @unchecked Sendable {
        var sessions: [ExamSession] = []
        var deleted: [UUID] = []
        func allSessions() async throws -> [ExamSession] { sessions }
        func save(_ session: ExamSession) async throws {}
        func delete(_ session: ExamSession) async throws { deleted.append(session.id) }
        func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws {}
        func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
    }

    private func session(name: String, mrn: String, status: SessionStatus,
                         grade: BTAGrade? = nil) -> ExamSession {
        let s = ExamSession()
        s.patient.name = name
        s.patient.medicalRecordNumber = mrn
        s.status = status
        if let grade { s.chooseGrade(grade) }
        return s
    }

    @Test("Sesi dimuat dari penyimpanan")
    func loadsSessions() async {
        let store = StubStore()
        store.sessions = [session(name: "A", mrn: "RM-1", status: .published)]
        let vm = SampleListViewModel(sessionStore: store)

        await vm.load()

        #expect(vm.sessions.count == 1)
        #expect(!vm.isLoading)
    }

    @Test("Sesi belum terbit tampil sebagai Berjalan")
    func unpublishedSessionsShowAsRunning() async {
        let store = StubStore()
        store.sessions = [
            session(name: "A", mrn: "RM-1", status: .scanning),
            session(name: "B", mrn: "RM-2", status: .reviewing)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        #expect(vm.sessions.allSatisfy { $0.displayStatus == .running },
                "Chip Berjalan harus bisa terisi — yang lama tidak pernah bisa")
    }

    @Test("Filter status menyaring daftar")
    func statusFilterWorks() async {
        let store = StubStore()
        store.sessions = [
            session(name: "A", mrn: "RM-1", status: .scanning),
            session(name: "B", mrn: "RM-2", status: .published, grade: .negative),
            session(name: "C", mrn: "RM-3", status: .published, grade: .plus2)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        vm.statusFilter = .running
        #expect(vm.filteredSessions.count == 1)

        vm.statusFilter = .negative
        #expect(vm.filteredSessions.map(\.patient.name) == ["B"])

        vm.statusFilter = .positive
        #expect(vm.filteredSessions.map(\.patient.name) == ["C"])

        vm.statusFilter = nil
        #expect(vm.filteredSessions.count == 3)
    }

    @Test("Pencarian cocok pada nama maupun nomor rekam medis")
    func searchMatchesNameAndMRN() async {
        let store = StubStore()
        store.sessions = [
            session(name: "Ahmad Rizki", mrn: "RM 240724-001", status: .published),
            session(name: "Siti Rahma", mrn: "RM 240724-002", status: .published)
        ]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        vm.searchText = "ahmad"
        #expect(vm.filteredSessions.count == 1)

        vm.searchText = "240724-002"
        #expect(vm.filteredSessions.map(\.patient.name) == ["Siti Rahma"])
    }

    @Test("Menghapus sesi juga menghapusnya dari daftar")
    func deleteRemovesSession() async {
        let store = StubStore()
        let target = session(name: "A", mrn: "RM-1", status: .scanning)
        store.sessions = [target]
        let vm = SampleListViewModel(sessionStore: store)
        await vm.load()

        await vm.delete(target)

        #expect(store.deleted == [target.id])
        #expect(vm.sessions.isEmpty)
    }
}
```

- [ ] **Step 2: Jalankan test, pastikan gagal**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/SessionListViewModelTests 2>&1 | tail -25
```

Diharapkan: GAGAL COMPILE — `SampleListViewModel(sessionStore:)` belum ada.

- [ ] **Step 3: Tulis ulang SampleListViewModel**

Ganti seluruh isi `Bacilab/Features/SampleList/SampleListViewModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SampleListViewModel {
    private let sessionStore: any SessionStoreProtocol

    private(set) var sessions: [ExamSession] = []
    var isLoading = false
    var errorMessage: String?

    var searchText = ""
    var statusFilter: SessionDisplayStatus?

    init(sessionStore: any SessionStoreProtocol) {
        self.sessionStore = sessionStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await sessionStore.allSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ session: ExamSession) async {
        do {
            try await sessionStore.delete(session)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredSessions: [ExamSession] {
        let byStatus = statusFilter.map { filter in
            sessions.filter { $0.displayStatus == filter }
        } ?? sessions

        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return byStatus }

        // Nomor rekam medis ikut dicari: itu yang tertulis di tabung dan di formulir,
        // dan sering satu-satunya yang dipegang petugas saat mencari hasil.
        return byStatus.filter {
            $0.patient.name.localizedCaseInsensitiveContains(query)
                || $0.patient.medicalRecordNumber.localizedCaseInsensitiveContains(query)
        }
    }
}
```

- [ ] **Step 4: Tulis ulang SampleListView**

Ganti seluruh isi `Bacilab/Features/SampleList/SampleListView.swift`:

```swift
import SwiftUI

struct SampleListView: View {
    @State private var viewModel: SampleListViewModel
    @Environment(AppDependencies.self) private var dependencies
    @State private var newSession: ExamSession?

    init(viewModel: SampleListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    banner
                    searchBar
                    sessionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottomTrailing) { fab }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExamSession.self) { session in
                destination(for: session)
            }
            .sheet(item: $newSession, onDismiss: { Task { await viewModel.load() } }) { session in
                NavigationStack {
                    PatientDataView(session: session, dependencies: dependencies)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.load() }
    }

    /// Sesi yang belum terbit dibuka kembali di tempat ia ditinggalkan; yang sudah terbit
    /// membuka lembar hasilnya — layar yang sama dengan ujung alur pemeriksaan.
    @ViewBuilder
    private func destination(for session: ExamSession) -> some View {
        switch session.status {
        case .scanning:
            ScanView(session: session, dependencies: dependencies)
        case .reviewing:
            ReviewView(session: session,
                       queue: dependencies.makeAnalysisQueue(),
                       dependencies: dependencies)
        case .published:
            ResultSheetView(session: session, dependencies: dependencies)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Electra Lab")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("BTA Analyzer")
                .font(.system(size: 32, weight: .black))
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
                                    .locale(Locale(identifier: "id_ID"))))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 64)
    }

    private var banner: some View {
        Button {
            newSession = ExamSession()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analisis Baru")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Mulai pemeriksaan BTA")
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cari nama atau no. rekam medis...",
                      text: Bindable(viewModel).searchText)
                .font(.system(.body, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Riwayat Pemeriksaan")
                .font(.system(.headline, design: .rounded, weight: .bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Semua", nil)
                    chip("Berjalan", .running)
                    chip("Positif", .positive)
                    chip("Negatif", .negative)
                }
            }

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if viewModel.filteredSessions.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Pemeriksaan",
                    systemImage: "testtube.2",
                    description: Text("Ketuk Analisis Baru untuk memulai")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.filteredSessions) { session in
                        NavigationLink(value: session) { row(for: session) }
                            .buttonStyle(.plain)
                            // Sesi yang ditinggalkan harus bisa dibuang: satu sesi 20 lapang
                            // memakan puluhan megabita, dan sesi salah-mulai akan menumpuk.
                            // `.onDelete` butuh `List`; menu tekan-tahan bekerja di sini.
                            .contextMenu {
                                Button("Hapus Pemeriksaan", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.delete(session) }
                                }
                            }
                        if session.id != viewModel.filteredSessions.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func chip(_ label: String, _ status: SessionDisplayStatus?) -> some View {
        let isSelected = viewModel.statusFilter == status
        return Button {
            viewModel.statusFilter = status
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.systemBackground), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(Capsule().stroke(isSelected ? .clear : Color(.systemGray4), lineWidth: 1))
        }
    }

    private func row(for session: ExamSession) -> some View {
        let color: Color = switch session.displayStatus {
        case .running:  .orange
        case .negative: .green
        case .positive: .red
        }

        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "microbe.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.patient.name.isEmpty ? "Tanpa nama" : session.patient.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(session.patient.medicalRecordNumber.isEmpty
                     ? session.createdAt.formatted(date: .abbreviated, time: .shortened)
                     : session.patient.medicalRecordNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.displayStatus.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.12), in: Capsule())
                    .foregroundStyle(color)
                if session.displayStatus == .running {
                    Text("\(session.fields.count) lapang")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var fab: some View {
        Button {
            newSession = ExamSession()
        } label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
        }
        .padding(24)
    }
}

#Preview("Beranda") {
    let deps = AppDependencies()
    return SampleListView(viewModel: SampleListViewModel(sessionStore: deps.sessionStore))
        .environment(deps)
}
```

`ExamSession` harus `Hashable` supaya bisa dipakai sebagai nilai `NavigationLink`. Tambahkan di akhir `ExamSession.swift`:

```swift
extension ExamSession: Hashable {
    static func == (lhs: ExamSession, rhs: ExamSession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
```

- [ ] **Step 5: Perbarui ElectraLabApp**

Di `Bacilab/App/ElectraLabApp.swift`, ganti argumen inisialisasi:

```swift
            SampleListView(
                viewModel: SampleListViewModel(
                    sessionStore: dependencies.sessionStore
                )
            )
```

- [ ] **Step 6: Jalankan test, pastikan lulus**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:BacilabTests/SessionListViewModelTests 2>&1 | tail -25
```

Diharapkan: LULUS, 5 test.

- [ ] **Step 7: Commit**

```bash
git add Bacilab/Features/SampleList/ Bacilab/App/ElectraLabApp.swift \
        Bacilab/Core/Domain/Entities/ExamSession.swift \
        BacilabTests/SessionListViewModelTests.swift
git commit -m "feat: list exam sessions with resumable running state"
```

---

## Task 17: Hapus alur lama

**Files:**
- Delete: `Bacilab/Core/Domain/Entities/SampleDraft.swift`, `Sample.swift`, `CapturedField.swift`
- Delete: `Bacilab/Core/Services/SampleRepository.swift`, `Bacilab/Core/Domain/Protocols/SampleRepositoryProtocol.swift`
- Delete: `Bacilab/Features/DataInput/`, `Bacilab/Features/Capture/`, `Bacilab/Features/Analysis/`, `Bacilab/Features/Result/`
- Delete: `BacilabTests/CaptureFlowTests.swift`, `BacilabTests/OverlayTests.swift`
- Modify: `Bacilab/App/AppDependencies.swift`, `Bacilab/Core/Extensions/PreviewHelpers.swift`
- Modify: `BacilabTests/GradeThresholdTests.swift`, `BacilabTests/DualDetectorTests.swift`

**Interfaces:**
- Consumes: seluruh tipe baru dari Task 1–16
- Produces: pohon sumber tanpa `SampleDraft`, `Sample`, atau layar lama

Dikerjakan terakhir supaya setiap task sebelumnya ter-compile sendiri selama migrasi.

- [ ] **Step 1: Hapus berkas lama**

```bash
git rm -r Bacilab/Features/DataInput Bacilab/Features/Capture \
          Bacilab/Features/Analysis Bacilab/Features/Result
git rm Bacilab/Core/Domain/Entities/SampleDraft.swift \
       Bacilab/Core/Domain/Entities/Sample.swift \
       Bacilab/Core/Domain/Entities/CapturedField.swift \
       Bacilab/Core/Services/SampleRepository.swift \
       Bacilab/Core/Domain/Protocols/SampleRepositoryProtocol.swift \
       BacilabTests/CaptureFlowTests.swift \
       BacilabTests/OverlayTests.swift
```

`CaptureFlowTests` digantikan `ScanViewModelTests`, yang menguji hal sama pada alur baru dan menambah kasus yang dulu tidak ada — lapang kosong tetap terhitung. `OverlayTests` digantikan `DetectorStyleTests`; tiga dari empat testnya (frame beku, kembali ke live) menguji perilaku yang tidak ada lagi, dan yang keempat — id kotak tidak bertabrakan — sudah pindah ke sana.

Di Xcode, hapus referensi merah yang tertinggal dari `project.pbxproj`.

- [ ] **Step 2: Bersihkan AppDependencies**

Hapus dua baris `sampleRepository` dari `Bacilab/App/AppDependencies.swift` sehingga menjadi:

```swift
import Foundation
import Observation

@Observable
final class AppDependencies {
    let cameraService: any CameraServiceProtocol
    let analysisService: any AnalysisServiceProtocol
    let sessionStore: any SessionStoreProtocol

    init() {
        cameraService = CameraService()
        // Semua model membaca setiap lapang. ResNet yang hitungannya dipakai; dua YOLO ikut
        // tersimpan untuk dibandingkan, dan tidak pernah menjadi angka yang dipakai.
        analysisService = MultiDetectorService()
        sessionStore = SessionStore()
    }

    /// Satu antrean per sesi.
    ///
    /// Bukan properti tunggal: antrean bersama akan menempatkan lapang dari dua sesi berbeda
    /// dalam satu urutan, dan membatalkan salah satunya akan membatalkan keduanya.
    @MainActor
    func makeAnalysisQueue() -> FieldAnalysisQueue {
        FieldAnalysisQueue(analysisService: analysisService)
    }
}
```

- [ ] **Step 3: Tulis ulang PreviewHelpers**

Ganti seluruh isi `Bacilab/Core/Extensions/PreviewHelpers.swift`:

```swift
import Foundation

extension ExamSession {

    /// Sesi 20 lapang padat — 3+ dan sudah memenuhi ambangnya.
    static var previewHeavy: ExamSession {
        make(name: "Ahmad Rizki", mrn: "RM 240724-001",
             counts: Array(repeating: 15, count: 20), status: .published)
    }

    /// Sesi 20 lapang bersih — Negatif, tapi masih jauh dari 100 lapang yang disyaratkan.
    static var previewNegative: ExamSession {
        make(name: "Siti Rahma", mrn: "RM 240724-002",
             counts: Array(repeating: 0, count: 20), status: .published)
    }

    /// Sesi yang ditinggal di tengah scan.
    static var previewRunning: ExamSession {
        make(name: "Budi Santoso", mrn: "RM 240724-003",
             counts: [2, 0, 1, 0, 3], status: .scanning)
    }

    private static func make(
        name: String,
        mrn: String,
        counts: [Int],
        status: SessionStatus
    ) -> ExamSession {
        let session = ExamSession()
        session.patient.name = name
        session.patient.medicalRecordNumber = mrn
        session.status = status
        for count in counts {
            let field = session.appendField(imageFileName: "field.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .resnet, btaCount: count,
                                               confidence: 0.86, elapsed: 0.6)],
                    primary: .resnet
                ),
                for: field.id
            )
        }
        return session
    }
}
```

- [ ] **Step 4: Tulis ulang GradeThresholdTests**

Ganti seluruh isi `BacilabTests/GradeThresholdTests.swift`:

```swift
import Testing
@testable import Bacilab

/// WHO/IUATLD menskalakan beban baca pada kepadatan: smear berat mengumumkan dirinya dalam
/// ~20 lapang, sedangkan Negatif dan Scanty baru boleh dilaporkan setelah 100 lapang penuh.
/// Asimetrinya disengaja — membaca terlalu sedikit pada slide yang jarang adalah yang
/// memulangkan pasien menular tanpa pengobatan.
struct GradeThresholdTests {

    private func session(fieldCount: Int, btaPerField: Int) -> ExamSession {
        let session = ExamSession()
        for _ in 0..<fieldCount {
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .resnet, btaCount: btaPerField,
                                               confidence: 0.8, elapsed: 0.4)],
                    primary: .resnet),
                for: field.id)
        }
        return session
    }

    @Test("Ambang lapang pandang sesuai WHO/IUATLD")
    func minimumFieldsPerGrade() {
        #expect(BTAGrade.plus3.minimumFields == 20)
        #expect(BTAGrade.plus2.minimumFields == 50)
        #expect(BTAGrade.plus1.minimumFields == 100)
        #expect(BTAGrade.scanty.minimumFields == 100)
        #expect(BTAGrade.negative.minimumFields == 100)
    }

    @Test("Negatif tidak boleh final sebelum 100 lapang pandang")
    func negativeNeedsFullReading() {
        let twenty = session(fieldCount: 20, btaPerField: 0)
        #expect(twenty.reportedGrade == .negative)
        #expect(!twenty.isGradeConfirmed, "Negatif setelah 20 lapang tidak boleh final")
        #expect(twenty.fieldsRemainingForGrade == 80)

        let ninetyNine = session(fieldCount: 99, btaPerField: 0)
        #expect(!ninetyNine.isGradeConfirmed)

        let hundred = session(fieldCount: 100, btaPerField: 0)
        #expect(hundred.isGradeConfirmed)
        #expect(hundred.fieldsRemainingForGrade == 0)
    }

    @Test("3+ sudah bisa final setelah 20 lapang pandang")
    func heavySmearConfirmsEarly() {
        #expect(!session(fieldCount: 19, btaPerField: 15).isGradeConfirmed)
        #expect(session(fieldCount: 20, btaPerField: 15).isGradeConfirmed)
    }

    @Test("Satu lapang pandang tidak pernah menghasilkan grade final")
    func singleFieldIsNeverFinal() {
        for grade in BTAGrade.allCases {
            let s = session(fieldCount: 1, btaPerField: 5)
            s.chooseGrade(grade)
            #expect(!s.isGradeConfirmed,
                    "\(grade.rawValue) dianggap final hanya dari 1 lapang pandang")
        }
    }

    @Test("Ambang mengikuti grade yang sedang berlaku")
    func thresholdFollowsCurrentGrade() {
        let s = session(fieldCount: 30, btaPerField: 15)

        s.chooseGrade(.plus3)
        #expect(s.isGradeConfirmed)

        s.chooseGrade(.negative)
        #expect(!s.isGradeConfirmed)
        #expect(s.fieldsRemainingForGrade == 70)
    }
}
```

- [ ] **Step 5: Rapikan DualDetectorTests**

Hapus tiga test yang mengemudikan alur lama, beserta seluruh badan fungsinya:

- `comparisonAccumulatesWithoutTouchingGrade`
- `switchingDetectorDoesNotCarryCountsOver`
- `failedReadingIsNotCountedAsZero`

Dua yang pertama menguji `SampleDraft.adoptCount` / `reconcileCountSource`, yang tidak ada lagi — hitungan sekarang diturunkan dari daftar lapang, jadi menyimpang antar-model bukan lagi sesuatu yang bisa terjadi dan tidak ada yang perlu dijaga. Yang ketiga sudah digantikan `FieldRecordTests.failedAnalysisHasNoCount` dan `ExamSessionTests.failedFieldContributesToNeither`.

Tujuh test sisanya menguji `MultiDetectorService` langsung dan tidak disentuh.

- [ ] **Step 6: Perbarui UI test**

Ganti seluruh isi `BacilabUITests/BacilabUITests.swift`:

```swift
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

        app.buttons["Analisis Baru"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Data Pasien"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testKameraTerkunciSampaiDataWajibTerisi() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Analisis Baru"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Data Pasien"].waitForExistence(timeout: 5))

        let openCamera = app.buttons["Buka Kamera"]
        XCTAssertTrue(openCamera.exists)
        XCTAssertFalse(openCamera.isEnabled,
                       "Sesi tidak boleh dimulai tanpa nama dan nomor rekam medis")

        app.textFields["Masukkan nama lengkap"].tap()
        app.typeText("Ahmad Rizki")
        app.textFields["Contoh: RM 240724-001"].tap()
        app.typeText("RM 240724-001")

        XCTAssertTrue(openCamera.isEnabled)
    }
}
```

- [ ] **Step 7: Jalankan seluruh suite**

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -40
```

Diharapkan: BUILD SUCCEEDED dan seluruh test lulus. Kalau ada referensi ke tipe yang dihapus, kompilernya akan menyebutkan berkasnya — perbaiki lalu jalankan lagi.

- [ ] **Step 8: Pastikan tidak ada sisa referensi**

```bash
grep -rn "SampleDraft\|SampleRepository\|CaptureViewModel\|AnalysisViewModel\|ResultViewModel\|Klinik Bunda" \
     Bacilab BacilabTests BacilabUITests --include="*.swift"
```

Diharapkan: tidak ada keluaran.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: remove the old draft-based capture flow"
```

---

## Task 18: Perbarui CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: keadaan akhir setelah Task 17
- Produces: dokumen yang cocok dengan kode

CLAUDE.md sekarang menjelaskan alur yang tidak ada lagi. Bagian yang harus berubah:

- [ ] **Step 1: Ganti nama fasilitas**

Seluruh "Klinik Bunda" menjadi "Electra Lab", termasuk di kalimat pembuka Project Overview.

- [ ] **Step 2: Ganti deskripsi alur**

"guides a lab technician through a 4-screen flow: patient data entry → camera capture → manual BTA review → result/interpretation" menjadi:

> guides a lab technician through: patient data → scan session (20 fields per batch) → per-field review → published result sheet. Every clinical decision — per-field count, grade, notes, publish — belongs to the review screen alone.

- [ ] **Step 3: Ganti bagian "SampleDraft — shared mutable state"**

Ganti seluruh bagian itu dengan:

> ### ExamSession — one source of truth, no stored counts
> `ExamSession` is `@Observable`, created once per examination and passed by reference. **No count
> is stored.** `totalBTA` and `examinedFieldCount` are recomputed from `fields` on every read, so
> the count that drives the grade cannot drift from the fields it came from. The old model kept
> `manualBTACount` beside the field list; the two could disagree, and the stored one is what
> reached the patient's report.
>
> `chosenGrade` is optional: `nil` means nobody has decided yet, so `reportedGrade` falls back to
> `suggestedGrade`. That optional replaces the old `hasManualGrade` flag.

- [ ] **Step 4: Ganti bagian "A capture that fails must not count as a field"**

Ganti dengan:

> ### Every scanned field counts — including empty ones
> `ScanViewModel.captureField` appends a field whenever the image is written to disk, whether or
> not any bacilli are found. Auto-scan used to increment only when `btaCount > 0`, so empty fields
> never entered the denominator and **grade Negatif was structurally unreachable**.
>
> A capture that fails still appends nothing: the field is recorded only after its image is safely
> on disk, so a full disk cannot leave a field whose picture does not exist.
>
> Because every frame counts, a stationary slide is counted repeatedly. The per-100 ratio survives
> that (BTA and fields rise together), but `examinedFieldCount` can reach a threshold without that
> many distinct fields being seen. Review's **delete-field** is what corrects it.

- [ ] **Step 5: Ganti bagian struktur file**

Perbarui pohon direktori agar cocok dengan hasil Task 17: `Features/PatientData`, `Features/Scan`, `Features/Review`, `Features/ResultSheet`, `Features/SampleList`; `Core/Services/SessionStore.swift`, `FieldAnalysisQueue.swift`, `FocusMetric.swift`; `Core/Domain/Entities/ExamSession.swift`, `FieldRecord.swift`, `PatientInfo.swift`.

- [ ] **Step 6: Perbarui catatan confidence**

Tambahkan ke bagian "Never fabricate clinical figures":

> Review menampilkannya sebagai "Model yakin N% atas basil yang ia tandai", bukan sebagai angka
> keyakinan hasil. Grafik ONNX membuang deteksi di bawah 0,70, jadi angka itu tidak pernah bisa
> terbaca di bawah 70%.

- [ ] **Step 7: Tambahkan catatan penyimpanan**

Tambahkan bagian baru setelah Simulator safety:

> ### Sessions live on disk
> `SessionStore` writes one directory per session under Application Support: `manifest.json` plus
> `field-NNN.jpg` at analysis resolution (max side 1600 — the model's own `max_size`). The manifest
> is rewritten after every recorded or analysed field, so a session survives the app being killed.
> `FieldRecord.imageFileName` is relative, never an absolute URL: iOS container paths change
> between installs.

- [ ] **Step 8: Verifikasi**

```bash
grep -n "Klinik Bunda\|SampleDraft\|4-screen" CLAUDE.md
```

Diharapkan: tidak ada keluaran.

- [ ] **Step 9: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for the session-based flow"
```
