import XCTest

/// Plays through Gridlock in the simulator and captures the App Store screenshots, each
/// attached to the test result under its file name (the workflow exports them).
/// Every shot starts from a fresh launch with a played-in save passed as launch arguments
/// (they override what the app reads from UserDefaults; nothing is written to the device).
final class ScreenshotTests: XCTestCase {
    /// Six levels played, stars and best times on most: the save of someone a few days in.
    static let progress = #"{"unlocked":7,"best":{"0":71.2,"1":83.5,"2":96.1,"3":88.4,"4":104.3,"5":118.9},"#
        + #""stars":{"0":[true,true,true],"1":[true,true,false],"2":[true,true,true],"3":[true,false,true],"4":[true,true,false],"5":[true,false,false]},"#
        + #""scores":{"0":2140,"1":2655,"2":3010,"3":2480,"4":3390,"5":1820}}"#
    /// Freeplay on the Downtown map at Gridlock density, at night, with everything on.
    static let freeplay = #"{"map":6,"density":9,"flow":"wild","rush":true,"peds":true,"day":false,"night":true,"emergency":true}"#

    override func setUp() {
        continueAfterFailure = true
    }

    func launch(freeplay: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        // A <string> plist value so the JSON is read as plain text.
        var args = ["-legacyImported", "YES", "-intersection-progress", "<string>\(Self.progress)</string>"]
        if freeplay { args += ["-intersection-freeplay", "<string>\(Self.freeplay)</string>"] }
        app.launchArguments = args
        app.launch()
        // Game Center may ask to sign in on a fresh simulator.
        sleep(3)
        for label in ["Cancel", "Not Now", "Close"] where app.buttons[label].exists { app.buttons[label].tap() }
        return app
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func tap(_ app: XCUIApplication, _ text: String) {
        let match = NSPredicate(format: "label CONTAINS[c] %@", text)
        let button = app.buttons.matching(match).firstMatch
        if button.waitForExistence(timeout: 10) {
            button.tap()
        } else {
            let label = app.staticTexts.matching(match).firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 5), "nothing labelled \(text)")
            label.tap()
        }
    }

    /// Switches every straight-through signal for these directions (not the left turns).
    func toggle(_ app: XCUIApplication, _ directions: [String]) {
        for d in directions {
            let match = NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS[c] 'left')", d)
            for b in app.buttons.matching(match).allElementsBoundByIndex where b.isHittable { b.tap() }
        }
    }

    /// A short, safe stretch of play: north-south through traffic, then east-west.
    func play(_ app: XCUIApplication, seconds: UInt32) {
        sleep(1)
        toggle(app, ["Northbound", "Southbound"])
        sleep(14)
        toggle(app, ["Northbound", "Southbound"])
        sleep(6)
        toggle(app, ["Eastbound", "Westbound"])
        sleep(seconds)
    }

    func test1DowntownRush() {
        let app = launch()
        tap(app, "Levels")
        tap(app, "Downtown Rush")
        tap(app, "Start shift")
        play(app, seconds: 10)
        shot("01-downtown-rush")
    }

    func test2FreeplayAtNight() {
        let app = launch(freeplay: true)
        tap(app, "Freeplay")
        sleep(1)
        shot("06-freeplay-setup")
        tap(app, "Start freeplay")
        play(app, seconds: 12)
        shot("02-freeplay-night")
    }

    func test3Crosswalks() {
        let app = launch()
        tap(app, "Levels")
        tap(app, "Crosswalks")
        tap(app, "Start shift")
        // North-south traffic and the walk signal across 1st Ave, which don't cross.
        sleep(1)
        toggle(app, ["Northbound", "Southbound"])
        tap(app, "Walk across 1st Ave")
        sleep(16)
        shot("03-crosswalks")
    }

    func test4Menu() {
        _ = launch()
        sleep(2)
        shot("04-menu")
    }

    func test5Levels() {
        let app = launch()
        tap(app, "Levels")
        sleep(1)
        shot("05-levels")
    }

    func test6HowToPlay() {
        let app = launch()
        tap(app, "How to play")
        sleep(1)
        shot("07-how-to-play")
    }
}
