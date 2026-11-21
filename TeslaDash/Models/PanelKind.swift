import Foundation

/// The swappable side panels on the dashboard, Dashla-style.
///
/// The user picks which panel lives on the left and right of the dashboard
/// in Settings; the choice is persisted in UserDefaults.
enum PanelKind: String, CaseIterable, Identifiable, Codable {
    case map
    case navigation
    case music
    case tirePressure
    case climate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: "Map"
        case .navigation: "Navigation"
        case .music: "Music"
        case .tirePressure: "Tire Pressure"
        case .climate: "Climate"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .navigation: "location.north.line"
        case .music: "music.note"
        case .tirePressure: "gauge.with.dots.needle.bottom.50percent"
        case .climate: "thermometer.medium"
        }
    }
}
