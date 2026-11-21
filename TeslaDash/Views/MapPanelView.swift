import MapKit
import SwiftUI

/// Full-screen live map with destination search and on-device routing.
///
/// The map shows the phone's GPS position (the phone is in the car).
/// Routing is done on-device with MapKit; ETA and battery-on-arrival
/// are computed by `DashboardViewModel` — the car only reports its own
/// active destination, it does not provide routing.
struct MapPanelView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var cameraPosition = MapCameraPosition.automatic
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $cameraPosition) {
                if let route = viewModel.route {
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
                }
                if let dest = viewModel.routeDestinationCoordinate {
                    Marker(viewModel.destinationName ?? "Destination", coordinate: dest)
                }
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onAppear {
                centerOnCar()
            }

            VStack(spacing: 8) {
                searchBar
                if !searchResults.isEmpty {
                    resultsList
                }
                if viewModel.route != nil {
                    routeCard
                }
            }
            .padding()
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search destination", text: $searchText)
                .autocorrectionDisabled()
                .onSubmit { runSearch() }
            if isSearching {
                ProgressView()
            }
            Button(action: centerOnCar) {
                Image(systemName: "location.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(searchResults, id: \.self) { item in
                Button {
                    searchResults = []
                    searchText = item.name ?? ""
                    Task { await viewModel.requestRoute(to: item) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unknown place")
                            .font(.subheadline).bold()
                        Text(item.placemark.title ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func runSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        if let coord = viewModel.mapCoordinate {
            request.region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
            isSearching = false
        }
    }

    // MARK: - Route card

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(viewModel.destinationName ?? "Destination")
                    .font(.headline)
                Spacer()
                Button("End") { viewModel.clearRoute() }
                    .font(.subheadline)
            }
            if let route = viewModel.route {
                Text("ETA \(viewModel.routeETA ?? "—") · \(Int(route.distance / 1609.34)) mi · \(Int(route.expectedTravelTime / 60)) min")
                    .font(.subheadline)
            }
            if let arrival = viewModel.batteryOnArrivalPercent {
                Text("Battery on arrival: ~\(arrival)% (estimate)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Camera

    private func centerOnCar() {
        guard let coord = viewModel.mapCoordinate else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
    }
}
