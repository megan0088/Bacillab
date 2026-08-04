import SwiftUI

@main
struct ElectraLabApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            SampleListView(
                viewModel: SampleListViewModel(
                    sampleRepository: dependencies.sampleRepository
                )
            )
            .environment(dependencies)
        }
    }
}
