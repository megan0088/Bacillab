import SwiftUI

@main
struct ElectraLabApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            SampleListView(
                viewModel: SampleListViewModel(
                    sessionStore: dependencies.sessionStore,
                    seedsDemoData: true
                )
            )
            .environment(dependencies)
        }
    }
}
