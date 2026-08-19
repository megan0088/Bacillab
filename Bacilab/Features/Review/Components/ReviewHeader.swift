import SwiftUI

struct ReviewHeader: View {
    let viewModel: ReviewViewModel

    var body: some View {
        analysisProgress
    }

    // MARK: - Queue

    private var analysisProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Analysing \(viewModel.session.fields.count - viewModel.queue.remaining) "
                 + "of \(viewModel.session.fields.count) fields…")
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
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
    return ReviewHeader(viewModel: viewModel)
        .padding(.vertical)
        .background(Color.black)
}
