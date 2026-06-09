import Foundation

// MARK: - CCNamedEntity

/// Marks a model that has a user-facing `name`, so collections of it can be
/// sorted alphabetically with a single shared comparator.
public protocol CCNamedEntity {
    var name: String { get }
}

extension CCApplication: CCNamedEntity {}
extension CCAddon: CCNamedEntity {}
extension CCNetworkGroup: CCNamedEntity {}

extension Sequence where Element: CCNamedEntity {
    /// Alphabetical, Finder-style ordering: case/diacritic-insensitive and
    /// numerically aware (so `app2` sorts before `app10`).
    public func sortedByName() -> [Element] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension Sequence where Element == CCOrganization {
    /// Personal space pinned first, then organizations alphabetically (Finder-style).
    public func sortedForDisplay() -> [CCOrganization] {
        sorted {
            if $0.isPersonalSpace != $1.isPersonalSpace {
                return $0.isPersonalSpace
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
