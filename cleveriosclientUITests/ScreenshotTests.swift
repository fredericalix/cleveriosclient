import XCTest

/// Drives App Store screenshot capture via `fastlane snapshot`.
///
/// Each test method here represents one screenshot. The order is enforced
/// by the numeric prefix in the snapshot name (Apple sorts screenshots
/// alphabetically in App Store Connect).
///
/// Setup notes:
///   1. `SnapshotHelper.swift` must be present in this target — generated
///      by `bundle exec fastlane snapshot update`.
///   2. The app must support a UI-test demo mode. See `fastlane/README.md`
///      → "Demo data — making screenshots reproducible".
///   3. Run with `bundle exec fastlane screenshots`. Do not run via Xcode
///      directly — `setupSnapshot` only takes effect when launched by
///      `fastlane snapshot`.
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchEnvironment["UI_TEST_DEMO_MODE"] = "1"
        app.launch()
        return app
    }

    func test01_Login() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        // No demo flag here — we want the unauthenticated state.
        app.launch()
        snapshot("01-Login")
    }

    func test02_Dashboard() throws {
        let app = makeApp()
        // Wait for the dashboard to be ready.
        let firstOrg = app.staticTexts.firstMatch
        XCTAssertTrue(firstOrg.waitForExistence(timeout: 10))
        snapshot("02-Dashboard")
    }

    func test03_ApplicationDetail_Metrics() throws {
        let app = makeApp()
        // Tap the first application in the list.
        let firstApp = app.cells.firstMatch
        XCTAssertTrue(firstApp.waitForExistence(timeout: 10))
        firstApp.tap()
        // Switch to the Metrics tab.
        let metricsTab = app.tabBars.buttons["Metrics"]
        if metricsTab.waitForExistence(timeout: 5) {
            metricsTab.tap()
        }
        // Let charts render.
        sleep(3)
        snapshot("03-ApplicationDetail-Metrics")
    }

    func test04_ApplicationDetail_Logs() throws {
        let app = makeApp()
        let firstApp = app.cells.firstMatch
        XCTAssertTrue(firstApp.waitForExistence(timeout: 10))
        firstApp.tap()
        let logsTab = app.tabBars.buttons["Logs"]
        if logsTab.waitForExistence(timeout: 5) {
            logsTab.tap()
        }
        // Trigger the trampoline button if present.
        let displayLogs = app.buttons["Display Logs"]
        if displayLogs.waitForExistence(timeout: 3) {
            displayLogs.tap()
        }
        sleep(3)
        snapshot("04-ApplicationDetail-Logs")
    }

    func test05_ApplicationDetail_Deployments() throws {
        let app = makeApp()
        let firstApp = app.cells.firstMatch
        XCTAssertTrue(firstApp.waitForExistence(timeout: 10))
        firstApp.tap()
        let deploymentsTab = app.tabBars.buttons["Deployments"]
        if deploymentsTab.waitForExistence(timeout: 5) {
            deploymentsTab.tap()
        }
        sleep(2)
        snapshot("05-ApplicationDetail-Deployments")
    }
}
