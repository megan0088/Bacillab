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
