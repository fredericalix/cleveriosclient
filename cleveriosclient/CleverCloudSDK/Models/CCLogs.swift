import Foundation

// MARK: - Log Models

/// Represents a log entry from Clever Cloud.
///
/// `id` is the **stable wire identifier** (e.g. `"253992374:120:0"` for v4 SSE), used by the live
/// stream views to dedupe across reconnections. If the wire payload doesn't carry an `id`, we fall
/// back to a deterministic synthetic key (`timestamp + message hash`) so two parses of the same
/// log line still compare equal.
public struct CCLogEntry: Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let message: String
    public let level: CCLogLevel
    public let source: String?
    public let instanceId: String?

    enum CodingKeys: String, CodingKey {
        case id
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

        if let wireId = try? container.decode(String.self, forKey: .id), !wireId.isEmpty {
            self.id = wireId
        } else {
            self.id = Self.syntheticId(timestamp: self.timestamp, message: self.message)
        }
    }

    public init(id: String? = nil, timestamp: Date, message: String, level: CCLogLevel, source: String? = nil, instanceId: String? = nil) {
        self.id = id ?? Self.syntheticId(timestamp: timestamp, message: message)
        self.timestamp = timestamp
        self.message = message
        self.level = level
        self.source = source
        self.instanceId = instanceId
    }

    /// Fallback identity when the wire didn't carry one. Two CCLogEntry produced from the same
    /// (timestamp, message) tuple will compare equal — enough for dedup in practice.
    private static func syntheticId(timestamp: Date, message: String) -> String {
        return "\(Int(timestamp.timeIntervalSince1970 * 1000))-\(message.hashValue)"
    }
}

// MARK: - SSE Stream Parsing

extension CCLogEntry {
    /// Parse a Clever Cloud v4 logs SSE stream into log entries, sorted newest-first.
    /// Frames are `data:{json}\nevent:APPLICATION_LOG\nid:...\n\n`.
    public static func parseSSEStream(_ sseText: String) -> [CCLogEntry] {
        var entries: [CCLogEntry] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let events = sseText.components(separatedBy: "\n\n")

        for event in events {
            let lines = event.components(separatedBy: "\n")

            var dataLine: String?
            var eventType: String?

            for line in lines {
                if line.hasPrefix("data:") {
                    dataLine = String(line.dropFirst(5))
                } else if line.hasPrefix("event:") {
                    eventType = String(line.dropFirst(6))
                }
            }

            guard let jsonString = dataLine, !jsonString.isEmpty,
                  eventType == "APPLICATION_LOG" || eventType == "RESOURCE_LOG" else {
                continue
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let message = json["message"] as? String else {
                continue
            }

            let timestamp: Date
            if let dateStr = json["date"] as? String {
                timestamp = isoFormatter.date(from: dateStr)
                    ?? ISO8601DateFormatter().date(from: dateStr)
                    ?? Date()
            } else {
                timestamp = Date()
            }

            let level: CCLogLevel
            if let severity = json["severity"] as? String {
                switch severity.lowercased() {
                case "debug": level = .debug
                case "info", "informational": level = .info
                case "warning", "warn": level = .warning
                case "error", "err", "critical", "alert", "emergency": level = .error
                default: level = .info
                }
            } else {
                level = .info
            }

            entries.append(CCLogEntry(
                id: json["id"] as? String,
                timestamp: timestamp,
                message: message,
                level: level,
                source: json["service"] as? String,
                instanceId: json["instanceId"] as? String
            ))
        }

        entries.sort { $0.timestamp > $1.timestamp }
        return entries
    }

    /// Parse a single SSE `data:` payload (one JSON object) into a `CCLogEntry`.
    /// Returns `nil` if the payload isn't a recognizable log line. Used by the live streaming
    /// path (`streamApplicationLogs`, `streamAddonLogs`) where each event is parsed on arrival
    /// instead of accumulating the full stream.
    public static func parseSSEEventData(_ jsonString: String) -> CCLogEntry? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let message = json["message"] as? String else {
            return nil
        }

        let timestamp: Date
        if let dateStr = json["date"] as? String {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = isoFormatter.date(from: dateStr)
                ?? ISO8601DateFormatter().date(from: dateStr)
                ?? Date()
        } else {
            timestamp = Date()
        }

        let level: CCLogLevel
        if let severity = json["severity"] as? String {
            switch severity.lowercased() {
            case "debug": level = .debug
            case "info", "informational": level = .info
            case "warning", "warn": level = .warning
            case "error", "err", "critical", "alert", "emergency": level = .error
            default: level = .info
            }
        } else {
            level = .info
        }

        return CCLogEntry(
            id: json["id"] as? String,
            timestamp: timestamp,
            message: message,
            level: level,
            source: json["service"] as? String,
            instanceId: json["instanceId"] as? String
        )
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
