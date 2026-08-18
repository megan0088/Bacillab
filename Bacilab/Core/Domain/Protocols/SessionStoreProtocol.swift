import Foundation

protocol SessionStoreProtocol: AnyObject {
    func allSessions() async throws -> [ExamSession]
    func save(_ snapshot: SessionSnapshot) async throws
    func delete(_ session: ExamSession) async throws

    /// Menulis berkas gambar satu lapang ke direktori sesi.
    func writeFieldImage(_ data: Data, fileName: String, for session: ExamSession) throws

    /// Lokasi berkas gambar satu lapang. Dibentuk dari direktori sesi + nama berkas relatif,
    /// bukan dari URL absolut yang tersimpan — path kontainer app berubah antar-instalasi.
    func fieldImageURL(fileName: String, for session: ExamSession) -> URL
}
