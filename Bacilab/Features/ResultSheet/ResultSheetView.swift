import SwiftUI

/// Lembar hasil. Read-only, dan sengaja demikian.
///
/// Grade, hitungan, dan catatan semuanya diputuskan di Review. Kalau layar ini bisa mengubah
/// salah satunya, akan ada dua tempat yang menentukan grade lagi — persis tabrakan yang
/// rancangan ini hilangkan.
struct ResultSheetView: View {
    let session: ExamSession
    let dependencies: AppDependencies

    @State private var isGradeExpanded = false

    private var grade: BTAGrade { session.reportedGrade }

    private var gradeColor: Color {
        switch grade {
        case .negative:              return .green
        case .scanty:                return .orange
        case .plus1, .plus2, .plus3: return .red
        }
    }

    private var gradeLabel: String {
        switch grade {
        case .negative: return "Negative"
        case .scanty:   return "Scanty (Borderline)"
        case .plus1:    return "Positif (1+)"
        case .plus2:    return "Positif (2+)"
        case .plus3:    return "Positif (3+)"
        }
    }

    private var gradeDescription: String {
        switch grade {
        case .negative: return "Tidak ditemukan BTA dalam 100 lapang pandang."
        case .scanty:   return "Ditemukan 1–9 BTA dalam 100 lapang pandang. Perlu pemeriksaan ulang."
        case .plus1:    return "Ditemukan 10–99 BTA dalam 100 lapang pandang."
        case .plus2:    return "Ditemukan 1–10 BTA per lapang pandang dalam setidaknya 50 lapang."
        case .plus3:    return "Ditemukan lebih dari 10 BTA per lapang pandang dalam setidaknya 20 lapang."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                patientSection
                resultSection
                statsSection
                if !session.notes.isEmpty { notesSection }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Result Sheet")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Pasien

    private var patientSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Patient Information")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 12)

            infoRow("Laboratorium", "Electra Lab")
            Divider().padding(.leading, 120)
            infoRow("No. Rekam Medis", session.patient.medicalRecordNumber)
            Divider().padding(.leading, 120)
            infoRow("NIK", session.patient.nationalID)
            Divider().padding(.leading, 120)
            infoRow("Nama", session.patient.name)
            Divider().padding(.leading, 120)
            infoRow("Tanggal Lahir", formatted(session.patient.dateOfBirth))
            Divider().padding(.leading, 120)
            infoRow("Tgl. Pemeriksaan", formatted(session.patient.examinationDate))
            Divider().padding(.leading, 120)
            infoRow("Waktu Ambil Sampel", formatted(session.patient.sampleCollectedAt, withTime: true))
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatted(_ date: Date, withTime: Bool = false) -> String {
        let locale = Locale(identifier: "id_ID")
        return withTime
            ? date.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(locale))
            : date.formatted(.dateTime.day().month(.wide).year().locale(locale))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Hasil

    /// How the grade was arrived at, shown when the grade row is tapped.
    ///
    /// A grade is an **extrapolation**: the bacilli counted across the fields actually read,
    /// scaled to 100 fields, landing in a band. "2+" does not mean two of anything. Without this
    /// the reader has to take the letter on trust, and the one number that matters clinically is
    /// the one they cannot check.
    @ViewBuilder
    private var gradeDerivation: some View {
        let fields = max(session.examinedFieldCount, 1)
        let per100 = Double(session.totalBTA) / Double(fields) * 100

        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(.white.opacity(0.35))

            derivationRow("Counted",
                          "\(session.totalBTA) BTA across \(session.examinedFieldCount) fields read")
            derivationRow("Extrapolated", String(format: "%.0f BTA per 100 fields", per100))
            derivationRow("Band", "\(grade.rawValue) — \(gradeDescription)")
            derivationRow("Fields required",
                          session.isGradeConfirmed
                          ? "\(grade.minimumFields) (WHO/IUATLD) — met"
                          : "\(grade.minimumFields) (WHO/IUATLD) — \(session.fieldsRemainingForGrade) short")

            // The comparison model never contributes to this number, and a reader has no other
            // way to know which of the two produced it.
            derivationRow("Counted by", "ResNet. YOLO11 read the same fields for comparison only.")

            // A slide read partly through the eyepiece and partly from imported photos is two
            // acquisitions pooled into one grade. Silent about it, this sheet would imply one.
            if session.importedFieldCount > 0 {
                derivationRow("Imported fields",
                              "\(session.importedFieldCount) of \(session.examinedFieldCount) came from photos, not the eyepiece")
            }
        }
        .padding(.top, 2)
    }

    private func derivationRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .frame(width: 108, alignment: .leading)
                .opacity(0.75)
            Text(value)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Label("AI analysis is not a medical diagnosis", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { isGradeExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: grade == .negative
                              ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                        Text(gradeLabel)
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Spacer()
                        if !session.isGradeConfirmed {
                            Text("PROVISIONAL")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.25), in: Capsule())
                        }
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .rotationEffect(.degrees(isGradeExpanded ? 180 : 0))
                    }
                }
                .foregroundStyle(.white)

                Text(gradeDescription)
                    .font(.caption)
                    .opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if isGradeExpanded { gradeDerivation }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradeColor, in: RoundedRectangle(cornerRadius: 14))

            if !session.isGradeConfirmed {
                Label(
                    "Only \(session.examinedFieldCount) fields read. \(grade.rawValue) requires "
                    + "\(grade.minimumFields) fields (WHO/IUATLD), so this result is not final.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Statistik

    private var statsSection: some View {
        HStack(spacing: 0) {
            statCell(icon: "scope", label: "Fields Read", value: "\(session.examinedFieldCount)")
            Divider().frame(height: 56)
            statCell(icon: "microbe.fill", label: "Total BTA", value: "\(session.totalBTA)")
            Divider().frame(height: 56)
            statCell(icon: "hand.raised.fill", label: "Analyst Corrections",
                     value: "\(session.fields.filter { $0.correctedCount != nil }.count)")
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func statCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Catatan

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Laboratory Notes")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(session.notes)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Lembar Hasil – 3+ final") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    session.status = .published
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 15,
                                       confidence: 0.9, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}

#Preview("Lembar Hasil – Negatif sementara") {
    let session = ExamSession()
    session.patient.name = "Siti Rahma"
    session.patient.medicalRecordNumber = "RM 240724-002"
    session.notes = "Sputum encer, kualitas sampel kurang baik."
    session.status = .published
    for _ in 0..<20 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: 0,
                                       confidence: 0.8, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    return NavigationStack {
        ResultSheetView(session: session, dependencies: AppDependencies())
    }
}
