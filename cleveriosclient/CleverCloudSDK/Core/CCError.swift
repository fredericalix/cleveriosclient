import Foundation

/// Comprehensive error handling for Clever Cloud SDK
public enum CCError: Error, LocalizedError, Equatable {
    
    // MARK: - Authentication Errors
    
    /// Invalid or missing API token
    case invalidToken
    
    /// Token has expired
    case tokenExpired
    
    /// Authentication failed
    case authenticationFailed
    
    // MARK: - Network Errors
    
    /// Network connection failed
    case networkError(Error)
    
    /// Request timeout
    case timeout
    
    /// Invalid URL
    case invalidURL
    
    // MARK: - API Errors
    
    /// HTTP error with status code
    case httpError(statusCode: Int, message: String?)
    
    /// Invalid API response format
    case invalidResponse
    
    /// JSON parsing failed
    case parsingError(Error)
    
    /// API rate limit exceeded
    case rateLimitExceeded
    
    // MARK: - Resource Errors
    
    /// Requested resource not found
    case resourceNotFound
    
    /// Access denied to resource
    case accessDenied
    
    /// Resource already exists
    case resourceExists
    
    // MARK: - Validation Errors
    
    /// Invalid input parameters
    case invalidParameters(String)
    
    /// Missing required field
    case missingRequiredField(String)
    
    // MARK: - Unknown Error
    
    /// Unexpected error
    case unknown(Error)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid API token. Please check your authentication credentials."
            
        case .tokenExpired:
            return "API token has expired. Please refresh your authentication."
            
        case .authenticationFailed:
            return "Authentication failed. Please verify your credentials."
            
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
            
        case .timeout:
            return "Request timed out. Please check your internet connection and try again."
            
        case .invalidURL:
            return "Invalid URL configuration."
            
        case .httpError(let statusCode, let message):
            let baseMessage = "HTTP error \(statusCode)"
            return message.map { "\(baseMessage): \($0)" } ?? baseMessage
            
        case .invalidResponse:
            return "Invalid response format received from server."
            
        case .parsingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
            
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please wait before making more requests."
            
        case .resourceNotFound:
            return "The requested resource was not found."
            
        case .accessDenied:
            return "Access denied. You don't have permission to access this resource."
            
        case .resourceExists:
            return "Resource already exists."
            
        case .invalidParameters(let details):
            return "Invalid parameters: \(details)"
            
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
            
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Equatable Implementation
    
    public static func == (lhs: CCError, rhs: CCError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidToken, .invalidToken),
             (.tokenExpired, .tokenExpired),
             (.authenticationFailed, .authenticationFailed),
             (.timeout, .timeout),
             (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.rateLimitExceeded, .rateLimitExceeded),
             (.resourceNotFound, .resourceNotFound),
             (.accessDenied, .accessDenied),
             (.resourceExists, .resourceExists):
            return true
            
        case (.httpError(let lhsCode, let lhsMessage), .httpError(let rhsCode, let rhsMessage)):
            return lhsCode == rhsCode && lhsMessage == rhsMessage
            
        case (.invalidParameters(let lhsDetails), .invalidParameters(let rhsDetails)):
            return lhsDetails == rhsDetails
            
        case (.missingRequiredField(let lhsField), .missingRequiredField(let rhsField)):
            return lhsField == rhsField
            
        default:
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    /// Check if error is related to authentication
    public var isAuthenticationError: Bool {
        switch self {
        case .invalidToken, .tokenExpired, .authenticationFailed:
            return true
        case .httpError(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        default:
            return false
        }
    }
    
    /// Check if error is retryable
    public var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .rateLimitExceeded:
            return true
        case .httpError(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
} 