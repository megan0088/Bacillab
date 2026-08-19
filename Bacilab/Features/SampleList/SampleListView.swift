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
                    sessionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color(.systemGroupedBackground))
            // Search sits at the bottom of the list rather than above it: the history is what
            // the technician came for, and search is what they reach for only when it is long.
            // The "+" lives in the banner, so there is no separate FAB.
            //
            // `safeAreaInset` rather than `.overlay`: it insets the scroll content by the bar's
            // own height, so the bar can never cover a row. As an overlay it did — with the
            // vertical space of a landscape screen, the one seeded session sat underneath it and
            // read as an empty history.
            .safeAreaInset(edge: .bottom) { searchBar }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExamSession.self) { session in
                destination(for: session)
            }
            .sheet(item: $newSession, onDismiss: { Task { await viewModel.load() } }) { session in
                NavigationStack {
                    PatientDataView(session: session, dependencies: dependencies)
                }
            }
            .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
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
                       queue: dependencies.queue(for: session),
                       dependencies: dependencies)
        case .published:
            ResultSheetView(session: session, dependencies: dependencies)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Electra Lab")
                .font(.appBody)
                .foregroundStyle(.secondary)
            Text("BTA Analyzer")
                .font(.appTitle.weight(.black))
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.appCaption)
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
                    Text("New Analysis")
                        .font(.appHeading .weight(.bold))
                    Text("Input patient")
                        .font(.appCaption)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.appTitle)
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
            TextField("Search by ID card number", text: Bindable(viewModel).searchText)
                .font(.appBody)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color(.systemGray4), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.appHeading.weight(.medium))

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if viewModel.filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No examinations yet",
                    systemImage: "testtube.2",
                    description: Text("Tap New Analysis to start one")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.filteredSessions) { session in
                        NavigationLink(value: session) { row(for: session) }
                            .buttonStyle(.plain)
                            // An abandoned session has to be discardable: 20 fields is tens of
                            // megabytes, and mis-started sessions accumulate. `.onDelete` needs a
                            // `List`; a long-press menu works inside this `VStack`.
                            .contextMenu {
                                Button("Delete Examination", systemImage: "trash", role: .destructive) {
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

    private func row(for session: ExamSession) -> some View {
        let badge = SessionBadge(session: session)

        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "doc.text.fill")
                        .font(.appHeading)
                        .foregroundStyle(Color.accentColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.patient.examinationDate.formatted(.dateTime.day().month(.wide).year()))
                    .font(.appCaption)
                    .foregroundStyle(.secondary)

                // The record number leads: it is what is written on the tube and the form, and
                // is often the only thing the technician is holding when they come looking.
                Text(session.patient.medicalRecordNumber.isEmpty
                     ? "No MRN" : session.patient.medicalRecordNumber)
                    .font(.appBody.weight(.semibold))

                Text(session.patient.name.isEmpty ? "Unnamed" : session.patient.name)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Badge(text: badge.text, tint: badge.tint)
                .fixedSize()

            Image(systemName: "chevron.right")
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

}

#Preview("Home") {
    let deps = AppDependencies()
    return SampleListView(viewModel: SampleListViewModel(sessionStore: deps.sessionStore))
        .environment(deps)
}
