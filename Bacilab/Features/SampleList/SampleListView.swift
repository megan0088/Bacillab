import SwiftUI

struct SampleListView: View {
    @State private var viewModel: SampleListViewModel
    @Environment(AppDependencies.self) private var dependencies
    @State private var showingNewSampleFlow = false
    @State private var selectedStatus: SampleStatus? = nil
    @State private var searchText = ""

    init(viewModel: SampleListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    bannerCard
                    searchBar
                    samplesSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottomTrailing) { fab }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Sample.self) { sample in
                ResultView(
                    viewModel: ResultViewModel(
                        sample: sample,
                        sampleRepository: dependencies.sampleRepository
                    )
                )
            }
            .sheet(isPresented: $showingNewSampleFlow, onDismiss: {
                Task { await viewModel.loadSamples() }
            }) {
                NavigationStack {
                    DataInputView(draft: SampleDraft(), dependencies: dependencies)
                }
                .environment(dependencies)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.loadSamples() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Klinik Bunda")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("BTA Analyzer")
                .font(.system(size: 32, weight: .black))
            Text(
                Date.now.formatted(
                    .dateTime
                        .weekday(.wide)
                        .day()
                        .month(.wide)
                        .year()
                        .locale(Locale(identifier: "id_ID"))
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 64)
    }

    // MARK: - Banner

    private var bannerCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 110)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Spacer()
                    Button {
                        showingNewSampleFlow = true
                    } label: {
                        Label("New Analysis", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.2), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)

                Spacer()

                Text("Mulai analisis BTA hari ini")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cari nama pasien...", text: $searchText)
                .font(.system(.body, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Samples Section

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Riwayat Sampel")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Button("Lihat semua >") {}
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusChip(label: "Semua",   isSelected: selectedStatus == nil)  { selectedStatus = nil }
                    StatusChip(label: "Positif", isSelected: selectedStatus == .positive) { selectedStatus = .positive }
                    StatusChip(label: "Negatif", isSelected: selectedStatus == .negative) { selectedStatus = .negative }
                    StatusChip(label: "Pending", isSelected: selectedStatus == .pending)  { selectedStatus = .pending }
                }
            }

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if filteredSamples.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Sampel",
                    systemImage: "testtube.2",
                    description: Text("Ketuk + untuk memulai analisis baru")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredSamples) { sample in
                        NavigationLink(value: sample) {
                            SampleRow(sample: sample)
                        }
                        .buttonStyle(.plain)
                        if sample.id != filteredSamples.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var filteredSamples: [Sample] {
        let byStatus: [Sample]
        if let status = selectedStatus {
            byStatus = viewModel.samples.filter { $0.status == status }
        } else {
            byStatus = viewModel.samples
        }
        guard !searchText.isEmpty else { return byStatus }
        return byStatus.filter { $0.patientName.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - FAB

    private var fab: some View {
        Button { showingNewSampleFlow = true } label: {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
        }
        .padding(24)
    }
}

// MARK: - Supporting Views

private struct StatusChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.systemBackground), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
                )
        }
    }
}

private struct SampleRow: View {
    let sample: Sample

    private var statusColor: Color {
        switch sample.status {
        case .positive: return .red
        case .negative: return .green
        case .pending:  return .orange
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Square blue icon
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "microbe.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(sample.patientName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(sample.examinationDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(sample.status.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.12), in: Capsule())
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

#Preview("Home – with data") {
    let deps = AppDependencies()
    let vm = SampleListViewModel(sampleRepository: deps.sampleRepository)
    vm.samples = Sample.previews
    return SampleListView(viewModel: vm)
        .environment(deps)
}

#Preview("Home – empty state") {
    let deps = AppDependencies()
    return SampleListView(
        viewModel: SampleListViewModel(sampleRepository: deps.sampleRepository)
    )
    .environment(deps)
}
