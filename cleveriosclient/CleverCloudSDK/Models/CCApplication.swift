import Foundation

/// Represents a Clever Cloud application
public struct CCApplication: Codable, Identifiable, Equatable {
    
    // MARK: - Core Properties
    
    /// Unique application identifier
    public let id: String
    
    /// Application name
    public let name: String
    
    /// Application description
    public let description: String?
    
    /// Application zone (deployment region)
    public let zone: String
    
    /// Application zone ID
    public let zoneId: String
    
    /// Application instance configuration
    public let instance: CCInstance
    

    
    // MARK: - Computed Properties
    
    /// Application display name
    public var displayName: String {
        return name.isEmpty ? "Unnamed App" : name
    }
    
    /// Application short ID
    public var shortId: String {
        return String(id.suffix(8))
    }
    
    // MARK: - Initializer
    
    public init(id: String, name: String, description: String?, zone: String, zoneId: String, instance: CCInstance) {
        self.id = id
        self.name = name
        self.description = description
        self.zone = zone
        self.zoneId = zoneId
        self.instance = instance
    }
}

// MARK: - CCInstance

/// Represents application instance configuration
public struct CCInstance: Codable, Equatable {
    /// Instance type (e.g., "node", "python", etc.)
    public let type: String
    
    /// Instance version
    public let version: String
    
    /// Instance variant
    public let variant: CCInstanceVariant?
    
    /// Minimum instances count
    public let minInstances: Int
    
    /// Maximum instances count  
    public let maxInstances: Int
    
    /// Maximum allowed instances
    public let maxAllowedInstances: Int
    
    /// Minimum flavor configuration
    public let minFlavor: CCFlavor
    
    /// Maximum flavor configuration
    public let maxFlavor: CCFlavor
    
    /// Available flavors
    public let flavors: [CCFlavor]?
}

// MARK: - CCInstanceVariant

/// Represents instance variant information
public struct CCInstanceVariant: Codable, Equatable, Sendable {
    /// Variant ID
    public let id: String
    
    /// Variant slug
    public let slug: String
    
    /// Variant name
    public let name: String
    
    /// Deploy type
    public let deployType: String
    
    /// Logo URL
    public let logo: String?
}

// MARK: - CCFlavor

/// Represents a flavor (size configuration) for an instance
public struct CCFlavor: Codable, Identifiable, Equatable, Sendable {
    /// Flavor name
    public let name: String
    
    /// Identifiable conformance
    public var id: String { return name }
    
    /// Memory in MB
    public let mem: Int
    
    /// Number of CPUs
    public let cpus: Int
    
    /// Number of GPUs
    public let gpus: Int
    
    /// Disk space
    public let disk: Int
    
    /// Price per hour
    public let price: Double
    
    /// Whether this flavor is available
    public let available: Bool
    
    /// Whether this is a microservice flavor
    public let microservice: Bool
    
    /// Whether this supports machine learning
    public let machine_learning: Bool
    
    /// Nice level
    public let nice: Int
    
    /// Price ID
    public let price_id: String
    
    /// Memory configuration
    public let memory: CCMemoryInfo?
    
    /// CPU factor
    public let cpuFactor: Double
    
    /// Memory factor
    public let memFactor: Double
}

// MARK: - CCFlavor Extensions for Creation UI

public extension CCFlavor {
    /// Display memory in a user-friendly format
    var displayMemory: String {
        if mem >= 1024 {
            return "\(mem / 1024) GB"
        } else {
            return "\(mem) MB"
        }
    }
    
    /// Display price in a user-friendly format
    var displayPrice: String {
        return String(format: "%.3f€/h", price)
    }
}

// MARK: - CCMemoryInfo

/// Represents memory information
public struct CCMemoryInfo: Codable, Equatable, Sendable {
    /// Memory unit
    public let unit: String
    
    /// Memory value in bytes
    public let value: Int
    
    /// Formatted memory string
    public let formatted: String
}



// MARK: - Instance State (Real runtime states from Clever Cloud)

/// Possible states of a running Clever Cloud instance
public enum InstanceState: String, CaseIterable, Codable {
    case up = "UP"
    case deploying = "DEPLOYING"
    case down = "DOWN"
    case failed = "FAILED"
    case stopped = "STOPPED"
    case unknown = "UNKNOWN"
    
    public var description: String {
        switch self {
        case .up: return "Up"
        case .deploying: return "Deploying"
        case .down: return "Down"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Application Computed Status (Calculated from instances)

/// Computed status of an application based on its instances
public enum ApplicationStatus: String, CaseIterable {
    case running = "RUNNING"      // Has UP instances
    case deploying = "DEPLOYING"  // Has DEPLOYING instances
    case stopped = "STOPPED"      // No UP or DEPLOYING instances
    case failed = "FAILED"        // Has FAILED instances
    case unknown = "UNKNOWN"      // Unknown state
    
    public var description: String {
        switch self {
        case .running: return "Running"
        case .deploying: return "Deploying"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }
    
    /// Compute application status from instances
    public static func compute(from instances: [CCApplicationInstance]) -> ApplicationStatus {
        // Parse string states to enum
        let upInstances = instances.filter { $0.state.uppercased() == "UP" }
        let deployingInstances = instances.filter { $0.state.uppercased() == "DEPLOYING" }
        let failedInstances = instances.filter { $0.state.uppercased() == "FAILED" }
        
        if !upInstances.isEmpty {
            return .running
        } else if !deployingInstances.isEmpty {
            return .deploying
        } else if !failedInstances.isEmpty {
            return .failed
        } else if instances.isEmpty {
            return .stopped
        } else {
            return .unknown
        }
    }
}

// MARK: - Application Runtime
public enum ApplicationRuntime: String, CaseIterable, Codable {
    case nodejs = "nodejs"
    case java = "java"
    case python = "python"
    case php = "php"
    case ruby = "ruby"
    case go = "go"
    case rust = "rust"
    case docker = "docker"
    case `static` = "static"
    
    public var displayName: String {
        switch self {
        case .nodejs: return "Node.js"
        case .java: return "Java"
        case .python: return "Python"
        case .php: return "PHP"
        case .ruby: return "Ruby"
        case .go: return "Go"
        case .rust: return "Rust"
        case .docker: return "Docker"
        case .`static`: return "Static"
        }
    }
}

// MARK: - Instance Type
public enum InstanceType: String, CaseIterable, Codable {
    case nano = "nano"
    case xs = "XS"
    case s = "S"
    case m = "M"
    case l = "L"
    case xl = "XL"
    case xxl = "2XL"
    case xxxl = "3XL"
    
    public var displayName: String {
        switch self {
        case .nano: return "Nano (FREE)"
        case .xs: return "XS"
        case .s: return "S"
        case .m: return "M"
        case .l: return "L"
        case .xl: return "XL"
        case .xxl: return "2XL"
        case .xxxl: return "3XL"
        }
    }
}

// MARK: - Zone
public enum Zone: String, CaseIterable, Codable {
    case parisFirstZone = "par"
    case parisSecondZone = "rbx"
    case gravitee = "gra"
    case montreal = "mtl"
    case sydney = "syd"
    case warsaw = "wsw"
    
    public var displayName: String {
        switch self {
        case .parisFirstZone: return "Paris (par)"
        case .parisSecondZone: return "Roubaix (rbx)"
        case .gravitee: return "Graveline (gra)"
        case .montreal: return "Montreal (mtl)"
        case .sydney: return "Sydney (syd)"
        case .warsaw: return "Warsaw (wsw)"
        }
    }
}

// MARK: - Application Update Model

/// Model for updating an existing application
public struct CCApplicationUpdate: Codable {
    public let name: String?
    public let description: String?
    public let minInstances: Int?
    public let maxInstances: Int?
    public let minFlavor: String?
    public let maxFlavor: String?
    public let runtime: String?
    public let branch: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case minInstances = "min_instances"
        case maxInstances = "max_instances"
        case minFlavor = "min_flavor"
        case maxFlavor = "max_flavor"
        case runtime
        case branch
    }
    
    public init(
        name: String? = nil,
        description: String? = nil,
        minInstances: Int? = nil,
        maxInstances: Int? = nil,
        minFlavor: String? = nil,
        maxFlavor: String? = nil,
        runtime: String? = nil,
        branch: String? = nil
    ) {
        self.name = name
        self.description = description
        self.minInstances = minInstances
        self.maxInstances = maxInstances
        self.minFlavor = minFlavor
        self.maxFlavor = maxFlavor
        self.runtime = runtime
        self.branch = branch
    }
}

// MARK: - Supporting Models

// Add-on models have been moved to CCAddon.swift for better organization

// MARK: - Sample Application Extension

extension CCApplication {
    /// Sample application for previews and testing
    public static var sampleApplication: CCApplication {
        return CCApplication(
            id: "app_123456789",
            name: "Sample Application",
            description: "A sample application for testing",
            zone: "par",
            zoneId: "par_01",
            instance: CCInstance(
                type: "node",
                version: "18",
                variant: nil,
                minInstances: 1,
                maxInstances: 3,
                maxAllowedInstances: 40,
                minFlavor: CCFlavor(
                    name: "S",
                    mem: 1024,
                    cpus: 1,
                    gpus: 0,
                    disk: 1024,
                    price: 0.6,
                    available: true,
                    microservice: false,
                    machine_learning: false,
                    nice: 0,
                    price_id: "s_flavor",
                    memory: nil,
                    cpuFactor: 1.0,
                    memFactor: 1.0
                ),
                maxFlavor: CCFlavor(
                    name: "S",
                    mem: 1024,
                    cpus: 1,
                    gpus: 0,
                    disk: 1024,
                    price: 0.6,
                    available: true,
                    microservice: false,
                    machine_learning: false,
                    nice: 0,
                    price_id: "s_flavor",
                    memory: nil,
                    cpuFactor: 1.0,
                    memFactor: 1.0
                ),
                flavors: nil
            )
        )
    }
}

 