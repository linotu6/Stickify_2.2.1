import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .capture
    @StateObject private var stateStore = StickifyStateStore()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .capture:
                    CaptureView(demoState: demoStateBinding)
                case .library:
                    LibraryView(demoState: demoStateBinding)
                case .playground:
                    PlaygroundView(demoState: demoStateBinding)
                }
            }
            .ignoresSafeArea()

            CloudTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StickifyTheme.carbonBlack)
        .preferredColorScheme(.light)
    }

    private var demoStateBinding: Binding<StickifyDemoState> {
        Binding(
            get: { stateStore.state },
            set: { stateStore.state = $0 }
        )
    }
}

#Preview {
    ContentView()
}
