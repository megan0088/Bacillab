import SwiftUI

struct FieldCountRow: View {
    let viewModel: ReviewViewModel
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button {
                onEdit()
            } label: {
                HStack(spacing: 10) {
                    Text(countLabel)
                        .font(.appHeading.weight(.bold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("BTA")
                        .font(.appBody.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "pencil")
                        .font(.appCaption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .foregroundStyle(.primary)

            confidenceLine
        }
    }

    /// Below this the field is flagged for a manual look. **Not calibrated** against read slides.
    private static let lowConfidencePercent = 85

    private var countLabel: String {
        guard let field = viewModel.selectedField else { return "—" }
        if field.isExcluded { return "—" }
        guard let count = field.effectiveCount else { return "—" }
        return "\(count)"
    }

    /// Confidence ditampilkan sebagai milik model, bukan sebagai kepastian hasil.
    ///
    /// Grafik ONNX sudah membuang deteksi di bawah 0,70, jadi angka ini tidak pernah bisa
    /// terbaca di bawah 70% betapapun lemahnya sebuah lapang. Ia menyatakan seberapa yakin
    /// model terhadap basil yang **ia simpan** — bukan seberapa yakin siapa pun terhadap
    /// hitungannya.
    @ViewBuilder
    private var confidenceLine: some View {
        if let field = viewModel.selectedField {
            if field.correctedCount != nil {
                Label("Corrected by analyst", systemImage: "hand.raised.fill")
                    .font(.appCaption)
                    .foregroundStyle(Color.accentColor)
            } else if field.analysis == nil {
                Text("Waiting for analysis…")
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            } else if field.effectiveCount == nil {
                Label("The model could not read this field — enter it manually",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.appCaption)
                    .foregroundStyle(.orange)
            } else if let confidence = field.analysis?.confidence {
                let percent = Int((confidence * 100).rounded())
                VStack(spacing: 4) {
                    Text("\(percent)% AI Confidence Level")
                        .font(.appCaption)
                        .foregroundStyle(.white.opacity(0.55))

                    // Prompts a second look; it never changes a count. The threshold is a
                    // starting point, not a calibrated one — and note the graph already discards
                    // detections below 0.70, so this figure can never read lower than 70% however
                    // weak the field is. It says how sure the model is about the bacilli it kept.
                    if percent < Self.lowConfidencePercent {
                        Label("Low AI Confidence, Verify Manually",
                              systemImage: "exclamationmark.circle.fill")
                            .font(.appCaption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

#Preview("Review – 6 lapang") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    for i in 0..<6 {
        let f = session.appendField(imageFileName: "f.jpg")
        session.setAnalysis(FieldAnalysis(
            readings: [DetectorReading(detector: .resnet, btaCount: i * 2,
                                       confidence: 0.86, elapsed: 0.6)],
            primary: .resnet), for: f.id)
    }
    let deps = AppDependencies()
    let viewModel = ReviewViewModel(
        session: session,
        store: deps.sessionStore,
        queue: deps.queue(for: session)
    )
    return FieldCountRow(viewModel: viewModel, onEdit: {})
        .padding(.vertical)
        .background(Color.black)
}
