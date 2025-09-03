import Foundation

// MARK: - Elasticsearch Format

/// Represents the Elasticsearch format returned by the logs API
struct ElasticsearchLogEntry: Codable {
    let index: String
    let type: String
    let id: String
    let source: LogSource
    let sort: [Int]?
    
    enum CodingKeys: String, CodingKey {
        case index = "_index"
        case type = "_type"
        case id = "_id"
        case source = "_source"
        case sort
    }
    
    struct LogSource: Codable {
        let message: String
        let timestamp: String
        let host: String?
        let type: String?
        let syslogProgram: String?
        let syslogSeverity: String?
        let appId: String?
        let deploymentId: String?
        let sourceHost: String?
        let zone: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case timestamp = "@timestamp"
            case host
            case type
            case syslogProgram = "syslog_program"
            case syslogSeverity = "syslog_severity"
            case appId
            case deploymentId
            case sourceHost = "@source_host"
            case zone
        }
    }
}

// MARK: - Log Models

/// Represents a log entry from Clever Cloud
public struct CCLogEntry: Codable, Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let level: CCLogLevel
    public let source: String?
    public let instanceId: String?
    
    enum CodingKeys: String, CodingKey {
        case timestamp = "@timestamp"
        case message
        case level
        case source
        case instanceId = "instance_id"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle timestamp
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            if let date = ISO8601DateFormatter().date(from: timestampString) {
                self.timestamp = date
            } else {
                self.timestamp = Date()
            }
        } else if let timestampDouble = try? container.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: timestampDouble / 1000)
        } else {
            self.timestamp = Date()
        }
        
        // Message
        self.message = try container.decode(String.self, forKey: .message)
        
        // Level - default to info if not provided
        if let levelString = try? container.decode(String.self, forKey: .level) {
            self.level = CCLogLevel(rawValue: levelString.lowercased()) ?? .info
        } else {
            // Try to infer from message
            let lowercasedMessage = message.lowercased()
            if lowercasedMessage.contains("error") || lowercasedMessage.contains("fail") {
                self.level = .error
            } else if lowercasedMessage.contains("warn") {
                self.level = .warning
            } else if lowercasedMessage.contains("debug") {
                self.level = .debug
            } else {
                self.level = .info
            }
        }
        
        // Optional fields
        self.source = try? container.decode(String.self, forKey: .source)
        self.instanceId = try? container.decode(String.self, forKey: .instanceId)
    }
    
    public init(timestamp: Date, message: String, level: CCLogLevel, source: String? = nil, instanceId: String? = nil) {
        self.timestamp = timestamp
        self.message = message
        self.level = level
        self.source = source
        self.instanceId = instanceId
    }
}

/// Log level enumeration
public enum CCLogLevel: String, Codable, CaseIterable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    
    public var color: String {
        switch self {
        case .debug:
            return "gray"
        case .info:
            return "blue"
        case .warning:
            return "orange"
        case .error:
            return "red"
        }
    }
    
    public var icon: String {
        switch self {
        case .debug:
            return "ant.circle"
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }
} 