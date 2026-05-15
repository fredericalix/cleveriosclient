import Foundation

enum ApplicationTab: String, CaseIterable, Identifiable, Codable, Hashable {
    case configuration
    case metrics
    case deployments
    case logs
    case environment
    case domains
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configuration: return "Configuration"
        case .metrics: return "Metrics"
        case .deployments: return "Deployments"
        case .logs: return "Logs"
        case .environment: return "Environment"
        case .domains: return "Domains"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .configuration: return "gear"
        case .metrics: return "chart.bar"
        case .deployments: return "arrow.up.circle"
        case .logs: return "doc.text.magnifyingglass"
        case .environment: return "key.fill"
        case .domains: return "globe"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

enum ApplicationTabOrder {
    static let storageKey = "applicationTabOrder.v1"

    static let defaultOrder: [ApplicationTab] = [
        .configuration, .metrics, .deployments, .logs, .environment, .domains, .advanced
    ]

    static func load() -> [ApplicationTab] {
        guard let raw = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return defaultOrder
        }
        let parsed = raw.compactMap(ApplicationTab.init(rawValue:))
        let missing = ApplicationTab.allCases.filter { !parsed.contains($0) }
        let merged = parsed + missing
        return merged.isEmpty ? defaultOrder : merged
    }

    static func save(_ tabs: [ApplicationTab]) {
        UserDefaults.standard.set(tabs.map(\.rawValue), forKey: storageKey)
        NotificationCenter.default.post(name: .applicationTabOrderChanged, object: nil)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .applicationTabOrderChanged, object: nil)
    }
}

extension Notification.Name {
    static let applicationTabOrderChanged = Notification.Name("applicationTabOrderChanged")
}
