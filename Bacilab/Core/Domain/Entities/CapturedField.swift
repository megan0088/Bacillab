import Foundation

/// Where a field's image came from.
///
/// A deliberate, sticky choice rather than something inferred per action. A slide read half
/// from the eyepiece and half from imported photos is two different acquisitions pooled into
/// one count, and nothing downstream would show that had happened.
enum FieldSource: String, Hashable, Sendable, CaseIterable, Identifiable {
    case camera
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera:  return "Kamera"
        case .gallery: return "Galeri"
        }
    }

    var icon: String {
        switch self {
        case .camera:  return "camera.fill"
        case .gallery: return "photo.on.rectangle.angled"
        }
    }
}

/// One field that was read, kept so it can be looked at again.
///
/// `image` is the centred square from `FieldFraming` — the exact pixels the detectors were
/// given — downscaled for storage. Keeping the raw photo instead would misplace every box,
/// since box coordinates are normalised against that square.
struct CapturedField: Identifiable, Hashable, Sendable {
    let id: UUID
    let image: Data
    let readings: [DetectorReading]
    let source: FieldSource
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        image: Data,
        readings: [DetectorReading],
        source: FieldSource,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.readings = readings
        self.source = source
        self.capturedAt = capturedAt
    }

    /// What a given model made of this field.
    func reading(_ detector: DetectorKind) -> DetectorReading? {
        readings.first { $0.detector == detector }
    }
}
