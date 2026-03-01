import XCTest

@MainActor
class BinfluencerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTakeScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        // Give the app time to load
        sleep(2)

        // Screenshot 1: The initial setup/main screen
        snapshot("01_MainScreen")

        // Try to tap the settings/borough picker button if visible
        let settingsButton = app.buttons["slider.horizontal.3"]
        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
            sleep(1)
            snapshot("02_BoroughPicker")

            // Try to find and tap the borough menu
            let boroughMenu = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'borough' OR label CONTAINS[c] 'Select'")).firstMatch
            if boroughMenu.waitForExistence(timeout: 2) {
                boroughMenu.tap()
                sleep(1)
                snapshot("03_BoroughSelection")

                // Dismiss the menu by tapping elsewhere
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
                sleep(1)
            }

            // Go back to main screen
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.waitForExistence(timeout: 2) {
                backButton.tap()
                sleep(1)
            }
        }

        // Final screenshot of whatever state we're in
        snapshot("04_AppView")
    }
}
