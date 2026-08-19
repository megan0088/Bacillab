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
            readings: [DetectorReading(detector: .yolo, btaCount: count,
                                       confidence: 0.8, elapsed: 0.5)],
            primary: .yolo
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

        try await store.save(session.snapshot())
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

        try await store.save(session.snapshot())
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

        try await store.save(session.snapshot())
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
        try await store.save(session.snapshot())
        session.notes = "diperbarui"
        try await store.save(session.snapshot())

        let loaded = try await store.allSessions()
        #expect(loaded.count == 1)
        #expect(loaded[0].notes == "diperbarui")
    }

    @Test("Gambar lapang tersimpan dan bisa dibaca lewat URL-nya")
    func fieldImageIsWrittenAndReadable() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ExamSession()
        try await store.save(session.snapshot())
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
        try await store.save(session.snapshot())
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
        try await store.save(older.snapshot())
        try await store.save(newer.snapshot())

        let loaded = try await store.allSessions()
        #expect(loaded.first?.id == newer.id)
    }

    @Test("Manifest rusak dilewati, bukan menjatuhkan seluruh daftar")
    func corruptManifestIsSkipped() async throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let good = ExamSession()
        try await store.save(good.snapshot())

        let brokenDir = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
        try Data("bukan json".utf8)
            .write(to: brokenDir.appendingPathComponent("manifest.json"))

        let loaded = try await store.allSessions()
        #expect(loaded.count == 1, "Satu sesi rusak tidak boleh menyembunyikan sesi lain")
        #expect(loaded[0].id == good.id)
    }
}
