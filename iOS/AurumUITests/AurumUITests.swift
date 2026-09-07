import XCTest

final class AurumUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }
    private func openSavedCollection() {
        app.tabBars.buttons["Map"].firstMatch.tap()
        if app.buttons["map-saved"].waitForExistence(timeout: 2) { app.buttons["map-saved"].tap() }
    }
    func testGlobeFlightsTripsAndSaved() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].firstMatch.tap()
        let content = app.buttons["map-section-Flights"]; XCTAssertTrue(content.waitForExistence(timeout: 8)); capture("63 Globe map")
        app.buttons["map-panel-expand"].tap(); app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap()
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 5)); capture("64 Flight route panel")
        app.buttons["map-panel-expand"].tap()
        XCTAssertTrue(app.staticTexts["UI test · Delayed"].waitForExistence(timeout: 5)); capture("65 Flight intelligence")
        let history = app.buttons["Load delay history"]; reveal(history); history.tap()
        XCTAssertTrue(app.staticTexts["UI test sample only"].waitForExistence(timeout: 5)); capture("66 Flight delay history")
        app.buttons["All flights"].tap(); app.buttons["map-section-Trips"].tap()
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-trip-")).firstMatch; XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        XCTAssertTrue(app.buttons["Open trip"].waitForExistence(timeout: 5))
        app.buttons["map-saved"].tap(); XCTAssertTrue(app.navigationBars["Saved places"].waitForExistence(timeout: 5))
    }
    func testNativeMapSheetExpandsAndReturnsToTabBar() {
        let originalBarY = app.tabBars.firstMatch.frame.minY
        app.tabBars.buttons["Map"].firstMatch.tap()
        let expand = app.buttons["map-panel-expand"]; XCTAssertTrue(expand.waitForExistence(timeout: 8))
        let compactY = expand.frame.minY; capture("68 Native map sheet compact")
        XCTAssertGreaterThanOrEqual(app.otherElements["map-panel-surface"].frame.maxY, app.frame.maxY - 1)
        expand.tap()
        let raised = NSPredicate { _, _ in expand.frame.minY < compactY - 200 }
        expectation(for: raised, evaluatedWith: expand); waitForExpectations(timeout: 8)
        capture("69 Native map sheet expanded")
        XCTAssertGreaterThanOrEqual(app.otherElements["map-panel-surface"].frame.maxY, app.frame.maxY - 1)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY, originalBarY, accuracy: 2)
        expand.tap()
        expectation(for: NSPredicate { _, _ in expand.frame.minY > compactY - 50 }, evaluatedWith: expand); waitForExpectations(timeout: 8)
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5)); XCTAssertTrue(bar.buttons["Travel"].isHittable)
        bar.buttons["Travel"].tap()
        XCTAssertTrue(app.buttons["travel-create"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Map"].firstMatch.tap(); XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let handle = origin.withOffset(CGVector(dx: app.frame.midX, dy: expand.frame.minY - 10))
        handle.press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: 180)))
        expectation(for: raised, evaluatedWith: expand); waitForExpectations(timeout: 8)
        capture("70 Native dragged sheet with navigation")
        app.buttons["map-panel-options"].tap(); app.buttons["map-panel-close"].tap()
        XCTAssertTrue(app.buttons["map-show-panel"].waitForExistence(timeout: 5))
    }
    func testMapBodyDragAndStandaloneFlight() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing"]; app.launch()
        let originalBar = app.tabBars.firstMatch.frame
        app.tabBars.buttons["Map"].tap()
        let expand = app.buttons["map-panel-expand"]; XCTAssertTrue(expand.waitForExistence(timeout: 8))
        let compactY = expand.frame.minY
        app.buttons["map-section-Flights"].tap()
        XCTAssertEqual(expand.frame.minY, compactY, accuracy: 2)
        let scroll = app.scrollViews["map-panel-scroll"]
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
        expectation(for: NSPredicate { _, _ in expand.frame.minY < compactY - 200 }, evaluatedWith: expand)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY, originalBar.minY, accuracy: 2)
        XCTAssertGreaterThanOrEqual(app.otherElements["map-panel-surface"].frame.maxY, app.frame.maxY - 1)
        capture("71 Refined map sheet body drag")
        app.buttons["map-add-flight"].tap()
        let airline = app.textFields["flight-airline-query"]; XCTAssertTrue(airline.waitForExistence(timeout: 5))
        airline.tap(); airline.typeText("British")
        app.buttons["flight-airline-BA"].tap()
        let number = app.textFields["flight-number-query"]; number.tap(); number.typeText("178\n")
        app.buttons["flight-find"].tap()
        let result = app.buttons["flight-result-BAW178-ui-test"]; reveal(result); XCTAssertTrue(result.waitForExistence(timeout: 5))
        capture("72 Native flight search results")
        result.tap()
        XCTAssertTrue(app.buttons["flight-record-save"].waitForExistence(timeout: 8))
        capture("73 Standalone flight review")
        app.buttons["flight-record-save"].tap()
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["My flights"].exists)
        app.buttons["map-panel-expand"].tap()
        let footer = app.staticTexts["flight-detail-footer"]
        for _ in 0..<10 {
            app.scrollViews["map-panel-scroll"].swipeUp(velocity: .slow)
            if footer.isHittable { break }
        }
        XCTAssertTrue(footer.isHittable)
        XCTAssertLessThanOrEqual(footer.frame.maxY, app.tabBars.firstMatch.frame.minY)
        capture("75 Flight content clear of navigation")
        app.buttons["All flights"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-standalone-")).firstMatch.exists)
        app.buttons["map-add-flight"].tap()
        app.segmentedControls["flight-search-method"].buttons["Route"].tap()
        let from = app.textFields["flight-route-origin"]; from.tap(); from.typeText("JFK\n")
        let to = app.textFields["flight-route-destination"]; to.tap(); to.typeText("LHR\n")
        app.buttons["flight-find"].tap()
        reveal(result); XCTAssertTrue(result.waitForExistence(timeout: 5)); capture("74 Flight route search")
        app.buttons["Cancel"].firstMatch.tap()
        app.tabBars.buttons["Travel"].tap(); app.tabBars.buttons["Map"].tap()
        XCTAssertEqual(expand.frame.minY, compactY, accuracy: 2)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY, originalBar.minY, accuracy: 2)
    }
    func testGlobeCitySearchAndGuide() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].firstMatch.tap(); XCTAssertTrue(app.buttons["map-panel-expand"].waitForExistence(timeout: 8))
        let city = app.textFields["world-city-search"]; XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap(); city.typeText("Lis")
        let suggestion = app.buttons["world-city-search-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        let guide = app.buttons["map-city-guide"]; reveal(guide); XCTAssertTrue(guide.waitForExistence(timeout: 5)); guide.tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 5)); capture("67 Map to city guide")
    }
    func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // Let native transitions settle before visual capture.
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func reveal(_ element: XCUIElement) {
        for _ in 0..<9 {
            if !element.exists { app.swipeUp(velocity: .slow); continue }
            let frame = element.frame
            if element.exists && frame.minY > app.frame.minY + 150 && frame.maxY < app.frame.maxY - 180 && element.isHittable { return }
            if element.exists && frame.minY < app.frame.minY + 150 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
    }
    func testDiscoverSaveAndPlanStay() {
        let hero = app.buttons["hero-hotel"]
        XCTAssertTrue(hero.waitForExistence(timeout: 10))
        capture("01 Discover — Liquid Glass")
        hero.tap()
        XCTAssertTrue(app.buttons["plan-stay"].waitForExistence(timeout: 5))
        capture("02 Hotel detail")
        app.buttons["detail-save"].tap()
        app.buttons["plan-stay"].tap()
        XCTAssertTrue(app.buttons["add-stay"].waitForExistence(timeout: 5))
        app.buttons["add-stay"].tap()
        XCTAssertTrue(app.buttons["add-stay"].label.contains("Added"))
        capture("03 Stay planning")
        app.buttons["Done"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSavedCollection()
        XCTAssertTrue(app.staticTexts["Mandarin Oriental, Bangkok"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Travel"].tap()
        if app.buttons["Earlier saved plans · 1"].exists { app.buttons["Earlier saved plans · 1"].tap() }
        XCTAssertTrue(app.staticTexts["Mandarin Oriental, Bangkok"].waitForExistence(timeout: 5))
        capture("04 Itinerary")
    }
    func testSearchCatalogAndEmptyState() {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Savoy")
        XCTAssertTrue(app.staticTexts["The Savoy"].waitForExistence(timeout: 5))
        capture("05 Native hotel search")
        field.tap(); field.press(forDuration: 1.0)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap(); field.typeText("__missing__") }
        else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "__missing__") }
        XCTAssertTrue(app.staticTexts["A little further afield?"].waitForExistence(timeout: 5))
    }
    func testDiningPlan() {
        app.buttons["hero-hotel"].tap()
        let venue = app.buttons["venue-0"]
        for _ in 0..<4 { if venue.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(venue.isHittable); venue.tap()
        XCTAssertTrue(app.buttons["restaurant-plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["restaurant-title"].exists)
        capture("10 Restaurant detail")
        app.buttons["restaurant-save"].tap()
        XCTAssertEqual(app.buttons["restaurant-save"].label, "Unsave restaurant")
        app.buttons["restaurant-plan"].tap()
        let add = app.buttons["add-dining"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        for _ in 0..<3 { if add.isHittable { break }; app.swipeUp() }
        add.tap()
        XCTAssertTrue(add.label.contains("Added"))
        capture("06 Dining planner")
    }
    func testRestaurantVisitAndSavedNavigation() {
        app.buttons["hero-hotel"].tap()
        let venue = app.buttons["venue-0"]
        for _ in 0..<5 { if venue.isHittable { break }; app.swipeUp() }
        venue.tap()
        XCTAssertTrue(app.buttons["restaurant-save"].waitForExistence(timeout: 5))
        app.buttons["restaurant-save"].tap()
        let journal = app.buttons["restaurant-journal"]
        for _ in 0..<5 { if journal.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(journal.isHittable)
        capture("11 Restaurant visit and location")
        journal.tap()
        app.buttons["visit-rating-5"].tap()
        let note = app.textViews["visit-note"]
        note.tap(); note.typeText("Ask for a quiet table.")
        app.buttons["save-visit"].tap()
        XCTAssertTrue(app.staticTexts["Ask for a quiet table."].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--preserve-state"]
        app.launch()
        openSavedCollection()
        XCTAssertTrue(app.staticTexts["The Bamboo Bar"].waitForExistence(timeout: 5))
        app.staticTexts["The Bamboo Bar"].tap()
        XCTAssertTrue(app.buttons["restaurant-plan"].waitForExistence(timeout: 5))
        for _ in 0..<5 { if app.buttons["restaurant-journal"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Ask for a quiet table."].exists)
        app.buttons["restaurant-journal"].tap()
        XCTAssertEqual(app.textViews["visit-note"].value as? String, "Ask for a quiet table.")
        app.buttons["Cancel"].tap()
    }
    private func openCityExplorer(fixtures: Bool, createTrip: Bool = false) {
        app.terminate(); app.launchArguments = ["--ui-testing"] + (fixtures ? ["--location-testing", "--city-testing"] : []); app.launch()
        if createTrip {
            app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
            let field = app.textFields["trip-destination"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Lis")
            XCTAssertTrue(app.buttons["trip-destination-suggestion-0"].waitForExistence(timeout: 5)); app.buttons["trip-destination-suggestion-0"].tap(); app.buttons["journey-save"].tap()
            XCTAssertTrue(app.staticTexts["Trip to Lisbon, Portugal"].waitForExistence(timeout: 5)); app.tabBars.buttons["Discover"].tap()
        }
        let explore = app.buttons["explore-cities"]; XCTAssertTrue(explore.waitForExistence(timeout: 5)); explore.tap()
        XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
    }
    private func chooseCityInterest(_ interest: String) {
        let chooser = app.buttons["city-all-interests"]; reveal(chooser); chooser.tap()
        let item = app.buttons["city-choose-" + interest]; reveal(item); item.tap()
    }
    private func firstCityResult() -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-place-")).firstMatch }
    private func addDiscoveryToFirstTrip(save: String, journal: Bool = false) {
        app.buttons["explore-add-trip"].tap()
        XCTAssertTrue(app.segmentedControls["explore-trip-mode"].waitForExistence(timeout: 5))
        if journal { app.segmentedControls["explore-trip-mode"].buttons.element(boundBy: 1).tap() }
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "explore-trip-")).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 8)); reveal(trip); trip.tap()
        XCTAssertTrue(app.buttons[save].waitForExistence(timeout: 8)); app.buttons[save].tap()
        XCTAssertTrue(app.buttons["explore-add-trip"].waitForExistence(timeout: 8))
    }
    func testWorldwideCityDiscoverySavePlanHotelAndJournal() {
        openCityExplorer(fixtures: true, createTrip: true)
        let city = app.textFields["explore-city-query"]; city.tap(); city.typeText("Lis")
        XCTAssertTrue(app.buttons["explore-city-query-suggestion-0"].waitForExistence(timeout: 5)); app.buttons["explore-city-query-suggestion-0"].tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 5)); app.buttons["city-save"].tap()
        XCTAssertFalse(app.otherElements["city-dining-collection"].exists)
        chooseCityInterest("museums")
        let result = firstCityResult(); reveal(result); XCTAssertTrue(result.waitForExistence(timeout: 8)); result.tap()
        XCTAssertTrue(app.staticTexts["explore-place-title"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["explore-place-title"].label, "Lisbon Museum 1")
        app.buttons["explore-place-save"].tap(); capture("58 City discovery detail")
        addDiscoveryToFirstTrip(save: "event-save")
        addDiscoveryToFirstTrip(save: "rated-save", journal: true)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 { if app.buttons["city-all-interests"].isHittable { break }; app.swipeDown(velocity: .slow) }
        chooseCityInterest("hotels")
        let hotel = firstCityResult(); reveal(hotel); hotel.tap()
        XCTAssertTrue(app.staticTexts["explore-place-title"].waitForExistence(timeout: 5)); addDiscoveryToFirstTrip(save: "hotel-record-save")
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state", "--location-testing", "--city-testing"]; app.launch()
        openSavedCollection(); app.buttons["saved-city-collection"].tap()
        XCTAssertTrue(app.staticTexts["Lisbon Museum 1"].waitForExistence(timeout: 5)); capture("59 Saved city discoveries")
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Lisbon, Portugal"].tap()
        let museum = app.staticTexts["Lisbon Museum 1"]; reveal(museum); XCTAssertTrue(museum.exists)
        for _ in 0..<8 { if app.buttons["Map"].isHittable { break }; app.swipeDown(velocity: .slow) }
        app.buttons["Map"].tap(); XCTAssertTrue(app.staticTexts["trip-map-count"].waitForExistence(timeout: 5))
    }
    func testCityCollectionProminentAndSearchable() {
        openCityExplorer(fixtures: true)
        let paris = app.buttons["explore-city-Paris"]
        for _ in 0..<8 {
            if paris.exists && paris.frame.midY > 160 && paris.frame.midY < app.frame.height - 180 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        }
        paris.tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 5))
        let collection = app.buttons["city-collection-all"]; reveal(collection); XCTAssertTrue(collection.exists)
        capture("57 Paris hotel dining collection")
        collection.tap(); XCTAssertTrue(app.navigationBars["The dining collection"].waitForExistence(timeout: 5))
        let search = app.textFields["city-collection-query"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Peninsula\n")
        let result = firstCityResult(); reveal(result); XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.staticTexts["explore-place-title"].waitForExistence(timeout: 5)); app.buttons["explore-place-save"].tap()
        XCTAssertEqual(app.buttons["explore-place-save"].label, "Unsave place")
    }
    func testLiveCityOutsideCatalog() {
        openCityExplorer(fixtures: false)
        let field = app.textFields["explore-city-query"]; field.tap(); field.typeText("Lisbon Portugal")
        let city = app.buttons["explore-city-query-suggestion-0"]; XCTAssertTrue(city.waitForExistence(timeout: 20)); city.tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 20)); capture("56 Worldwide city guide")
        chooseCityInterest("museums")
        let place = firstCityResult(); for _ in 0..<5 { if place.exists { break }; app.swipeUp(velocity: .slow); RunLoop.current.run(until: Date().addingTimeInterval(2)) }
        XCTAssertTrue(place.waitForExistence(timeout: 20)); reveal(place); capture("60 Live city museums"); place.tap()
        XCTAssertTrue(app.buttons["explore-add-trip"].waitForExistence(timeout: 5)); capture("61 Live place details")
    }
    func testCityMapSearchAndSavedFilter() {
        openCityExplorer(fixtures: true)
        let field = app.textFields["explore-city-query"]; field.tap(); field.typeText("Lis")
        let city = app.buttons["explore-city-query-suggestion-0"]; XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 5))
        chooseCityInterest("museums")
        let place = firstCityResult(); reveal(place); XCTAssertTrue(place.waitForExistence(timeout: 5)); place.tap()
        XCTAssertTrue(app.buttons["explore-place-save"].waitForExistence(timeout: 5)); app.buttons["explore-place-save"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 { if app.buttons["city-filters"].isHittable { break }; app.swipeDown(velocity: .slow) }
        app.buttons["city-filters"].tap()
        let saved = app.switches["Only saved places"]; XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap(); app.buttons["Done"].tap()
        let views = app.segmentedControls["city-results-view"]; reveal(views); views.buttons.element(boundBy: 1).tap()
        let map = app.otherElements["city-results-map"]; XCTAssertTrue(map.waitForExistence(timeout: 8)); app.swipeUp(velocity: .slow); capture("62 City map and saved filter")
        XCTAssertTrue(app.staticTexts["Lisbon Museum 1"].exists)
        for _ in 0..<8 { if app.textFields["city-place-query"].isHittable { break }; app.swipeDown(velocity: .slow) }
        let query = app.textFields["city-place-query"]; query.tap(); query.typeText("noresults\n")
        let empty = app.staticTexts["No saved places match this search. Try another interest or reset your filters."]; reveal(empty); XCTAssertTrue(empty.waitForExistence(timeout: 5))
    }
    private func createAddFlowTrip(fixtures: Bool = true) {
        app.terminate(); app.launchArguments = ["--ui-testing"] + (fixtures ? ["--location-testing"] : []); app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap(); destination.typeText("Paris\n")
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.staticTexts["Trip to Paris"].waitForExistence(timeout: 5)); app.staticTexts["Trip to Paris"].tap()
    }
    func testExistingTripWithoutRouteCanAddMeeting() {
        createAddFlowTrip()
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        let stop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-stop-")).firstMatch
        reveal(stop); stop.swipeLeft(); app.buttons["Delete"].firstMatch.tap()
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5)); app.buttons["journey-add"].tap()
        let meeting = app.buttons["add-plan-meeting"]; reveal(meeting); meeting.tap()
        let title = app.textFields["event-title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("A plan for my existing trip\n")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.staticTexts["A plan for my existing trip"].waitForExistence(timeout: 8))
        capture("53 Existing trip now accepts plans")
    }
    func testUndatedTripResumesSelectedEventAfterDestinationStep() {
        createAddFlowTrip()
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        let stop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-stop-")).firstMatch
        reveal(stop); stop.swipeLeft(); app.buttons["Delete"].firstMatch.tap()
        let dates = app.switches["Add travel dates"]; reveal(dates); dates.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5)); app.buttons["journey-add"].tap()
        let meeting = app.buttons["add-plan-meeting"]; reveal(meeting); meeting.tap()
        XCTAssertTrue(app.buttons["add-trip-continue"].waitForExistence(timeout: 5)); app.buttons["add-trip-continue"].tap()
        let title = app.textFields["event-title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("A newly dated meeting\n")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.staticTexts["A newly dated meeting"].waitForExistence(timeout: 8))
    }
    func testEveryAddOptionOpensItsEditor() {
        createAddFlowTrip()
        app.buttons["journey-add"].tap()
        XCTAssertTrue(app.buttons["add-plan-hotel"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["add-plan-hotel"].frame.minY, app.buttons["add-plan-place"].frame.minY)
        capture("48 Stays first add menu")
        let options = [("hotel", "hotel-record-save"), ("flight", "flight-record-save"), ("place", "event-save"), ("attraction", "event-save"), ("tour", "event-save"), ("concert", "event-save"), ("performance", "event-save"), ("sport", "event-save"), ("shopping", "event-save"), ("wellness", "event-save"), ("meeting", "event-save"), ("appointment", "event-save"), ("conference", "event-save"), ("celebration", "event-save"), ("transfer", "event-save"), ("train", "event-save"), ("ferry", "event-save"), ("freeTime", "event-save"), ("custom", "event-save")]
        for (option, save) in options {
            let choice = app.buttons["add-plan-" + option]; reveal(choice); choice.tap()
            XCTAssertTrue(app.buttons[save].waitForExistence(timeout: 5), "No editor for " + option)
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.buttons["add-plan-" + option].waitForExistence(timeout: 5))
        }
        let ideas = app.buttons["AI activity ideas"]; reveal(ideas); ideas.tap()
        XCTAssertTrue(app.navigationBars["Ideas for your days"].waitForExistence(timeout: 5))
    }
    func testAddBookingsPlacesAndVenuePersistsOnMap() {
        createAddFlowTrip()
        for choice in ["hotel", "place", "attraction"] {
            app.buttons["journey-add"].tap(); app.buttons["add-plan-" + choice].tap()
            let field = app.textFields["place-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Par")
            let suggestion = app.buttons["place-name-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
            XCTAssertTrue(app.staticTexts["place-map-ready"].waitForExistence(timeout: 5))
            if choice == "hotel" { capture("49 Hotel booking with mapped place") }
            app.buttons[choice == "hotel" ? "hotel-record-save" : "event-save"].tap()
            XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        }
        app.buttons["journey-add"].tap(); let meeting = app.buttons["add-plan-meeting"]; reveal(meeting); meeting.tap()
        let title = app.textFields["event-title"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Team lunch\n")
        let venue = app.textFields["event-location"]; venue.tap(); venue.typeText("Par")
        XCTAssertTrue(app.buttons["event-location-suggestion-0"].waitForExistence(timeout: 5)); app.buttons["event-location-suggestion-0"].tap()
        app.buttons["event-save"].tap(); XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        app.buttons["journey-add"].tap(); app.buttons["add-plan-flight"].tap()
        let airline = app.textFields["booking-airline"]; XCTAssertTrue(airline.waitForExistence(timeout: 5)); airline.tap(); airline.typeText("Air France\n")
        for identifier in ["booking-departure", "booking-arrival"] {
            let airport = app.textFields[identifier]; reveal(airport); airport.tap(); airport.typeText("Par")
            let suggestion = app.buttons[identifier + "-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        }
        app.buttons["flight-record-save"].tap(); XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Paris"].tap()
        let map = app.buttons["Map"]; reveal(map); map.tap()
        XCTAssertTrue(app.staticTexts["trip-map-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trip-map-count"].label, "4 places on your map")
        capture("50 Saved trip map with bookings and meeting")
    }
    func testPlaceSearchPopupStaysOpenAndReturnsSelection() {
        createAddFlowTrip()
        for choice in ["place", "hotel", "attraction", "journal"] {
            if choice == "journal" { app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap() }
            else { app.buttons["journey-add"].tap(); app.buttons["add-plan-" + choice].tap() }
            let opener = app.buttons[choice == "hotel" ? "Search hotels" : "Find a restaurant or place"]
            XCTAssertTrue(opener.waitForExistence(timeout: 5))
            if choice == "place" {
                let extraDay = app.buttons["event-day-1"]; reveal(extraDay); extraDay.tap()
                for _ in 0..<8 { if opener.isHittable { break }; app.swipeDown(velocity: .slow) }
            }
            opener.tap()
            let query = app.textFields["live-place-query"]
            XCTAssertTrue(query.waitForExistence(timeout: 5))
            // Catch a transient presentation that disappears immediately after opening.
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            XCTAssertTrue(query.exists, "Search dismissed itself for " + choice)
            query.tap(); query.typeText("Par")
            let suggestion = app.buttons["live-place-query-suggestion-0"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            if choice == "place" { capture("55 Restaurant search popup stays open") }
            suggestion.tap()
            let selectedName = app.textFields["place-name"]
            XCTAssertTrue(selectedName.waitForExistence(timeout: 5))
            XCTAssertEqual(selectedName.value as? String, "Paris Test Hotel")
            XCTAssertTrue(app.staticTexts["place-map-ready"].exists)
            // Reopen and cancel: neither the selection nor the editor should be lost.
            opener.tap(); XCTAssertTrue(query.waitForExistence(timeout: 5))
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(selectedName.waitForExistence(timeout: 5))
            XCTAssertEqual(selectedName.value as? String, "Paris Test Hotel")
            if choice == "place" {
                let extraDay = app.buttons["event-day-1"]; reveal(extraDay)
                XCTAssertEqual(extraDay.value as? String, "Selected", "Search reset the draft schedule")
            }
            let save = choice == "hotel" ? "hotel-record-save" : choice == "journal" ? "rated-save" : "event-save"
            app.buttons[save].tap()
            XCTAssertTrue(app.buttons[choice == "journal" ? "trip-add-place" : "journey-add"].waitForExistence(timeout: 8))
        }
    }
    func testFlightSearchPopupsStayOpen() {
        createAddFlowTrip()
        app.buttons["journey-add"].tap(); app.buttons["add-plan-flight"].tap()
        XCTAssertTrue(app.buttons["Search flights"].waitForExistence(timeout: 5)); app.buttons["Search flights"].tap()
        XCTAssertTrue(app.textFields["lookup-origin"].waitForExistence(timeout: 5))
        for (opener, field) in [("Find departure city or airport", "lookup-origin"), ("Find arrival city or airport", "lookup-destination")] {
            app.buttons[opener].tap()
            let query = app.textFields["live-place-query"]; XCTAssertTrue(query.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(2)); XCTAssertTrue(query.exists)
            query.tap(); query.typeText("Par")
            let suggestion = app.buttons["live-place-query-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
            XCTAssertTrue(app.textFields[field].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textFields[field].value as? String, "Paris Charles de Gaulle Airport")
        }
    }
    func testLiveGooglePlaceAutocompleteResolvesMapLocation() {
        createAddFlowTrip(fixtures: false)
        app.buttons["journey-add"].tap(); capture("48 Stays first add menu"); app.buttons["add-plan-hotel"].tap()
        let field = app.textFields["place-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("The Savoy London")
        XCTAssertTrue(app.staticTexts["Google Maps"].waitForExistence(timeout: 15))
        capture("51 Live Google Places suggestions")
        app.buttons["place-name-suggestion-0"].tap()
        XCTAssertTrue(app.staticTexts["place-map-ready"].waitForExistence(timeout: 20))
        capture("52 Resolved Savoy hotel")
        app.buttons["hotel-record-save"].tap(); XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        let map = app.buttons["Map"]; reveal(map); map.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        capture("54 Live Savoy on trip map")
    }
    func testMeetingAndCustomItineraryEvents() {
        app.tabBars.buttons["Travel"].tap()
        app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap()
        app.buttons["journey-add"].tap()
        XCTAssertTrue(app.buttons["add-plan-place"].waitForExistence(timeout: 5))
        capture("38 Itinerary item chooser")
        reveal(app.buttons["add-plan-meeting"]); capture("39 Meetings and occasions")
        app.buttons["add-plan-meeting"].tap()
        let name = app.textFields["event-title"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Design review\n")
        let duration = app.switches["event-duration-toggle"]
        reveal(duration); duration.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap(); XCTAssertEqual(duration.value as? String, "1")
        capture("40 Meeting schedule")
        let day = app.buttons["event-day-1"]; reveal(day); day.tap()
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.buttons["agenda-event-0"].waitForExistence(timeout: 5))
        capture("41 Meeting in agenda")
        app.buttons["agenda-event-0"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5)); XCTAssertEqual(name.value as? String, "Design review")
        let allDay = app.switches["event-all-day"]; reveal(allDay); allDay.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap(); XCTAssertEqual(allDay.value as? String, "1")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.staticTexts["All day"].waitForExistence(timeout: 5))
        app.buttons["journey-add"].tap()
        let custom = app.buttons["add-plan-custom"]; reveal(custom); custom.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Private preview\n")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.staticTexts["Private preview"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.staticTexts["Design review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private preview"].exists)
        capture("42 Saved meeting and custom event")
    }
    func testTravelItineraryAndRepeatedEvents() {
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.buttons["travel-create"].waitForExistence(timeout: 5))
        capture("12 Travel dashboard")
        app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5))
        app.buttons["journey-add"].tap()
        app.buttons["add-plan-place"].tap()
        let name = app.textFields["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("A wonderful dinner\n")
        let day = app.buttons["event-day-1"]
        reveal(day)
        capture("17 Before day selection")
        XCTAssertTrue(day.isHittable); day.tap()
        capture("17 Repeated event editor")
        XCTAssertEqual(day.value as? String, "Selected")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5))
        capture("14 Itinerary agenda")
        XCTAssertTrue(app.buttons["agenda-event-0"].exists)
        let secondEvent = app.buttons["agenda-event-1"]
        for _ in 0..<5 { if secondEvent.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(secondEvent.exists)
        for _ in 0..<6 { if app.buttons["Calendar"].isHittable { break }; app.swipeDown() }
        app.buttons["Calendar"].tap()
        capture("15 Itinerary calendar")
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.staticTexts["Trip to Paris"].waitForExistence(timeout: 5))
    }
    func testUnifiedTripPlanningAndJournalStayTogether() {
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.buttons["Plan"].waitForExistence(timeout: 5))
        app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap()
        app.textFields["place-name"].tap(); app.textFields["place-name"].typeText("A favourite cafe\n")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.staticTexts["A favourite cafe"].waitForExistence(timeout: 5))
        app.buttons["Plan"].tap()
        app.buttons["journey-add"].tap(); app.buttons["add-plan-place"].tap()
        let dinner = app.textFields["place-name"]
        XCTAssertTrue(dinner.waitForExistence(timeout: 5)); dinner.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { dinner.tap() }
        dinner.typeText("Dinner by the river\n")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.staticTexts["Dinner by the river"].waitForExistence(timeout: 5))
        capture("43 Unified trip plan")
        app.buttons["Journal"].tap()
        app.buttons["trip-journal-planned"].tap()
        reveal(app.staticTexts["Dinner by the river"])
        XCTAssertTrue(app.staticTexts["Dinner by the river"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A favourite cafe"].exists)
        reveal(app.buttons["trip-journal-planned"]); app.buttons["trip-journal-planned"].tap()
        reveal(app.staticTexts["Dinner by the river"])
        XCTAssertEqual(app.staticTexts.matching(identifier: "Dinner by the river").count, 1)
        capture("44 Journal and planned places")
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertFalse(app.buttons["Trip journals"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Trip to Paris").count, 1)
        capture("45 Unified trips dashboard")
        app.staticTexts["Trip to Paris"].tap()
        XCTAssertTrue(app.staticTexts["Dinner by the river"].waitForExistence(timeout: 5))
        app.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["A favourite cafe"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Dinner by the river"])
        XCTAssertTrue(app.staticTexts["Dinner by the river"].exists)
    }
    func testTripJournalLogging() {
        app.tabBars.buttons["Travel"].tap()
        app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap()
        app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap()
        app.textFields["place-name"].tap(); app.textFields["place-name"].typeText("My favorite table\n")
        let rating = app.steppers["Overall-stepper"]
        reveal(rating)
        XCTAssertTrue(rating.isHittable)
        let increase = rating.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        increase.tap(); increase.tap(); increase.tap()
        capture("18 Personal rating editor")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.staticTexts["My favorite table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0.3"].exists)
        capture("16 Trip journal")
    }
    @MainActor func testTravelBackendAccountConnection() async throws {
        var probe = URLRequest(url: URL(string: "http://localhost:8788/v1/status")!); probe.timeoutInterval = 2
        do { let (_, response) = try await URLSession.shared.data(for: probe); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) } }
        catch { throw XCTSkip("Start the isolated backend on localhost:8788 to run this integration test.") }
        app.terminate()
        app.launchArguments = ["--ui-testing", "--travel-test-server", "http://localhost:8788"]
        app.launch()
        app.tabBars.buttons["Travel"].tap()
        app.buttons["Travel account"].tap()
        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 8))
        capture("20 Account before signup")
        app.buttons["Create account"].tap()
        capture("21 Account signup form")
        let handle = app.textFields["account-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5)); handle.tap(); handle.typeText("ui_" + UUID().uuidString.prefix(8).lowercased())
        let displayName = app.textFields["Display name"]
        displayName.tap(); displayName.typeText("Native Test Traveler")
        let password = app.secureTextFields["account-password"]
        password.tap(); password.typeText("Strong-simulator-password-123")
        app.buttons["Create my account"].tap()
        let connected = app.buttons["Sign out"].waitForExistence(timeout: 10)
        capture("22 Account registration result")
        XCTAssertTrue(connected)
        capture("19 Backend account connected")
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.secureTextFields["account-password"].waitForExistence(timeout: 8))
    }
    @MainActor func testSupabaseNativeAccount() async throws {
        let root = "https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api"
        let handleValue = "native_" + UUID().uuidString.prefix(8).lowercased()
        let passwordValue = UUID().uuidString + "-cloud"
        var registration = URLRequest(url: URL(string: root + "/v1/auth/register")!)
        registration.httpMethod = "POST"; registration.setValue("application/json", forHTTPHeaderField: "Content-Type")
        registration.httpBody = try JSONSerialization.data(withJSONObject: ["handle": handleValue, "name": "Native Cloud Test", "password": passwordValue])
        let (data, response) = try await URLSession.shared.data(for: registration)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let account = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cleanupToken = account["token"] as! String
        addTeardownBlock {
            var removal = URLRequest(url: URL(string: root + "/v1/account")!); removal.httpMethod = "DELETE"
            removal.setValue("Bearer " + cleanupToken, forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: removal)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        }
        app.terminate(); app.launchArguments = ["--ui-testing", "--travel-test-server", root + "?native-test=" + handleValue]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["Travel account"].tap()
        let handle = app.textFields["account-handle"]; XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap(); handle.typeText(handleValue)
        let password = app.secureTextFields["account-password"]; password.tap(); password.typeText(passwordValue)
        let login = app.buttons["account-submit"]
        XCTAssertTrue(login.isEnabled); login.tap()
        // iOS may present its password-saving prompt over the account sheet.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 10) { notNow.tap() }
        else if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
        if !app.buttons["Sign out"].waitForExistence(timeout: 3), app.buttons["Travel account"].exists { app.buttons["Travel account"].tap() }
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 25), app.staticTexts["account-message"].exists ? app.staticTexts["account-message"].label : "No account error shown")
        XCTAssertTrue(app.staticTexts["Native Cloud Test"].exists)
        capture("71 Supabase native account")
        app.buttons["Refresh cloud journeys"].tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
    }
    func testFlightValidation() {
        app.buttons["category-Flights"].tap()
        let origin = app.textFields["flight-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        origin.tap(); origin.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Paris")
        app.swipeUp(); app.swipeUp()
        let find = app.buttons["find-flights"]
        XCTAssertTrue(find.waitForExistence(timeout: 5)); find.tap()
        XCTAssertTrue(app.staticTexts["Choose different departure and arrival cities."].waitForExistence(timeout: 5))
        capture("07 Flight validation")
    }
    func testConciergeChatAndHotelNavigation() {
        app.tabBars.buttons["Concierge"].tap()
        let prompt = app.buttons["concierge-prompt-bed.double"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        capture("09 Concierge welcome")
        prompt.tap()
        XCTAssertTrue(app.staticTexts["concierge-reply"].waitForExistence(timeout: 5))
        capture("10 Concierge recommendations")
        let hotel = app.buttons["concierge-hotel-par-peninsula"]
        XCTAssertTrue(hotel.waitForExistence(timeout: 5))
        if !hotel.isHittable { app.swipeDown() }
        hotel.tap()
        XCTAssertTrue(app.buttons["plan-stay"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let input = app.textFields["concierge-input"].exists ? app.textFields["concierge-input"] : app.textViews["concierge-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("What about Tokyo?")
        app.buttons["concierge-send"].tap()
        let reply = app.staticTexts.matching(identifier: "concierge-reply")
        let hasTwo = NSPredicate(format: "count == 2")
        expectation(for: hasTwo, evaluatedWith: reply)
        waitForExpectations(timeout: 6)
        XCTAssertTrue(reply.element(boundBy: 1).label.contains("Tokyo"))
        openSavedCollection()
        app.tabBars.buttons["Concierge"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "concierge-reply").count, 2)
        app.buttons["New conversation"].tap()
        app.buttons["Clear this conversation"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
    }

    func beginOnboarding(extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--onboarding-testing"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: 8))
    }
    @MainActor func testOnboardingCloudRegistrationAndSignIn() throws {
        let root = "https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api"
        let username = "onboard_" + UUID().uuidString.prefix(8).lowercased()
        let passwordValue = UUID().uuidString + "-cloud"
        // Only this test's account is ever touched, including cleanup after a failed assertion.
        addTeardownBlock {
            var login = URLRequest(url: URL(string: root + "/v1/auth/login")!)
            login.httpMethod = "POST"; login.setValue("application/json", forHTTPHeaderField: "Content-Type")
            login.httpBody = try JSONSerialization.data(withJSONObject: ["handle": username, "password": passwordValue])
            let (data, response) = try await URLSession.shared.data(for: login)
            if (response as? HTTPURLResponse)?.statusCode == 401 { return }
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let token = try XCTUnwrap(result?["token"] as? String)
            var removal = URLRequest(url: URL(string: root + "/v1/account")!); removal.httpMethod = "DELETE"
            removal.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (_, deleted) = try await URLSession.shared.data(for: removal)
            XCTAssertEqual((deleted as? HTTPURLResponse)?.statusCode, 200)
        }
        let serverArgs = ["--travel-test-server", root + "?onboarding-test=" + username]
        beginOnboarding(extra: serverArgs)
        app.buttons["onboarding-start"].tap(); app.buttons["onboarding-skip"].tap()
        let name = app.textFields["onboarding-account-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8)); capture("74 Create your account"); name.tap(); name.typeText("Onboarding Traveler")
        app.keyboards.buttons["next"].tap()
        let handle = app.textFields["onboarding-account-handle"]
        handle.typeText(username)
        app.keyboards.buttons["next"].tap()
        let password = app.secureTextFields["onboarding-account-password"]
        dismissStrongPasswordIfNeeded()
        for character in passwordValue { password.typeText(String(character)) }
        app.keyboards.buttons["next"].tap()
        let confirmation = app.secureTextFields["onboarding-account-confirmation"]
        dismissStrongPasswordIfNeeded()
        confirmation.typeText("does-not-match")
        app.buttons["onboarding-account-submit"].tap()
        XCTAssertTrue(app.staticTexts["onboarding-account-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["onboarding-account-error"].label.contains("don’t match"), app.staticTexts["onboarding-account-error"].label)
        confirmation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14))
        for character in passwordValue { confirmation.typeText(String(character)) }
        app.buttons["onboarding-account-submit"].tap()
        dismissSavePasswordIfNeeded()
        XCTAssertTrue(app.buttons["membership-skip"].waitForExistence(timeout: 30), "Registration must reach the membership preview")
        capture("72 Onboarding account created")
        app.buttons["membership-skip"].tap()
        app.tabBars.buttons["Travel"].tap(); app.buttons["Travel account"].tap()
        XCTAssertTrue(app.staticTexts["Onboarding Traveler"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--onboarding-testing", "--preserve-state"] + serverArgs; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["Travel account"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 15), "Account must survive relaunch in Keychain")
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["account-handle"].waitForExistence(timeout: 10))
        beginOnboarding(extra: serverArgs)
        app.buttons["onboarding-sign-in"].tap()
        XCTAssertFalse(app.textFields["onboarding-account-name"].exists)
        handle.tap(); handle.typeText(username)
        app.keyboards.buttons["next"].tap()
        password.typeText("wrong-password-value")
        app.buttons["onboarding-account-submit"].tap()
        XCTAssertTrue(app.staticTexts["onboarding-account-error"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["membership-skip"].exists)
        password.tap(); password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + passwordValue)
        app.buttons["onboarding-account-submit"].tap()
        dismissSavePasswordIfNeeded()
        XCTAssertTrue(app.buttons["membership-skip"].waitForExistence(timeout: 30))
        app.buttons["membership-skip"].tap()
        app.tabBars.buttons["Travel"].tap(); app.buttons["Travel account"].tap()
        XCTAssertTrue(app.staticTexts["Onboarding Traveler"].waitForExistence(timeout: 10))
    }
    private func dismissStrongPasswordIfNeeded() {
        if app.staticTexts["Use Strong Password?"].waitForExistence(timeout: 3) { app.buttons["Close"].tap() }
    }
    private func dismissSavePasswordIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 3) { springboard.buttons["Not Now"].tap() }
        else if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
    }
    func testOnboardingPersonalizationAndPreview() {
        beginOnboarding()
        capture("21 Onboarding welcome")
        app.buttons["onboarding-start"].tap()
        app.buttons["interest-1"].tap()
        XCTAssertEqual(app.buttons["interest-1"].value as? String, "Selected")
        capture("22 Travel interests")
        app.buttons["onboarding-continue"].tap()
        app.buttons["cuisine-Japanese"].tap()
        capture("23 Dining preferences")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--onboarding-testing", "--preserve-state"]
        app.launch()
        XCTAssertEqual(app.buttons["cuisine-Japanese"].value as? String, "Selected")
        app.buttons["onboarding-back"].tap()
        XCTAssertEqual(app.buttons["interest-1"].value as? String, "Selected")
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-continue"].tap()
        app.buttons["destination-Paris"].tap()
        capture("24 First destination")
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-account-skip"].tap()
        XCTAssertTrue(app.buttons["membership-preview"].waitForExistence(timeout: 5))
        capture("25 Reserve introduction")
        reveal(app.buttons["membership-monthly"])
        app.buttons["membership-monthly"].tap()
        XCTAssertEqual(app.buttons["membership-monthly"].value as? String, "Selected")
        capture("26 Membership plans")
        app.buttons["membership-preview"].tap()
        XCTAssertTrue(app.buttons["membership-confirm"].waitForExistence(timeout: 5))
        capture("27 Simulated subscription confirmation")
        app.buttons["membership-cancel"].tap()
        XCTAssertTrue(app.buttons["membership-preview"].waitForExistence(timeout: 5))
        app.buttons["membership-preview"].tap()
        app.buttons["membership-confirm"].tap()
        XCTAssertTrue(app.buttons["membership-finish"].waitForExistence(timeout: 5))
        capture("28 Membership preview ready")
        app.buttons["membership-finish"].tap()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["personal-destination"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-start"].exists)
        app.buttons["Your workspace"].tap()
        reveal(app.buttons["profile-membership"]); app.buttons["profile-membership"].tap()
        reveal(app.buttons["membership-restore"]); app.buttons["membership-restore"].tap()
        XCTAssertTrue(app.alerts["Restore membership preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS 'monthly preview is restored'")).firstMatch.exists)
        app.alerts.buttons["OK"].tap()
        app.buttons["membership-close"].tap()
        reveal(app.buttons["profile-preferences"]); app.buttons["profile-preferences"].tap()
        XCTAssertEqual(app.buttons["interest-1"].value as? String, "Selected")
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.buttons["cuisine-Japanese"].value as? String, "Selected")
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.buttons["destination-Paris"].value as? String, "Selected")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["profile-preferences"].waitForExistence(timeout: 5))
    }
    func testOnboardingSkipWithoutSubscription() {
        beginOnboarding()
        app.buttons["onboarding-explore"].tap()
        reveal(app.buttons["membership-restore"]); app.buttons["membership-restore"].tap()
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No preview has been saved'")).firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["membership-skip"].tap()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--onboarding-testing", "--preserve-state"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-start"].exists)
    }
    func testOnboardingLargeText() {
        beginOnboarding(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        capture("29 Welcome accessibility text")
        app.buttons["onboarding-start"].tap()
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        capture("30 Preferences accessibility text")
        app.buttons["onboarding-skip"].tap()
        capture("73 Account accessibility text")
        XCTAssertTrue(app.buttons["onboarding-account-skip"].isHittable)
        app.buttons["onboarding-account-skip"].tap()
        XCTAssertTrue(app.buttons["membership-preview"].isHittable)
        app.buttons["membership-close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
    }

    func testSimpleTripCreationBuildsRouteAutomatically() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let create = app.buttons["journey-save"]
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(app.textFields["journey-name"].exists)
        XCTAssertFalse(app.buttons["journey-add-stop"].exists)
        XCTAssertFalse(app.buttons["Exact dates"].exists)
        XCTAssertFalse(app.switches["Add travel dates"].exists)
        XCTAssertTrue(app.datePickers["trip-departure-date"].exists)
        XCTAssertTrue(app.datePickers["trip-return-date"].exists)
        capture("46 Simple create trip")
        let destination = app.textFields["trip-destination"]
        destination.tap(); destination.typeText("Par")
        XCTAssertTrue(app.buttons["trip-destination-suggestion-0"].waitForExistence(timeout: 5))
        app.buttons["trip-destination-suggestion-0"].tap()
        XCTAssertTrue(create.isEnabled); create.tap()
        let trip = app.staticTexts["Trip to Paris, France"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        XCTAssertFalse(app.buttons["trip-add-route"].exists)
        XCTAssertTrue(app.buttons["journey-add"].exists)
        capture("47 Automatically prepared trip")
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        XCTAssertEqual(app.textFields["journey-name"].value as? String, "Trip to Paris, France")
        let savedStop = app.collectionViews.staticTexts["Paris, France"]
        reveal(savedStop); savedStop.tap()
        XCTAssertEqual(app.textFields["stop-country"].value as? String, "France")
        app.buttons["stop-save"].tap(); app.buttons["journey-save"].tap()
    }
    func testTripDestinationAutocompleteAndSave() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        destination.tap(); destination.typeText("Par")
        let suggestion = app.buttons["trip-destination-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); capture("32 Trip destination autocomplete")
        suggestion.tap(); XCTAssertEqual(destination.value as? String, "Paris, France")
        XCTAssertFalse(suggestion.exists)
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.staticTexts["Trip to Paris, France"].waitForExistence(timeout: 5))
        app.staticTexts["Trip to Paris, France"].tap()
        XCTAssertTrue(app.staticTexts["Paris, France"].waitForExistence(timeout: 5))
    }
    func testStopAutocompleteFillsCountry() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("London")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to London"].tap()
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        reveal(app.buttons["journey-add-stop"]); app.buttons["journey-add-stop"].tap()
        app.textFields["stop-name"].tap(); app.textFields["stop-name"].typeText("Par")
        XCTAssertTrue(app.buttons["stop-name-suggestion-0"].waitForExistence(timeout: 5))
        app.buttons["stop-name-suggestion-0"].tap()
        XCTAssertEqual(app.textFields["stop-country"].value as? String, "France")
        capture("33 Selected itinerary destination")
        app.buttons["stop-save"].tap(); XCTAssertTrue(app.staticTexts["Paris"].waitForExistence(timeout: 5))
    }
    func testFlightAirportAutocomplete() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.buttons["category-Flights"].tap()
        let origin = app.textFields["flight-origin"]
        origin.tap(); origin.typeText("Par")
        XCTAssertTrue(app.buttons["flight-origin-suggestion-0"].waitForExistence(timeout: 5))
        app.buttons["flight-origin-suggestion-0"].tap()
        XCTAssertEqual(origin.value as? String, "Paris Charles de Gaulle Airport")
        capture("34 Selected flight airport")
    }
    func testLiveTripDestinationAutocomplete() {
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        destination.tap(); destination.typeText("Paris")
        let suggestion = app.buttons["trip-destination-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 20), "Apple Maps should provide live destination suggestions")
        capture("35 Live Apple Maps autocomplete")
        suggestion.tap()
        let resolved = NSPredicate(format: "value != %@", "Paris")
        expectation(for: resolved, evaluatedWith: destination); waitForExpectations(timeout: 15)
        XCTAssertFalse(suggestion.exists)
        capture("36 Resolved live destination")
    }

    func testRatedPlaceAutocompleteFillsAddress() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris\n")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap(); app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap()
        let name = app.textFields["place-name"]; name.tap(); name.typeText("Par")
        XCTAssertTrue(app.buttons["place-name-suggestion-0"].waitForExistence(timeout: 5))
        app.buttons["place-name-suggestion-0"].tap()
        app.buttons["Location & contact"].tap()
        XCTAssertEqual(app.textFields["place-city"].value as? String, "Paris")
        XCTAssertEqual(app.textFields["place-address"].value as? String, "10 Avenue Example, Paris, France")
        app.buttons["Map coordinates"].tap()
        capture("37 Autocomplete place details")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.staticTexts["Paris Test Hotel"].waitForExistence(timeout: 5))
    }

}
