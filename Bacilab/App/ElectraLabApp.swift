import SwiftUI

@main
struct ElectraLabApp: App {
    @State private var dependencies = AppDependencies()
    @State private var isShowingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                SampleListView(
                    viewModel: SampleListViewModel(
                        sessionStore: dependencies.sessionStore,
                        seedsDemoData: true
                    )
                )
                .environment(dependencies)

                if isShowingSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            // The splash covers the first launch's demo seed, which writes 50 field images to
            // disk. Timed rather than tied to that work finishing: on a second launch there is
            // nothing to seed, and a splash that vanishes instantly reads as a flicker.
            .task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.45)) { isShowingSplash = false }
            }
        }
    }
}
