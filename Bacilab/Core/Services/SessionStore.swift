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
