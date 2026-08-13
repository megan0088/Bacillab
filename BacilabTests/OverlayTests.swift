import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Covers the overlay's contract: the boxes must exist, and they must be drawn on the frame
/// they were measured against.
struct OverlayTests {

    private func makeViewModel(_ deps: AppDependencies) -> CaptureViewModel {
        CaptureViewModel(
            cameraService: deps.cameraService,
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )
    }

    @Test("Setiap bacaan sampai ke overlay lengkap dengan kotaknya")
    func readingsReachOverlayWithBoxes() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        await viewModel.capture(into: draft)

        // Every bundled model, not a hard-coded two — adding a fourth should not need this
        // assertion rewritten, only the model registered.
        #expect(viewModel.latestReadings.count == DetectorKind.allCases.count,
                "Overlay menerima \(viewModel.latestReadings.count) bacaan dari \(DetectorKind.allCases.count) model")
        for reading in viewModel.latestReadings {
            // A count with an empty box array is the failure that looks identical on screen
            // to the drawing being broken; this separates them.
            #expect(reading.boxes.count == reading.btaCount,
                    "\(reading.detector.rawValue): \(reading.btaCount) hitungan tapi \(reading.boxes.count) kotak")
        }

        // Only the grading model is required to fire on the synthetic field. YOLO11 scores
        // everything on it below its cutoff — see `YOLO11DetectorTests` — so demanding a
        // detection from every model would fail on a model that is behaving correctly.
        let grading = try #require(viewModel.latestReadings.first { $0.detector == .resnet })
        #expect(grading.btaCount > 0, "Model penilai tidak mendeteksi apa pun")
    }

    @Test("Frame yang dianalisis dibekukan agar kotak menempel di piksel yang benar")
    func analyzedFrameIsFrozen() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        #expect(viewModel.analyzedImage == nil, "Belum ada capture, seharusnya masih live")

        await viewModel.capture(into: draft)

        let frozen = try #require(viewModel.analyzedImage,
                                  "Frame tidak dibekukan; kotak akan tergambar di atas preview yang sudah bergerak")
        // Box coordinates are normalised against the centred square, so the frozen frame has
        // to be that square — a 4:3 frame here would put every box in the wrong place.
        #expect(frozen.size.width == frozen.size.height,
                "Frame beku \(frozen.size) bukan persegi; koordinat kotak tidak akan cocok")
    }

    @Test("Kembali ke live membersihkan frame beku dan kotaknya")
    func resumingLiveClearsEverything() async throws {
        let deps = AppDependencies()
        let viewModel = makeViewModel(deps)
        let draft = SampleDraft()

        await viewModel.capture(into: draft)
        #expect(viewModel.analyzedImage != nil)
        #expect(!viewModel.latestReadings.isEmpty)

        viewModel.resumeLivePreview()

        // Stale boxes over a live feed point at bacilli that are no longer there.
        #expect(viewModel.analyzedImage == nil)
        #expect(viewModel.latestReadings.isEmpty)
        #expect(viewModel.latestDetections.isEmpty)
    }

    @Test("Kotak kedua model punya identitas yang tidak bertabrakan")
    func markerIdentitiesAreUniqueAcrossModels() async throws {
        let result = try await MultiDetectorService().analyze(
            imageData: try Data(contentsOf: #require(
                Bundle(for: OverlayBundleMarker.self).url(forResource: "bta-probe", withExtension: "png")
            )),
            using: .all
        )

        // Mirrors how the view builds its flat marker list. Both models number their boxes
        // from 0, so without the detector in the id the two sets collide and SwiftUI drops
        // one model's boxes entirely.
        let ids = result.readings.flatMap { reading in
            reading.boxes.enumerated().map { "\(reading.detector.rawValue)-\($0.offset)" }
        }

        #expect(ids.count == Set(ids).count,
                "Ada id kotak yang bertabrakan — kotak satu model akan menimpa model lain")
        #expect(ids.count == result.readings.reduce(0) { $0 + $1.boxes.count })
    }
}

private final class OverlayBundleMarker {}
