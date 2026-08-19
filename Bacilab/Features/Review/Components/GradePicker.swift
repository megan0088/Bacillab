import SwiftUI

struct GradePicker: View {
    @Bindable var session: ExamSession
    let viewModel: ReviewViewModel
    let onContinueScanning: () -> Void

    var body: some View {
        gradeSection
    }

    // MARK: - Grade

    private var gradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set Grade")
                .font(.appBody.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BTAGrade.allCases, id: \.self) { grade in
                        Button {
                            viewModel.chooseGrade(grade)
                        } label: {
                            Text(grade.displayName)
                                .font(.appCaption.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(session.reportedGrade == grade
                                            ? Color.accentColor : Color(.systemGray5),
                                            in: Capsule())
                                .foregroundStyle(session.reportedGrade == grade ? .white : .primary)
                        }
                    }
                }
            }

            if !session.isGradeConfirmed {
                provisionalNotice
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    /// Below the WHO/IUATLD threshold this grade may not stand as a report.
    private var provisionalNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the warning is suppressed for the exhibition. `Continue Scanning` below stays
            // either way — hiding the shortfall *and* the way to fix it would leave the analyst
            // no route to a grade that is actually confirmed.
            if !DemoMode.hidesProvisionalMarks {
                Label(
                    "\(session.reportedGrade.displayName) needs \(session.reportedGrade.minimumFields) "
                    + "fields (WHO/IUATLD). \(session.fieldsRemainingForGrade) more to go — "
                    + "the result will be stamped PROVISIONAL.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.appCaption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onContinueScanning()
            } label: {
                Label("Continue Scanning", systemImage: "camera.fill")
                    .font(.appCaption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Color.accentColor)
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
    return GradePicker(session: session, viewModel: viewModel, onContinueScanning: {})
        .padding(.vertical)
        .background(Color.black)
}
