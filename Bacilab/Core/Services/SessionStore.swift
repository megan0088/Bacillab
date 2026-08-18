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

    /// The on-disk shape is `SessionSnapshot` (declared beside `ExamSession`): a `Sendable` value
    /// the caller freezes on its own actor, so this store never reads a live session's `fields`
    /// off the main actor while the scan loop or the analysis queue is appending to it.
    private func session(from snapshot: SessionSnapshot) -> ExamSession {
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

    private func directory(forID id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func directory(for session: ExamSession) -> URL {
        directory(forID: session.id)
    }

    func fieldImageURL(fileName: String, for session: ExamSession) -> URL {
        directory(for: session).appendingPathComponent(fileName)
    }

    // MARK: - SessionStoreProtocol

    func save(_ snapshot: SessionSnapshot) async throws {
        let dir = directory(forID: snapshot.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        // Tulis atomik: app yang mati di tengah penulisan tidak boleh meninggalkan manifest
        // separuh jadi, karena itu akan menghapus seluruh sesi saat dibaca kembali.
        try data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
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
                  let snapshot = try? decoder.decode(SessionSnapshot.self, from: data)
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
