import Foundation


// MARK: - Extensions for existing Add-on models

public extension CCAddonProvider {
    /// Check if this provider supports a specific region
    func supportsRegion(_ region: String) -> Bool {
        return regions?.contains(region) ?? false
    }
    
    /// Get available plans for a specific region (simplified - no zone filtering for now)
    func plansForRegion(_ region: String) -> [CCAddonPlan] {
        return (plans ?? []).sorted { $0.price < $1.price }
    }
    
    /// Get a safe shortDesc
    var safeShortDesc: String {
        return shortDesc ?? "No description available"
    }
    
    /// Provider display name with icon for creation UI
    var displayNameWithIcon: String {
        switch id.lowercased() {
        case "postgresql-addon", "postgres":
            return "🐘 \(name)"
        case "mysql-addon":
            return "🐬 \(name)"
        case "redis-addon":
            return "🔴 \(name)"
        case "mongodb-addon", "mongo":
            return "🍃 \(name)"
        case "elasticsearch-addon":
            return "🔍 \(name)"
        case "jenkins-addon":
            return "⚙️ \(name)"
        case "pulsar-addon":
            return "📡 \(name)"
        case "materia-addon":
            return "🔧 \(name)"
        default:
            return "📦 \(name)"
        }
    }
}

public extension CCAddonPlan {
    /// Display price in a user-friendly format
    var displayPrice: String {
        return String(format: "%.2f€/month", price)
    }
    
    /// Display memory in a user-friendly format (simplified - no memory info in current model)
    var displayMemory: String? {
        return nil // Current model doesn't have memory info
    }
    
    /// Display disk in a user-friendly format (simplified - no disk info in current model)  
    var displayDisk: String? {
        return nil // Current model doesn't have disk info
    }
    
    /// Convert features array to strings for compatibility
    var featuresStrings: [String] {
        return features?.map { $0.name } ?? []
    }
}

// MARK: - Creation Request Models

/// Request model for creating a new add-on
public struct CCAddonCreationRequest: Codable {
    public let name: String
    public let plan: String
    public let providerId: String
    public let region: String
    public let options: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case name, plan, region, options
        case providerId = "providerId"
    }
    
    public init(
        name: String,
        plan: String,
        providerId: String,
        region: String,
        options: [String: String]? = nil
    ) {
        self.name = name
        self.plan = plan
        self.providerId = providerId
        self.region = region
        self.options = options
    }
}

/// Response model for add-on preordering (validation)
public struct CCAddonPreorderResponse: Codable {
    public let totalTTC: Double?
    public let totalHT: Double?
    public let currency: String?
    public let error: String?
    
    enum CodingKeys: String, CodingKey {
        case totalTTC = "totalTTC"
        case totalHT = "totalHT"
        case currency, error
    }
}

// MARK: - Validation Helpers



