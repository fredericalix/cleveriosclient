import Foundation

// MARK: - Common Request/Response Models

/// Empty request for endpoints that don't require a body
public struct EmptyRequest: Codable {
    public init() {}
}

/// Empty response for endpoints that don't return data
public struct EmptyResponse: Codable {
    public init() {}
} 