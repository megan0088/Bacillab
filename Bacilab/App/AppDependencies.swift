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
        FieldAnalysisQueue(analysisService: analysisService, store: sessionStore)
    }
}
