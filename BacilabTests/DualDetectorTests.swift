import Testing
import Foundation
import UIKit
@testable import Bacilab

/// Covers the rule the comparison exists to protect: two numbers may be shown, but only one
/// of them is allowed to become the patient's count.
struct DualDetectorTests {

    private func probeImageData() throws -> Data {
        let url = try #require(
            Bundle(for: DualBundleMarker.self).url(forResource: "bta-probe", withExtension: "png"),
            "bta-probe.png tidak ada di test bundle"
        )
        return try Data(contentsOf: url)
    }

    @Test("Kedua model membaca lapang yang sama dan keduanya terlaporkan")
    func bothDetectorsReport() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData())

        let resnet = try #require(result.reading(.resnet), "ResNet tidak melaporkan apa pun")
        let yolo = try #require(result.reading(.yolo), "YOLO tidak melaporkan apa pun")

        #expect(resnet.failure == nil, "ResNet gagal: \(resnet.failure ?? "")")
        #expect(yolo.failure == nil, "YOLO gagal: \(yolo.failure ?? "")")
        #expect(resnet.btaCount > 0 && yolo.btaCount > 0,
                "Salah satu model tidak mendeteksi apa pun; perbandingan jadi hampa")
    }

    @Test("Hitungan yang dilaporkan milik ResNet, bukan campuran keduanya")
    func primaryCountIsResNetAlone() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData())

        let resnet = try #require(result.reading(.resnet))
        let yolo = try #require(result.reading(.yolo))

        #expect(result.btaCount == resnet.btaCount,
                "btaCount = \(result.btaCount), padahal ResNet menghitung \(resnet.btaCount)")
        #expect(result.confidence == resnet.confidence)

        // The guard only means something if the two actually disagree on this probe.
        // If they ever converge, this test stops proving anything and should be revisited.
        #expect(resnet.btaCount != yolo.btaCount,
                "Kedua model kebetulan sama (\(resnet.btaCount)); test ini tidak lagi membuktikan apa-apa")

        // An average of the two would sit strictly between them — the count must not.
        let mean = (resnet.btaCount + yolo.btaCount) / 2
        #expect(result.btaCount != mean || resnet.btaCount == mean,
                "Hitungan terlihat seperti rata-rata kedua model")
    }

    @Test("Grade berasal dari hitungan ResNet saja")
    func gradeFollowsResNetOnly() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData())
        let resnet = try #require(result.reading(.resnet))

        #expect(result.grade == BTAGrade.grade(for: resnet.btaCount, across: 1),
                "Grade tidak konsisten dengan hitungan ResNet")
    }

    @Test("Hitungan pembanding menumpuk terpisah dan tidak menyentuh grade")
    func comparisonAccumulatesWithoutTouchingGrade() async throws {
        let deps = AppDependencies()
        let viewModel = CaptureViewModel(
            cameraService: deps.cameraService,
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )
        let draft = SampleDraft()

        await viewModel.capture(into: draft)
        await viewModel.capture(into: draft)

        #expect(draft.capturedFieldCount == 2)
        #expect(draft.fields(for: .yolo) == 2,
                "Pembanding tercatat \(draft.fields(for: .yolo)) lapang, seharusnya 2")
        #expect(draft.count(for: .yolo) > 0, "Pembanding tidak menumpuk sama sekali")

        // The grade must be derivable from the primary total alone; if the comparison had
        // leaked into it this equality would break.
        #expect(draft.grade == BTAGrade.grade(for: draft.manualBTACount,
                                              across: draft.capturedFieldCount))
    }

    @Test("Memilih satu model hanya menjalankan model itu")
    func singleSelectionRunsOnlyThatModel() async throws {
        let data = try probeImageData()
        let service = MultiDetectorService()

        let resnetOnly = try await service.analyze(imageData: data, using: .resnet)
        #expect(resnetOnly.readings.count == 1)
        #expect(resnetOnly.reading(.resnet) != nil)
        #expect(resnetOnly.reading(.yolo) == nil, "YOLO ikut jalan padahal tidak dipilih")

        let yoloOnly = try await service.analyze(imageData: data, using: .yolo)
        #expect(yoloOnly.readings.count == 1)
        #expect(yoloOnly.reading(.yolo) != nil)
        #expect(yoloOnly.reading(.resnet) == nil, "ResNet ikut jalan padahal tidak dipilih")
    }

    @Test("Memilih YOLO membuat grade mengikuti YOLO, bukan ResNet")
    func yoloSelectionGradesFromYolo() async throws {
        let data = try probeImageData()
        let service = MultiDetectorService()

        let yoloOnly = try await service.analyze(imageData: data, using: .yolo)
        let yolo = try #require(yoloOnly.reading(.yolo))

        #expect(yoloOnly.btaCount == yolo.btaCount)
        #expect(yoloOnly.grade == BTAGrade.grade(for: yolo.btaCount, across: 1))

        // And it must genuinely differ from what ResNet would have reported, otherwise the
        // selection is not actually changing which model answers.
        let resnetOnly = try await service.analyze(imageData: data, using: .resnet)
        #expect(yoloOnly.btaCount != resnetOnly.btaCount,
                "Pilihan model tidak mengubah hitungan — kemungkinan selection diabaikan")
    }

    @Test("Setiap model membawa kotaknya sendiri untuk digambar")
    func eachReadingCarriesItsOwnBoxes() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData(), using: .all)

        let resnet = try #require(result.reading(.resnet))
        let yolo = try #require(result.reading(.yolo))

        #expect(resnet.boxes.count == resnet.btaCount,
                "Kotak ResNet (\(resnet.boxes.count)) tidak sebanyak hitungannya (\(resnet.btaCount))")
        #expect(yolo.boxes.count == yolo.btaCount,
                "Kotak YOLO (\(yolo.boxes.count)) tidak sebanyak hitungannya (\(yolo.btaCount))")

        // The overlay draws both sets at once; identical arrays would mean one model's boxes
        // were copied over the other's and the comparison would look like perfect agreement.
        #expect(resnet.boxes != yolo.boxes, "Kedua model memberi kotak yang identik")
    }

    @Test("Satu model saja berarti tidak ada kolom pembanding")
    func singleSelectionHasNoComparison() async throws {
        let result = try await MultiDetectorService().analyze(imageData: probeImageData(), using: .resnet)

        #expect(DetectorSelection.resnet.comparisonDetectors.isEmpty)
        #expect(result.comparisonReadings(for: .resnet).isEmpty,
                "Model tunggal tidak boleh dihitung sebagai pembandingnya sendiri")
    }

    @Test("Berpindah model tidak membawa hitungan model sebelumnya")
    func switchingDetectorDoesNotCarryCountsOver() async throws {
        let deps = AppDependencies()
        let viewModel = CaptureViewModel(
            cameraService: deps.cameraService,
            analysisService: deps.analysisService,
            sampleRepository: deps.sampleRepository
        )
        let draft = SampleDraft()

        // One field read by both models. They disagree on this field, which is what makes a
        // carry-over visible at all — with equal counts the bug would hide.
        viewModel.detectorSelection = .all
        await viewModel.capture(into: draft)

        let resnetAfterBoth = draft.count(for: .resnet)
        let yoloAfterBoth = draft.count(for: .yolo)
        #expect(resnetAfterBoth > 0 && yoloAfterBoth > 0)
        #expect(resnetAfterBoth != yoloAfterBoth,
                "Prasyarat: kedua model harus berbeda agar bawaan angka bisa terdeteksi")

        // Switch to YOLO alone and read a second field.
        viewModel.detectorSelection = .yolo
        await viewModel.capture(into: draft)

        // YOLO's total must be its own two readings and nothing else. If ResNet's fields were
        // relabelled as YOLO's when the selection changed, this is where it shows.
        #expect(draft.count(for: .yolo) == yoloAfterBoth * 2,
                "Total YOLO \(draft.count(for: .yolo)), seharusnya \(yoloAfterBoth * 2) — angka ResNet ikut terbawa")
        #expect(draft.count(for: .resnet) == resnetAfterBoth,
                "Total ResNet berubah padahal ResNet tidak ikut membaca lapang kedua")

        // And the count of record must be YOLO's own total, not a mixture of the two.
        #expect(draft.manualBTACount == draft.count(for: .yolo),
                "Hitungan yang dipakai grade = \(draft.manualBTACount), bukan total YOLO \(draft.count(for: .yolo))")
    }

    @Test("Bacaan yang gagal tidak masuk sebagai nol")
    func failedReadingIsNotCountedAsZero() {
        let draft = SampleDraft()

        draft.record([DetectorReading(
            detector: .yolo, btaCount: 0, confidence: 0, elapsed: 0.1,
            failure: "model tidak dapat dimuat"
        )])

        #expect(draft.fields(for: .yolo) == 0,
                "Lapang yang gagal dibaca ikut terhitung, sehingga rata-ratanya turun palsu")
        #expect(draft.count(for: .yolo) == 0)
    }
}

private final class DualBundleMarker {}
