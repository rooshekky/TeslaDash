import SwiftUI

/// Root view: pairing first (live mode only), otherwise the tabbed app.
struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        Group {
            if !viewModel.isPaired && viewModel.mode == .live {
                PairingView(viewModel: viewModel)
            } else {
                MainTabView(viewModel: viewModel)
            }
        }
        .task {
            await viewModel.start()
        }
        .onAppear {
            viewModel.setScreenAwake(true)
        }
        .onDisappear {
            viewModel.setScreenAwake(false)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct MainTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        TabView {
            DashboardView(viewModel: viewModel)
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent") }
            MapPanelView(viewModel: viewModel)
                .tabItem { Label("Map", systemImage: "map") }
            TripHistoryView(viewModel: viewModel)
                .tabItem { Label("Trips", systemImage: "clock.arrow.circlepath") }
            SettingsView(viewModel: viewModel)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
