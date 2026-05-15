import Foundation

enum ViewState<Value> {
    case idle
    case loading
    case empty
    case loaded(Value)
    case error(String)

    var loadedValue: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}
