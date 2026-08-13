import SwiftUI

/// Sesi scan. Menghasilkan lapang, dan tidak tahu apa-apa tentang BTA.
///
/// Kekosongan layar ini disengaja: teknisi sedang menempel di okuler, bukan menatap layar.
/// Hitungan, grade, perbandingan model, dan confidence semuanya ada di Review, tempat ia
/// sudah duduk dan sedang memutuskan.
struct ScanView: View {
    @Bindable var session: ExamSession
    @State private var viewModel: ScanViewModel
    let dependencies: AppDependencies
    @State private var goToReview = false

    init(session: ExamSession, dependencies: AppDependencies) {
        self.session = session
        self.dependencies = dependencies
        _viewModel = State(initialValue: ScanViewModel(
            cameraService: dependencies.cameraService,
            store: dependencies.sessionStore,
            queue: dependencies.makeAnalysisQueue()
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width - 32, 360)

            VStack(spacing: 0) {
                fieldCounter
                Spacer(minLength: 20)
                viewfinder(side: side)
                focusBadge.padding(.top, 14)
                Spacer(minLength: 20)
                controls
                    .padding(.bottom, max(geo.safeAreaInsets.bottom + 16, 32))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Sesi Pemeriksaan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToReview) {
            ReviewView(session: session, queue: viewModel.queue, dependencies: dependencies)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Izin Kamera Diperlukan", isPresented: $viewModel.permissionDenied) {
            Button("Buka Pengaturan") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Aplikasi tidak dapat mengakses kamera untuk memindai preparat. "
                 + "Aktifkan izin kamera di Pengaturan, lalu buka kembali layar ini.")
        }
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
    }

    // MARK: - Bagian

    private var fieldCounter: some View {
        VStack(spacing: 4) {
            Text("\(session.fields.count) dari \(ExamSession.batchTarget) lapang")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())

            ProgressView(
                value: Double(min(session.fields.count, ExamSession.batchTarget)),
                total: Double(ExamSession.batchTarget)
            )
            .tint(Color.accentColor)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    /// Kotak, bukan lingkaran.
    ///
    /// Preview layer memakai `resizeAspectFill`, jadi kotak ini persis crop yang diterima
    /// model. Lingkaran putus-putus di dalamnya hanya panduan mengarahkan okuler — ia tidak
    /// memotong apa pun. Masker lingkaran akan menyembunyikan sudut-sudut kotak ini (sekitar
    /// 21% luasnya), padahal area itu tetap dibaca dan dihitung model.
    private func viewfinder(side: CGFloat) -> some View {
        ZStack {
            #if targetEnvironment(simulator)
            RadialGradient(
                colors: [Color(.systemGray2), Color(.systemGray5), Color(.systemGray6)],
                center: .center, startRadius: 0, endRadius: side * 0.53
            )
            Text("Simulator")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            #else
            CameraPreviewView(session: viewModel.session)
            #endif

            Circle()
                .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .padding(2)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                        lineWidth: viewModel.isScanning ? 3 : 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 6)
    }

    private var focusBadge: some View {
        Group {
            if viewModel.isBlurry {
                Label("Fokus belum tajam", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Fokus tajam", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBlurry)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.toggleScan(session: session)
            } label: {
                ZStack {
                    Circle()
                        .stroke(viewModel.isScanning ? Color.accentColor : Color(.systemGray3),
                                lineWidth: 3)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(viewModel.isScanning ? Color.accentColor : Color(.systemGray6))
                        .frame(width: 68, height: 68)
                    Image(systemName: viewModel.isScanning ? "stop.fill" : "viewfinder.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.isScanning ? .white : Color.accentColor)
                }
            }

            Text(viewModel.isScanning ? "Ketuk untuk berhenti" : "Mulai Scan")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if !session.fields.isEmpty {
                Button {
                    viewModel.stopScan()
                    session.status = .reviewing
                    goToReview = true
                } label: {
                    Text("Selesai · Lanjut ke Review")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 32)
                .padding(.top, 6)
            }
        }
    }
}

#Preview("Sesi – belum ada lapang") {
    NavigationStack {
        ScanView(session: ExamSession(), dependencies: AppDependencies())
    }
}

#Preview("Sesi – 8 lapang") {
    let session = ExamSession()
    for _ in 0..<8 { session.appendField(imageFileName: "f.jpg") }
    return NavigationStack {
        ScanView(session: session, dependencies: AppDependencies())
    }
}
