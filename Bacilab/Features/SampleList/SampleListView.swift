import SwiftUI

struct SampleListView: View {
    @State private var viewModel: SampleListViewModel
    @Environment(AppDependencies.self) private var dependencies
    @State private var newSession: ExamSession?

    init(viewModel: SampleListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    banner
                    searchBar
                    sessionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottomTrailing) { fab }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExamSession.self) { session in
                destination(for: session)
            }
            .sheet(item: $newSession, onDismiss: { Task { await viewModel.load() } }) { session in
                NavigationStack {
                    PatientDataView(session: session, dependencies: dependencies)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.load() }
    }

    /// Sesi yang belum terbit dibuka kembali di tempat ia ditinggalkan; yang sudah terbit
    /// membuka lembar hasilnya — layar yang sama dengan ujung alur pemeriksaan.
    @ViewBuilder
    private func destination(for session: ExamSession) -> some View {
        switch session.status {
        case .scanning:
            ScanView(session: session, dependencies: dependencies)
        case .reviewing:
            ReviewView(session: session,
                       queue: dependencies.makeAnalysisQueue(),
                       dependencies: dependencies)
        case .published:
            ResultSheetView(session: session, dependencies: dependencies)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Electra Lab")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("BTA Analyzer")
                .font(.system(size: 32, weight: .black))
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
                                    .locale(Locale(identifier: "id_ID"))))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 64)
    }

    private var banner: some View {
        Button {
            newSession = ExamSession()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analisis Baru")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Mulai pemeriksaan BTA")
                        .font(.caption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20)
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cari nama atau no. rekam medis...",
                      text: Bindable(viewModel).searchText)
                .font(.system(.body, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Riwayat Pemeriksaan")
                .font(.system(.headline, design: .rounded, weight: .bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Semua", nil)
                    chip("Berjalan", .running)
                    chip("Positif", .positive)
                    chip("Negatif", .negative)
                }
            }

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if viewModel.filteredSessions.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Pemeriksaan",
                    systemImage: "testtube.2",
                    description: Text("Ketuk Analisis Baru untuk memulai")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.filteredSessions) { session in
                        NavigationLink(value: session) { row(for: session) }
                            .buttonStyle(.plain)
                            // Sesi yang ditinggalkan harus bisa dibuang: satu sesi 20 lapang
                            // memakan puluhan megabita, dan sesi salah-mulai akan menumpuk.
                            // `.onDelete` butuh `List`; menu tekan-tahan bekerja di sini.
                            .contextMenu {
                                Button("Hapus Pemeriksaan", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.delete(session) }
                                }
                            }
                        if session.id != viewModel.filteredSessions.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func chip(_ label: String, _ status: SessionDisplayStatus?) -> some View {
        let isSelected = viewModel.statusFilter == status
        return Button {
            viewModel.statusFilter = status
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.systemBackground), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(Capsule().stroke(isSelected ? .clear : Color(.systemGray4), lineWidth: 1))
        }
    }

    private func row(for session: ExamSession) -> some View {
        let color: Color = switch session.displayStatus {
        case .running:  .orange
        case .negative: .green
        case .positive: .red
        }

        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "microbe.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.patient.name.isEmpty ? "Tanpa nama" : session.patient.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text(session.patient.medicalRecordNumber.isEmpty
                     ? session.createdAt.formatted(date: .abbreviated, time: .shortened)
                     : session.patient.medicalRecordNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.displayStatus.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.12), in: Capsule())
                    .foregroundStyle(color)
                if session.displayStatus == .running {
                    Text("\(session.fields.count) lapang")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var fab: some View {
        Button {
            newSession = ExamSession()
        } label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
        }
        .padding(24)
    }
}

#Preview("Beranda") {
    let deps = AppDependencies()
    return SampleListView(viewModel: SampleListViewModel(sessionStore: deps.sessionStore))
        .environment(deps)
}
