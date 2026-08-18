import Foundation

/// Apa yang dibuat model atas satu lapang.
struct FieldAnalysis: Codable, Hashable, Sendable {
    let readings: [DetectorReading]
    /// Model yang hitungannya dipakai. Model lain ikut tersimpan untuk dibandingkan,
    /// tapi tidak pernah menjadi angka yang dipakai.
    let primary: DetectorKind

    var primaryReading: DetectorReading? {
        readings.first { $0.detector == primary }
    }

    /// Hitungan model utama, atau nil kalau model itu gagal pada lapang ini.
    var count: Int? {
        guard let r = primaryReading, r.failure == nil else { return nil }
        return r.btaCount
    }

    var confidence: Double? {
        guard let r = primaryReading, r.failure == nil else { return nil }
        return r.confidence
    }
}

/// Where a field's image came from.
///
/// Recorded per field rather than per session: a slide read partly through the eyepiece and
/// partly from imported photos pools two different acquisitions into one count, and without
/// this nothing downstream would show that it happened.
enum FieldSource: String, Codable, Hashable, Sendable, CaseIterable {
    case camera
    case gallery

    var label: String {
        switch self {
        case .camera:  return "Camera"
        case .gallery: return "Imported"
        }
    }

    var icon: String {
        switch self {
        case .camera:  return "camera.fill"
        case .gallery: return "photo.on.rectangle.angled"
        }
    }
}

/// Satu lapang pandang yang sudah direkam.
///
/// `imageFileName` relatif terhadap direktori sesi, bukan URL absolut: path kontainer
/// aplikasi iOS berubah antar-instalasi, jadi URL absolut yang tersimpan akan menunjuk
/// ke berkas yang tidak ada lagi setelah app diperbarui.
struct FieldRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let imageFileName: String
    let source: FieldSource
    var analysis: FieldAnalysis?
    var correctedCount: Int?
    var isExcluded: Bool

    init(
        id: UUID = UUID(),
        index: Int,
        imageFileName: String,
        source: FieldSource = .camera,
        analysis: FieldAnalysis? = nil,
        correctedCount: Int? = nil,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.index = index
        self.imageFileName = imageFileName
        self.source = source
        self.analysis = analysis
        self.correctedCount = correctedCount
        self.isExcluded = isExcluded
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, index, imageFileName, source, analysis, correctedCount, isExcluded
    }

    /// Hand-written only so `source` may be absent. Manifests written before fields recorded
    /// their origin decode as camera fields instead of failing, which would otherwise take the
    /// whole session down with them — `SessionStore` skips a session it cannot decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        imageFileName = try container.decode(String.self, forKey: .imageFileName)
        source = try container.decodeIfPresent(FieldSource.self, forKey: .source) ?? .camera
        analysis = try container.decodeIfPresent(FieldAnalysis.self, forKey: .analysis)
        correctedCount = try container.decodeIfPresent(Int.self, forKey: .correctedCount)
        isExcluded = try container.decode(Bool.self, forKey: .isExcluded)
    }

    /// Hitungan yang berlaku, atau nil kalau belum ada.
    ///
    /// Optional dengan sengaja: lapang tanpa hitungan bukan lapang bernilai nol. Memaksanya
    /// jadi 0 akan membuat model yang gagal terlihat sama persis dengan model yang tidak
    /// menemukan apa-apa, dan lapang itu akan menyeret grade turun tanpa jejak.
    var effectiveCount: Int? {
        if let correctedCount { return correctedCount }
        return analysis?.count
    }

    /// Masuk ke pembilang dan penyebut grading.
    var isCounted: Bool { !isExcluded && effectiveCount != nil }

    /// Analisis sudah jalan tapi tidak menghasilkan angka, dan analis belum mengisinya.
    var needsManualCount: Bool {
        !isExcluded && analysis != nil && analysis?.count == nil && correctedCount == nil
    }

    /// Masih menunggu giliran di antrean analisis.
    ///
    /// Lapang yang sudah dibuang (sebelum atau sesudah analisis) tidak menunggu lagi.
    var isPending: Bool { !isExcluded && analysis == nil && correctedCount == nil }
}
