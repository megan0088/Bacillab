import Testing
import Foundation
import CoreML
import UIKit
@testable import Bacilab

/// Guards the third detector: YOLO11, exported end-to-end, decoded by hand.
///
/// Its contract differs from the OBB model in every way that matters — 640 input instead of
/// 1024, `(1, 300, 6)` corners instead of `(1, 6, 21504)` centres, and an NMS-free head — so
/// nothing about the other CoreML path implies this one works.
struct YOLO11DetectorTests {

    private func probeImageData() throws -> Data {
        let url = try #require(
            Bundle(for: V11BundleMarker.self).url(forResource: "bta-probe", withExtension: "png"),
            "bta-probe.png tidak ada di test bundle"
        )
        return try Data(contentsOf: url)
    }

    @Test("Model YOLO11 ter-bundle dan kontrak I/O-nya sesuai yang di-decode")
    func modelIsBundledWithExpectedShape() throws {
        #expect(YOLO11AnalysisService.isDetectorLoaded, "BTADetectorV11.mlmodelc tidak termuat")

        let url = try #require(
            Bundle.main.url(forResource: "BTADetectorV11", withExtension: "mlmodelc"),
            "BTADetectorV11.mlmodelc tidak ada di app bundle"
        )
        let model = try MLModel(contentsOf: url)

        // The decoder reads rows of 6 and stops at 300; if a re-export changes either, the
        // counts would drift silently rather than fail.
        let output = try #require(model.modelDescription.outputDescriptionsByName.values.first)
        let shape = try #require(output.multiArrayConstraint?.shape).map(\.intValue)
        #expect(shape == [1, 300, 6], "Bentuk output \(shape) — decoder perlu disesuaikan")

        // Input is 640, not the 1024 of the OBB model.
        let input = try #require(model.modelDescription.inputDescriptionsByName["image"])
        let image = try #require(input.imageConstraint)
        #expect(image.pixelsWide == 640 && image.pixelsHigh == 640,
                "Input \(image.pixelsWide)x\(image.pixelsHigh), bukan 640 — normalisasi kotak akan meleset")
    }

    /// Note what this test does **not** claim: that YOLO11 detects anything here.
    ///
    /// It scores every candidate on `bta-probe.png` below 0.25 and returns 0. That is the
    /// model's honest verdict, not a fault — `YOLO11RawTensorTests` confirms the decoder
    /// agrees with the raw tensor row for row. The probe is synthetic magenta dashes, and
    /// unlike the OBB model this one does not generalise to them.
    ///
    /// The consequence is worth stating plainly: **the simulator cannot exercise YOLO11.**
    /// Only real slides can tell whether it works, so nothing here should be read as evidence
    /// that it does.
    @Test("Kotak YOLO11 valid bila ada, dan hitungannya konsisten")
    func boxesAreValidWhenPresent() async throws {
        let result = try await YOLO11AnalysisService().analyze(imageData: probeImageData())

        #expect(result.detectedBoxes.count == result.btaCount)
        if result.btaCount > 0 {
            #expect(result.confidence >= 0.25, "Confidence di bawah ambangnya sendiri")
        }

        for box in result.detectedBoxes {
            #expect((0...1).contains(box.cx) && (0...1).contains(box.cy),
                    "Kotak di luar frame — koordinat mungkin bukan piksel 640")
            // A box normalised by the wrong constant collapses to near-zero rather than
            // failing outright, which would draw invisible rectangles instead of erroring.
            #expect(box.w > 0.002 && box.h > 0.002,
                    "Kotak \(box.w)x\(box.h) terlalu kecil — kemungkinan koordinat sudah ternormalisasi")
            #expect(box.w <= 1 && box.h <= 1)
            // The Detect head is axis-aligned.
            #expect(box.angle == 0)
        }
    }

    @Test("Ketiga model membaca lapang yang sama dan semuanya terlaporkan",
          .disabled("YOLOv8 dimatikan di MultiDetectorService — hidupkan keduanya bersamaan"))
    func allThreeReport() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData(), using: .all)

        #expect(result.readings.count == 3, "Hanya \(result.readings.count) model yang melapor")
        for kind in DetectorKind.allCases {
            let reading = try #require(result.reading(kind), "\(kind.rawValue) tidak melapor")
            #expect(reading.failure == nil, "\(kind.rawValue) gagal: \(reading.failure ?? "")")
            #expect(reading.boxes.count == reading.btaCount,
                    "\(kind.rawValue): \(reading.btaCount) hitungan tapi \(reading.boxes.count) kotak")
        }

        // The grade stays ResNet's no matter how many models joined in.
        let resnet = try #require(result.reading(.resnet))
        #expect(result.btaCount == resnet.btaCount)
        #expect(result.grade == BTAGrade.grade(for: resnet.btaCount, across: 1))
    }

    @Test("Memilih YOLO11 saja hanya menjalankan YOLO11")
    func selectingYolo11RunsOnlyIt() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData(), using: .yolo11)

        #expect(result.readings.count == 1)
        #expect(result.reading(.yolo11) != nil)
        #expect(result.reading(.resnet) == nil && result.reading(.yolo) == nil,
                "Model lain ikut jalan padahal tidak dipilih")

        let yolo11 = try #require(result.reading(.yolo11))
        #expect(result.btaCount == yolo11.btaCount, "Grade tidak mengikuti model yang dipilih")
    }

    @Test("Setiap model punya warna dan pola garis yang berbeda")
    func everyModelIsVisuallyDistinct() {
        let dashes = DetectorKind.allCases.map { DetectorStyle.dash(for: $0) }
        // Colour alone cannot carry three categories for a colour-blind reader, so the dash
        // patterns have to differ too.
        #expect(Set(dashes.map(\.description)).count == DetectorKind.allCases.count,
                "Ada model dengan pola garis yang sama")
    }
}

private final class V11BundleMarker {}
