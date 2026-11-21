import SwiftUI

/// Now-playing media from the car, with transport controls sent back
/// over BLE. (The library exposes track/artist/album/source and volume,
/// but no explicit play/pause state — the toggle button just toggles.)
struct MediaPanelView: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var state: VehicleState { viewModel.vehicleState }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.mediaTitle == nil && state.mediaArtist == nil {
                Text("Nothing playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.mediaTitle ?? "Unknown track")
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.mediaArtist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let album = state.mediaAlbum {
                        Text(album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let source = state.mediaSource {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let fraction = state.mediaVolumeFraction {
                ProgressView(value: fraction)
                    .tint(.primary)
            }

            HStack(spacing: 20) {
                controlButton(icon: "backward.fill", command: .mediaPrevious)
                controlButton(icon: "playpause.fill", command: .mediaToggle)
                controlButton(icon: "forward.fill", command: .mediaNext)
                Spacer()
                controlButton(icon: "volume.3.fill", command: .mediaVolumeDown)
                controlButton(icon: "speaker.wave.3.fill", command: .mediaVolumeUp)
            }
            .font(.title3)
        }
    }

    private func controlButton(icon: String, command: AppCommand) -> some View {
        Button {
            Task { await viewModel.sendCommand(command) }
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.connection.isConnected && viewModel.mode == .live)
    }
}
