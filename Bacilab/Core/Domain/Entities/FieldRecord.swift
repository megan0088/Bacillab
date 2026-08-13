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

/// Satu lapang pandang yang sudah direkam.
///
/// `imageFileName` relatif terhadap direktori sesi, bukan URL absolut: path kontainer
/// aplikasi iOS berubah antar-instalasi, jadi URL absolut yang tersimpan akan menunjuk
/// ke berkas yang tidak ada lagi setelah app diperbarui.
struct FieldRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let index: Int
    let imageFileName: String
    var analysis: FieldAnalysis?
    var correctedCount: Int?
    var isExcluded: Bool

    init(
        id: UUID = UUID(),
        index: Int,
        imageFileName: String,
        analysis: FieldAnalysis? = nil,
        correctedCount: Int? = nil,
        isExcluded: Bool = false
    ) {
        self.id = id
        self.index = index
        self.imageFileName = imageFileName
        self.analysis = analysis
        self.correctedCount = correctedCount
        self.isExcluded = isExcluded
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
    var isPending: Bool { analysis == nil && correctedCount == nil }
}
