import Foundation

// MARK: - Debug-only console logging
//
// Wrapper around `Swift.print` that compiles to a no-op in Release builds so
// the App Store binary contains zero `print` chatter (and zero log strings,
// thanks to `@autoclosure`). Debug builds (Cmd+R from Xcode by default) still
// log everything.
//
// To re-enable logging in a Release build (e.g. to diagnose a TestFlight
// issue), flip `kForceConsoleLogs` below to `true`. The `if` then short-
// circuits to `Swift.print` even in Release. Remember to flip it back to
// `false` before submitting to the App Store.
//
// IMPORTANT: the `@autoclosure` is what makes the log strings disappear from
// the Release binary. The string interpolation at the call site is wrapped in
// a closure that's never invoked when `#if DEBUG` is false, so the compiler
// can dead-code-eliminate the entire literal. A regular `String` parameter
// would still materialize the literal even if the function body is empty.

/// Force console logging in any build configuration. Default `false`.
/// Flip to `true` only for short-lived production diagnostics.
/// ⚠️ TEMPORARILY `true` for debugging — REVERT to `false` before any App Store submission
/// (otherwise log strings ship in the Release binary).
public let kForceConsoleLogs: Bool = true

@inlinable
public func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    Swift.print(message())
    #else
    if kForceConsoleLogs {
        Swift.print(message())
    }
    #endif
}
