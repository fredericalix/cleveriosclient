import Foundation
import SwiftUI

// MARK: - CCOrganization
/// Organization model representing a Clever Cloud organization or personal space
public struct CCOrganization: Codable, Identifiable, Hashable {
    
    // MARK: - Core Properties
    public let id: String
    public let name: String
    public let description: String?
    
    // MARK: - Billing Information
    public let billingEmail: String?
    public let address: String?
    public let city: String?
    public let zipcode: String?
    public let country: String?
    public let company: String?
    public let VAT: String?
    public let vatState: VATState?
    public let customerFullName: String?
    
    // MARK: - Organization Features
    public let avatar: String?
    public let canPay: Bool
    public let cleverEnterprise: Bool?
    public let emergencyNumber: String?
    public let canSEPA: Bool?
    public let isTrusted: Bool?
    
    // MARK: - Computed Properties
    
    /// Returns true if this is a personal space (user ID)
    public var isPersonalSpace: Bool {
        return id.hasPrefix("user_")
    }
    
    /// Returns true if this is an organization (orga ID)
    public var isOrganization: Bool {
        return id.hasPrefix("orga_")
    }
    
    /// Returns the organization type for display
    public var organizationType: OrganizationType {
        if isPersonalSpace {
            return .personal
        } else if cleverEnterprise ?? false {
            return .enterprise
        } else {
            return .standard
        }
    }
    
    /// Returns a display-friendly address
    public var fullAddress: String {
        var addressComponents: [String] = []
        
        if let address = address, !address.isEmpty {
            addressComponents.append(address)
        }
        if let city = city, !city.isEmpty {
            addressComponents.append(city)
        }
        if let zipcode = zipcode, !zipcode.isEmpty {
            addressComponents.append(zipcode)
        }
        if let country = country, !country.isEmpty {
            addressComponents.append(country)
        }
        
        return addressComponents.joined(separator: ", ")
    }
    
    /// Returns avatar URL or nil if not available
    public var avatarURL: URL? {
        guard let avatar = avatar else { return nil }
        return URL(string: avatar)
    }
}

// MARK: - VATState
public enum VATState: String, Codable, CaseIterable {
    case notApplicable = "NOT_APPLICABLE"
    case notNeeded = "NOT_NEEDED"
    case required = "REQUIRED"
    case provided = "PROVIDED"
    case valid = "VALID"           // ✨ NEW - Found in API responses
    case invalid = "INVALID"       // ✨ NEW - Found in API responses
    
    /// Returns a user-friendly description
    public var description: String {
        switch self {
        case .notApplicable:
            return "VAT not applicable"
        case .notNeeded:
            return "VAT not needed"
        case .required:
            return "VAT required"
        case .provided:
            return "VAT provided"
        case .valid:
            return "VAT valid"         // ✨ NEW
        case .invalid:
            return "VAT invalid"       // ✨ NEW
        }
    }
    
    /// Returns an appropriate color for UI display
    public var color: Color {
        switch self {
        case .notApplicable, .notNeeded:
            return .gray
        case .required, .invalid:      // ✨ UPDATED - invalid shows orange
            return .orange
        case .provided, .valid:        // ✨ UPDATED - valid shows green
            return .green
        }
    }
}

// MARK: - OrganizationType
public enum OrganizationType: String, CaseIterable {
    case personal = "personal"
    case standard = "standard"
    case enterprise = "enterprise"
    
    /// Returns a user-friendly description
    public var description: String {
        switch self {
        case .personal:
            return "Personal Space"
        case .standard:
            return "Organization"
        case .enterprise:
            return "Enterprise"
        }
    }
    
    /// Returns an appropriate icon for UI display
    public var icon: String {
        switch self {
        case .personal:
            return "person.circle"
        case .standard:
            return "building.2"
        case .enterprise:
            return "building.columns"
        }
    }
    
    /// Returns an appropriate color for UI display
    public var color: Color {
        switch self {
        case .personal:
            return .blue
        case .standard:
            return .green
        case .enterprise:
            return .purple
        }
    }
}

// MARK: - CCOrganizationCreate
/// Model for creating a new organization
public struct CCOrganizationCreate: Codable {
    public let name: String
    public let description: String
    public let billingEmail: String?
    public let address: String?
    public let city: String?
    public let zipcode: String?
    public let country: String?
    public let company: String?
    public let VAT: String?
    
    public init(name: String, 
                description: String, 
                billingEmail: String? = nil,
                address: String? = nil,
                city: String? = nil,
                zipcode: String? = nil,
                country: String? = nil,
                company: String? = nil,
                VAT: String? = nil) {
        self.name = name
        self.description = description
        self.billingEmail = billingEmail
        self.address = address
        self.city = city
        self.zipcode = zipcode
        self.country = country
        self.company = company
        self.VAT = VAT
    }
}

// MARK: - CCOrganizationUpdate
/// Model for updating an existing organization
public struct CCOrganizationUpdate: Codable {
    public let name: String?
    public let description: String?
    public let billingEmail: String?
    public let address: String?
    public let city: String?
    public let zipcode: String?
    public let country: String?
    public let company: String?
    public let VAT: String?
    
    public init(name: String? = nil,
                description: String? = nil,
                billingEmail: String? = nil,
                address: String? = nil,
                city: String? = nil,
                zipcode: String? = nil,
                country: String? = nil,
                company: String? = nil,
                VAT: String? = nil) {
        self.name = name
        self.description = description
        self.billingEmail = billingEmail
        self.address = address
        self.city = city
        self.zipcode = zipcode
        self.country = country
        self.company = company
        self.VAT = VAT
    }
} 