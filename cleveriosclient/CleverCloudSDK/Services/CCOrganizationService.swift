import Foundation
import Combine

// MARK: - CCOrganizationService
/// Service for managing Clever Cloud organizations and personal spaces
public class CCOrganizationService {
    
    // MARK: - Properties
    private let httpClient: CCHTTPClient
    
    // MARK: - Initialization
    public init(httpClient: CCHTTPClient) {
        self.httpClient = httpClient
    }
    
    // MARK: - Organization Management
    
    /// Get all organizations accessible to the current user
    /// - Returns: Publisher emitting array of organizations or error
    public func getAllOrganizations() -> AnyPublisher<[CCOrganization], CCError> {
        return httpClient.get("/organisations", apiVersion: .v2)
    }
    
    /// Get organization details by ID 
    /// - Parameter organizationId: Organization ID 
    /// - Returns: Publisher emitting organization or error
    public func getOrganization(id organizationId: String) -> AnyPublisher<CCOrganization, CCError> {
        return httpClient.get("/organisations/\(organizationId)", apiVersion: .v2)
    }
    
    /// Get current user's personal space (profile) by using organizations endpoint
    /// This is a workaround because /v2/self endpoint has OAuth authentication issues
    /// - Returns: Publisher emitting user's personal organization (profile) or error
    public func getUserProfile() -> AnyPublisher<CCOrganization, CCError> {
        // Use /v2/organisations endpoint instead of /v2/self which fails with OAuth 1.0a
        return getAllOrganizations()
            .tryMap { organizations in
                // Find the personal space (user profile) - it's usually the first organization
                // or the one that represents the user's personal space
                if let personalSpace = organizations.first {
                    return personalSpace
                } else {
                    throw CCError.resourceNotFound
                }
            }
            .mapError { error in
                if let ccError = error as? CCError {
                    return ccError
                } else {
                    return CCError.unknown(error)
                }
            }
            .eraseToAnyPublisher()
    }
    
    /// Create a new organization
    /// - Parameter organization: Organization creation data
    /// - Returns: Publisher emitting created organization or error
    public func createOrganization(_ organization: CCOrganizationCreate) -> AnyPublisher<CCOrganization, CCError> {
        return httpClient.post("/organisations", body: organization, apiVersion: .v2)
    }
    
    /// Update organization information
    /// - Parameters:
    ///   - organizationId: Organization ID (nil for current user's personal space)
    ///   - updates: Organization update data
    /// - Returns: Publisher emitting updated organization or error
    public func updateOrganization(id organizationId: String? = nil, 
                                 updates: CCOrganizationUpdate) -> AnyPublisher<CCOrganization, CCError> {
        let endpoint = organizationId != nil ? "/organisations/\(organizationId!)" : "/self"
        return httpClient.put(endpoint, body: updates, apiVersion: .v2)
    }
    
    /// Delete organization
    /// - Parameter organizationId: Organization ID (nil for current user's personal space)
    /// - Returns: Publisher emitting completion or error
    public func deleteOrganization(id organizationId: String? = nil) -> AnyPublisher<Void, CCError> {
        let endpoint = organizationId != nil ? "/organisations/\(organizationId!)" : "/self"
        return httpClient.delete(endpoint, apiVersion: .v2)
            .map { (_: EmptyResponse) in () }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Organization Members Management
    
    /// Get all members of an organization
    /// - Parameter organizationId: Organization ID
    /// - Returns: Publisher emitting array of members or error
    public func getOrganizationMembers(organizationId: String) -> AnyPublisher<[CCOrganizationMember], CCError> {
        return httpClient.get("/organisations/\(organizationId)/members", apiVersion: .v2)
    }
}

// MARK: - Supporting Types

/// Empty body for requests without body
private struct EmptyBody: Codable {}

// MARK: - Supporting Models

/// Organization member model
public struct CCOrganizationMember: Codable, Identifiable {
    public let id: String
    public let name: String
    public let email: String
    public let role: MemberRole
    public let joinedAt: Date
    
    public enum MemberRole: String, Codable {
        case admin = "ADMIN"
        case developer = "DEVELOPER"
        case accountant = "ACCOUNTANT"
        case viewer = "VIEWER"
        
        public var description: String {
            switch self {
            case .admin:
                return "Administrator"
            case .developer:
                return "Developer"
            case .accountant:
                return "Accountant"
            case .viewer:
                return "Viewer"
            }
        }
    }
}

/// Model for adding organization member
public struct CCOrganizationMemberAdd: Codable {
    public let email: String
    public let role: CCOrganizationMember.MemberRole
    
    public init(email: String, role: CCOrganizationMember.MemberRole) {
        self.email = email
        self.role = role
    }
}

/// Model for updating organization member
public struct CCOrganizationMemberUpdate: Codable {
    public let role: CCOrganizationMember.MemberRole
    
    public init(role: CCOrganizationMember.MemberRole) {
        self.role = role
    }
}

/// Payment information model
public struct CCPaymentInfo: Codable {
    public let canPay: Bool
    public let paymentMethods: [PaymentMethod]
    public let defaultMethod: String?
    
    public struct PaymentMethod: Codable, Identifiable {
        public let id: String
        public let type: String
        public let brand: String?
        public let lastFour: String?
        public let expiryMonth: Int?
        public let expiryYear: Int?
    }
}

/// Credits information model
public struct CCCreditsInfo: Codable {
    public let currentCredits: Double
    public let maxCreditsPerMonth: Double?
    public let isRecurrentPaymentEnabled: Bool
}

/// Consumption data model
public struct CCConsumptionData: Codable {
    public let consumptions: [Consumption]
    public let total: Double
    
    public struct Consumption: Codable, Identifiable {
        public let id: String
        public let appId: String?
        public let appName: String?
        public let instanceType: String
        public let instanceCount: Int
        public let duration: TimeInterval
        public let cost: Double
        public let date: Date
    }
} 