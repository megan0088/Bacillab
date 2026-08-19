import PhotosUI
import SwiftUI

/// The shutter, plus the gallery-import button beside it.
///
/// The two stay together deliberately: camera capture and gallery import share one recording
/// path in `ScanViewModel` (same framing, same write-then-append order), and splitting their
/// controls into separate components would suggest they were two different pipelines.
struct ShutterBar: View {
    let viewModel: ScanViewModel
    let session: ExamSession
    @Binding var goToReview: Bool
    @Binding var pickedPhoto: PhotosPickerItem?
    @Binding var isImporting: Bool

    var body: some View {
        VStack(spacing: 16) {
            // A white shutter on black, the way every camera app draws it — the one control the
            // technician has to find without looking away from the eyepiece.
            Button {
                viewModel.toggleScan(session: session)
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(viewModel.isScanning ? 1 : 0.45), lineWidth: 3)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(viewModel.isScanning ? Color.accentColor : .white)
                        .frame(width: 64, height: 64)
                    if viewModel.isScanning {
                        Image(systemName: "stop.fill")
                            .font(.appHeading)
                            .foregroundStyle(.white)
                    }
                }
            }

            Text(viewModel.isScanning ? "Tap to stop" : "Start Scan")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                // Importing is the only way to exercise detection without a microscope clamped
                // to the phone, so it stays beside the shutter rather than being buried.
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(
                        isImporting ? "Importing…" : "Import Photo",
                        systemImage: isImporting ? "hourglass" : "photo.on.rectangle.angled"
                    )
                    .font(.appCaption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.12), in: Capsule())
                }
                .disabled(isImporting)

                if !session.fields.isEmpty {
                    Button {
                        viewModel.stopScan()
                        session.status = .reviewing
                        goToReview = true
                    } label: {
                        Label("Review", systemImage: "arrow.right")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            }
        }
    }
}

#Preview("Shutter Bar") {
    let session = ExamSession()
    let dependencies = AppDependencies()
    let viewModel = ScanViewModel(
        cameraService: dependencies.cameraService,
        store: dependencies.sessionStore,
        queue: dependencies.queue(for: session)
    )
    return ZStack {
        Color.black.ignoresSafeArea()
        ShutterBar(
            viewModel: viewModel,
            session: session,
            goToReview: .constant(false),
            pickedPhoto: .constant(nil),
            isImporting: .constant(false)
        )
    }
}
