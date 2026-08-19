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

    /// The analysis queue for a session — the same instance every time it is asked for.
    ///
    /// One queue per session, but **not** a fresh one per call. `ScanView` and `HomeView`'s
    /// review destination both ask for a queue, and a navigation destination is rebuilt on every
    /// push, so minting one per call meant leaving Review and returning started a second worker
    /// over the same session: two ONNX runs in parallel where the design is deliberately serial,
    /// for twice the memory and exactly the thermal load the serial worker exists to avoid.
    ///
    /// One entry deep, because only one examination is ever open at a time. Opening a different
    /// session replaces it and lets the previous queue go, so this cannot grow.
    @MainActor
    func queue(for session: ExamSession) -> FieldAnalysisQueue {
        if let current = currentQueue, current.sessionID == session.id {
            return current.queue
        }
        let queue = FieldAnalysisQueue(analysisService: analysisService, store: sessionStore)
        currentQueue = (session.id, queue)
        return queue
    }

    @MainActor private var currentQueue: (sessionID: UUID, queue: FieldAnalysisQueue)?
}
