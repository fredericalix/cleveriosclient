import Foundation

/// Navigation destinations for NavigationStack path-based navigation
enum AppDestination: Hashable {
    case applicationDetail(CCApplication, String?)  // app + orgId
    case addonDetail(CCAddon, String?)              // addon + orgId
}
