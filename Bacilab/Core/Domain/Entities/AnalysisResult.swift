import Foundation

// Normalized bounding box for one detected bacterium.
// Coordinates are in [0, 1] relative to the model's 1024×1024 input square.
struct DetectedBox: Hashable, Sendable, Codable {
    let cx: Float      // center x, normalized
    let cy: Float      // center y, normalized
    let w: Float       // width, normalized
    let h: Float       // height, normalized
    let angle: Float   // rotation in radians
}

/// Which model produced a reading. Both are bundled so the two can be compared on the
/// same field; see `DualDetectorService`.
enum DetectorKind: String, Hashable, Sendable, CaseIterable, Codable {
    /// Faster R-CNN ResNet50-FPN, ONNX Runtime. Drives the clinical count.
    case resnet = "ResNet"
    /// YOLOv8s-OBB, CoreML. Comparison only — never feeds the grade.
    case yolo = "YOLOv8"
    /// YOLO11 end-to-end, CoreML. Comparison only — never feeds the grade.
    case yolo11 = "YOLO11"
}

/// Which model(s) read a field, chosen by the analyst before capturing or importing.
enum DetectorSelection: String, Hashable, Sendable, CaseIterable, Identifiable {
    case resnet
    case yolo
    case yolo11
    case all

    var id: String { rawValue }

    /// Label for the picker.
    var title: String {
        switch self {
        case .resnet: return DetectorKind.resnet.rawValue
        case .yolo:   return DetectorKind.yolo.rawValue
        case .yolo11: return DetectorKind.yolo11.rawValue
        case .all:    return "Semua"
        }
    }

    /// The model whose count becomes the BTA count and the grade.
    ///
    /// With `.all` this is deliberately ResNet and not some blend of three: averaging models
    /// yields a number none of them produced. Picking a single model on purpose does hand the
    /// grade to it — that is what choosing it means — and the UI has to say which.
    var gradingDetector: DetectorKind {
        switch self {
        case .resnet, .all: return .resnet
        case .yolo:         return .yolo
        case .yolo11:       return .yolo11
        }
    }

    /// Whether this selection asks a given model to run at all.
    func includes(_ detector: DetectorKind) -> Bool {
        self == .all || gradingDetector == detector
    }

    /// Models shown beside the grade but never becoming it.
    ///
    /// Empty for a single-model selection: with one model there is nothing to compare
    /// against, and listing its own count again as "the comparison" would manufacture an
    /// agreement that was never tested.
    var comparisonDetectors: [DetectorKind] {
        guard self == .all else { return [] }
        return DetectorKind.allCases.filter { $0 != gradingDetector }
    }
}

/// One detector's reading of one field.
///
/// Kept separate from `AnalysisResult` because a reading is just a number and how long it
/// took; only the primary detector's reading carries a grade and boxes into the flow.
struct DetectorReading: Hashable, Sendable, Codable {
    let detector: DetectorKind
    let btaCount: Int
    let confidence: Double
    let elapsed: TimeInterval

    /// This detector's own boxes, so both models' marks can be drawn over the same field.
    /// Seeing *where* they disagree says far more than seeing that two totals differ.
    let boxes: [DetectedBox]

    /// Set when this detector failed on a field the other one read. Comparing against a
    /// silent zero would make a broken model look like a model that saw nothing.
    let failure: String?

    init(
        detector: DetectorKind,
        btaCount: Int,
        confidence: Double,
        elapsed: TimeInterval,
        boxes: [DetectedBox] = [],
        failure: String? = nil
    ) {
        self.detector = detector
        self.btaCount = btaCount
        self.confidence = confidence
        self.elapsed = elapsed
        self.boxes = boxes
        self.failure = failure
    }
}

struct AnalysisResult: Hashable, Sendable {
    let btaCount: Int
    let confidence: Double
    let grade: BTAGrade
    let analyzedAt: Date
    let detectedBoxes: [DetectedBox]

    /// Every detector that read this field, primary first. Empty when only one model ran.
    ///
    /// `btaCount` above always stays the *primary* detector's figure — the comparison must
    /// never quietly change the number the patient is graded on.
    let readings: [DetectorReading]

    init(
        btaCount: Int,
        confidence: Double,
        grade: BTAGrade,
        analyzedAt: Date,
        detectedBoxes: [DetectedBox] = [],
        readings: [DetectorReading] = []
    ) {
        self.btaCount = btaCount
        self.confidence = confidence
        self.grade = grade
        self.analyzedAt = analyzedAt
        self.detectedBoxes = detectedBoxes
        self.readings = readings
    }

    /// This field's reading from a given model, if that model ran.
    func reading(_ detector: DetectorKind) -> DetectorReading? {
        readings.first { $0.detector == detector }
    }

    /// Readings from the models that did not drive the grade — empty when only one ran.
    func comparisonReadings(for selection: DetectorSelection) -> [DetectorReading] {
        selection.comparisonDetectors.compactMap(reading)
    }
}

enum BTAGrade: String, Hashable, CaseIterable, Sendable, Codable {
    case negative = "Negatif"
    case scanty   = "Scanty"
    case plus1    = "1+"
    case plus2    = "2+"
    case plus3    = "3+"

    /// Fields that must be read before this grade may be reported as final.
    ///
    /// WHO/IUATLD scales the workload to the density: a heavy smear declares itself
    /// quickly, while calling a slide Negatif or Scanty demands the full 100 fields —
    /// that is the reading which, if wrong, sends an infectious patient home untreated.
    var minimumFields: Int {
        switch self {
        case .plus3:                       return 20
        case .plus2:                       return 50
        case .plus1, .scanty, .negative:   return 100
        }
    }

    // IUATLD grading: totalBTA across all scanned fields, extrapolated to per-100-field scale
    static func grade(for totalBTA: Int, across fields: Int) -> BTAGrade {
        guard fields > 0, totalBTA > 0 else { return .negative }
        let per100 = Double(totalBTA) / Double(fields) * 100
        switch per100 {
        case ..<1:       return .negative
        case 1..<10:     return .scanty
        case 10..<100:   return .plus1
        case 100...1000: return .plus2
        default:         return .plus3
        }
    }
}
