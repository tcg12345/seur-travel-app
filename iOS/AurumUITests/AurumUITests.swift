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
    private func revealHotel(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > 130 && element.frame.maxY < app.frame.maxY - 100 { return }
            let up = !element.exists || element.frame.minY >= 130
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.78 : 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: up ? 0.25 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
    /// Global search explores a city first. Booking is always a deliberate second action.
    private func beginHotelFromExplore() {
        let query = app.textFields["explore-city-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Rome")
        let city = app.buttons["explore-city-Rome"]
        XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
        let booking = app.buttons["city-book-hotel"]; XCTAssertTrue(booking.waitForExistence(timeout: 5))
        XCTAssertTrue(booking.waitForExistence(timeout: 5)); booking.tap()
    }
    func testSavedTravelerCreateEditDeleteAndCheckoutPrefill() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let travelers = app.buttons["travel-saved-travelers"]; revealHotel(travelers); XCTAssertTrue(travelers.waitForExistence(timeout: 5)); travelers.tap()
        let add = app.buttons["traveler-add"]; XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let save = app.buttons["traveler-save"]; XCTAssertFalse(save.isEnabled)
        for (field, value) in [("first", "Alex"), ("last", "Traveler"), ("email", "alex@example.test"), ("phone", "+14165550123")] {
            let input = app.textFields["traveler-" + field]; revealHotel(input); input.tap(); input.typeText(value)
        }
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        app.buttons["traveler-nationality"].tap()
        let query = app.textFields["traveler-country-query"]; XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Canada")
        app.buttons["traveler-country-CA"].tap(); XCTAssertTrue(save.isEnabled); capture("Travelers — new profile"); save.tap()
        let profile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traveler-select-")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5)); XCTAssertTrue(profile.label.contains("Default")); capture("Travelers — saved profiles")
        profile.tap()
        let first = app.textFields["traveler-first"]; first.tap(); first.typeText("andra")
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }; save.tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5)); XCTAssertTrue(profile.label.contains("Alexandra"))
        // A second profile can be removed without altering the first/default traveler.
        add.tap()
        for (field, value) in [("first", "Sam"), ("last", "Companion"), ("email", "sam@example.test"), ("phone", "+14165550124")] {
            let input = app.textFields["traveler-" + field]; revealHotel(input); input.tap(); input.typeText(value)
        }
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        app.buttons["traveler-nationality"].tap(); query.tap(); query.typeText("Canada"); app.buttons["traveler-country-CA"].tap(); save.tap()
        let companion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "traveler-select-", "Sam Companion")).firstMatch
        XCTAssertTrue(companion.waitForExistence(timeout: 5)); companion.tap(); revealHotel(app.buttons["traveler-delete"]); app.buttons["traveler-delete"].tap()
        app.buttons.matching(identifier: "Delete traveler").firstMatch.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "traveler-select-")).count, 1)
        app.buttons["hotel-step-back"].firstMatch.tap()
        app.tabBars.buttons["Discover"].tap()
        app.buttons["global-search"].tap(); beginHotelFromExplore()
        finishHotelSearchSteps(selectDates: true) { XCTAssertTrue(self.app.buttons["hotel-saved-traveler"].label.contains("Alexandra Traveler")) }
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); hotel.tap()
        app.buttons["hotel-view-rooms"].tap()
        let offer = app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"]; revealHotel(offer); offer.tap()
        let checkout = app.buttons["hotel-checkout-start"]; XCTAssertTrue(checkout.waitForExistence(timeout: 8)); checkout.tap()
        XCTAssertTrue(app.staticTexts["checkout-traveler-message"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["hotel-checkout-first"].value as? String, "Alexandra")
        XCTAssertEqual(app.textFields["hotel-checkout-email"].value as? String, "alex@example.test")
        XCTAssertTrue(app.buttons["hotel-checkout-review"].isEnabled); capture("Travelers — checkout prefill")
    }
    func testSandboxCancellationRequiresIntentAndUpdatesBookingRecord() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-bookings-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let bookings = app.buttons["travel-hotel-bookings"]; revealHotel(bookings); bookings.tap()
        let upcoming = app.buttons["hotel-bookings-filter-Upcoming"]; XCTAssertTrue(upcoming.waitForExistence(timeout: 8)); upcoming.tap()
        app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000001"].tap()
        let cancel = app.buttons["hotel-cancel-open"]; revealHotel(cancel); cancel.tap()
        let confirm = app.buttons["hotel-cancel-confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 8)); XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(app.staticTexts["hotel-cancel-success"].exists); capture("Cancellation — final review")
        confirm.tap(); XCTAssertTrue(app.staticTexts["hotel-cancel-success"].waitForExistence(timeout: 8)); capture("Cancellation — verified result")
        app.buttons["hotel-cancel-done"].tap()
        let status = app.staticTexts["hotel-record-status"]
        expectation(for: NSPredicate(format: "label == %@", "Test booking cancelled"), evaluatedWith: status); waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["hotel-cancel-open"].exists)
    }
    func testPendingCancellationReopensAfterAppRestartWithoutSecondSubmission() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-bookings-testing", "--hotel-cancel-pending"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let bookings = app.buttons["travel-hotel-bookings"]; revealHotel(bookings); bookings.tap()
        let upcoming = app.buttons["hotel-bookings-filter-Upcoming"]; XCTAssertTrue(upcoming.waitForExistence(timeout: 8)); upcoming.tap()
        let record = app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000001"]; record.tap()
        let cancel = app.buttons["hotel-cancel-open"]; revealHotel(cancel); cancel.tap()
        let confirm = app.buttons["hotel-cancel-confirm"]; XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
        XCTAssertTrue(app.staticTexts["You can leave this page. We’ll keep checking the original cancellation request."].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-cancel-pending"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); revealHotel(bookings); bookings.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 8)); record.tap(); revealHotel(cancel); cancel.tap()
        XCTAssertTrue(app.staticTexts["You can leave this page. We’ll keep checking the original cancellation request."].waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.exists); capture("Cancellation — resumed pending request")
    }
    func testBookingRefreshShowsProviderCancellation() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-bookings-testing", "--hotel-sync-cancelled"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let bookings = app.buttons["travel-hotel-bookings"]; revealHotel(bookings); bookings.tap()
        let confirmed = app.buttons["hotel-bookings-filter-Upcoming"]; XCTAssertTrue(confirmed.waitForExistence(timeout: 8)); confirmed.tap()
        let record = app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000001"]; XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        let refresh = app.buttons["Refresh booking"]; XCTAssertTrue(refresh.waitForExistence(timeout: 5)); refresh.tap()
        let status = app.staticTexts["hotel-record-status"]
        expectation(for: NSPredicate(format: "label == %@", "Test booking cancelled"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["hotel-provider-checked"].exists)
        XCTAssertEqual(app.buttons["hotel-record-share"].label, "Share support summary")
        capture("Bookings — provider cancellation")
    }
    func testTravelBookingsFiltersDetailsAndSupportSummary() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-bookings-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let bookings = app.buttons["travel-hotel-bookings"]; revealHotel(bookings); XCTAssertTrue(bookings.waitForExistence(timeout: 8)); bookings.tap()
        let confirmed = app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000001"]
        let upcoming = app.buttons["hotel-bookings-filter-Upcoming"]
        XCTAssertTrue(upcoming.waitForExistence(timeout: 8)); capture("Bookings — attention first")
        upcoming.tap()
        XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000003"].exists)
        capture("Bookings — upcoming stays")
        app.buttons["hotel-bookings-filter-Past"].tap()
        let past = app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000005"]
        XCTAssertTrue(past.waitForExistence(timeout: 5)); XCTAssertFalse(confirmed.exists)
        capture("Bookings — past stays")
        past.tap(); XCTAssertTrue(app.staticTexts["TEST-SEUR-PAST"].waitForExistence(timeout: 5)); app.buttons["hotel-step-back"].tap()
        upcoming.tap(); XCTAssertTrue(confirmed.waitForExistence(timeout: 5))
        confirmed.tap(); XCTAssertTrue(app.buttons["hotel-record-share"].waitForExistence(timeout: 8)); XCTAssertTrue(app.staticTexts["TEST-SEUR-001"].exists); capture("Bookings — test receipt")
        let support = app.buttons["hotel-record-support"]; revealHotel(support); support.tap()
        XCTAssertTrue(app.staticTexts["hotel-support-summary"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["hotel-support-share"].exists); capture("Bookings — shareable summary")
        app.buttons["hotel-step-back"].tap(); app.buttons["hotel-step-back"].tap()
        let filter = app.buttons["hotel-bookings-filter-Needs attention"]
        if !filter.isHittable { app.scrollViews.containing(.button, identifier: "hotel-bookings-filter-All").firstMatch.swipeLeft() }
        filter.tap()
        let attention = app.buttons["hotel-saved-checkout-10000000-0000-4000-8000-000000000003"]; XCTAssertTrue(attention.waitForExistence(timeout: 5)); attention.tap()
        XCTAssertTrue(app.staticTexts["hotel-record-status"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["hotel-record-status"].label.contains("attention")); XCTAssertFalse(app.staticTexts["TEST-SEUR-001"].exists)
        XCTAssertTrue(app.buttons["hotel-record-share"].label.contains("support")); capture("Bookings — needs attention")
    }
    func testBookingHistoryLoadsOlderMatchesRetriesAndPreservesDetailReturn() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--hotel-history-testing", "--hotel-history-retry"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let bookings = app.buttons["travel-hotel-bookings"]; revealHotel(bookings); bookings.tap()
        let past = app.buttons["hotel-bookings-filter-Past"]; XCTAssertTrue(past.waitForExistence(timeout: 8)); past.tap()
        let older = app.buttons["hotel-bookings-load-more"]; XCTAssertTrue(older.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["hotel-bookings-loaded-count"].label.contains("30")); capture("Bookings — load older matches")
        older.tap(); XCTAssertTrue(app.staticTexts["hotel-bookings-more-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["hotel-bookings-loaded-count"].label.contains("30")); capture("Bookings — retry older page")
        older.tap(); XCTAssertTrue(app.staticTexts["hotel-bookings-loaded-count"].label.contains("60"))
        older.tap()
        let record = app.buttons["hotel-saved-checkout-20000000-0000-4000-8000-000000000064"]
        revealHotel(record); XCTAssertTrue(record.isHittable); XCTAssertFalse(older.exists)
        record.tap(); XCTAssertTrue(app.staticTexts["TEST-HISTORY-64"].waitForExistence(timeout: 5))
        app.buttons["hotel-step-back"].tap(); XCTAssertTrue(record.waitForExistence(timeout: 5))
        let count = app.staticTexts["hotel-bookings-loaded-count"]; revealHotel(count)
        XCTAssertTrue(count.label.contains("All 65")); XCTAssertFalse(older.exists); capture("Bookings — complete history")
    }
    func testSpecificHotelSearchOpensProviderDetailWithoutDestinationStep() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
        app.segmentedControls["explore-search-scope"].buttons["Hotels"].tap()
        let input = app.textFields["hotel-name-query"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Palazzo")
        let suggestion = app.buttons["hotel-name-query-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); capture("Search — hotel suggestions"); suggestion.tap()
        let result = app.buttons["hotel-name-result-liteapi:lpfixture0"]; XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["hotel-name-result-liteapi:lpfixture1"].exists)
        XCTAssertFalse(app.buttons["hotel-dates-apply"].exists); capture("Search — named hotel matches"); result.tap()
        XCTAssertTrue(app.staticTexts["hotel-detail-title"].waitForExistence(timeout: 5))
        let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.exists); rooms.tap()
        finishHotelSearchSteps(selectDates: true)
        let offer = app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"]; revealHotel(offer); XCTAssertTrue(offer.waitForExistence(timeout: 8))
    }
    func testExplicitStaysShortcutUsesFullPageDestinationAndBack() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing"]; app.launch()
        let stays = app.buttons["category-Stays"]; XCTAssertTrue(stays.waitForExistence(timeout: 8)); stays.tap()
        XCTAssertTrue(app.textFields["hotel-destination"].waitForExistence(timeout: 5))
        let rome = app.buttons["hotel-city-Rome"]; revealHotel(rome); rome.tap()
        XCTAssertTrue(app.buttons["hotel-dates-apply"].waitForExistence(timeout: 5)); app.buttons["hotel-step-back"].tap()
        XCTAssertTrue(app.textFields["hotel-destination"].waitForExistence(timeout: 5)); app.buttons["hotel-step-back"].tap()
        XCTAssertTrue(stays.waitForExistence(timeout: 5)); XCTAssertTrue(app.tabBars.buttons["Discover"].exists)
    }
    func testExploreSearchOpensCityBeforeFullPageHotelFlow() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["explore-dining"].exists); XCTAssertTrue(app.buttons["explore-experiences"].exists)
        XCTAssertFalse(app.buttons["hotel-dates"].exists); XCTAssertFalse(app.buttons["hotel-guests"].exists)
        capture("Explore — destinations first")
        let query = app.textFields["explore-city-query"]; query.tap(); query.typeText("Rome")
        let city = app.buttons["explore-city-Rome"]; XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
        let booking = app.buttons["city-book-hotel"]; XCTAssertTrue(booking.waitForExistence(timeout: 5)); XCTAssertTrue(booking.isHittable)
        XCTAssertFalse(app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"].exists)
        capture("Explore — Rome city guide")
        let bookingFrame = booking.frame
        XCTAssertLessThan(bookingFrame.width, app.frame.width * 0.6)
        XCTAssertGreaterThan(bookingFrame.midX, app.frame.midX)
        app.swipeUp()
        XCTAssertTrue(booking.isHittable)
        XCTAssertEqual(booking.frame.minY, bookingFrame.minY, accuracy: 2)
        capture("Explore — floating hotel shortcut")
        booking.tap()
        XCTAssertTrue(app.buttons["hotel-dates-apply"].waitForExistence(timeout: 5)); XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty)
        XCTAssertFalse(app.buttons["Close Your dates"].exists)
        finishHotelSearchSteps(selectDates: true)
        XCTAssertTrue(app.buttons["hotel-search-bar"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["hotel-search-bar"].label.contains("Rome"))
        XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty)
        app.buttons["hotel-search-close"].tap()
        XCTAssertTrue(booking.waitForExistence(timeout: 5)); XCTAssertTrue(app.textFields["explore-city-query"].exists == false)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(query.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["hotel-dates"].exists)
    }
    private func finishHotelSearchSteps(selectDates: Bool = false, configureGuests: () -> Void = {}) {
        XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5))
        if selectDates {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            let arrival = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
            let departure = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
            let start = app.buttons["hotel-date-" + formatter.string(from: arrival)]
            revealHotel(start); start.tap(); capture("Stays — range calendar")
            let end = app.buttons["hotel-date-" + formatter.string(from: departure)]
            revealHotel(end); end.tap()
        } else { app.buttons["hotel-dates-apply"].tap() }
        XCTAssertTrue(app.staticTexts["Who's coming?"].waitForExistence(timeout: 5))
        configureGuests()
        capture("Stays — full-page guests")
        app.buttons["hotel-guests-apply"].tap()
    }
    private func openHotelCheckout(flags: [String] = []) {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"] + flags; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true)
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); hotel.tap()
        let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.waitForExistence(timeout: 8)); rooms.tap()
        let offer = app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"]; revealHotel(offer); XCTAssertTrue(offer.waitForExistence(timeout: 8)); offer.tap()
        let start = app.buttons["hotel-checkout-start"]; XCTAssertTrue(start.waitForExistence(timeout: 8)); start.tap()
        let submit = app.buttons["hotel-checkout-review"]; XCTAssertTrue(submit.waitForExistence(timeout: 8)); XCTAssertFalse(submit.isEnabled)
        for (name, value) in [("first", "Test"), ("last", "Traveler"), ("email", "test@example.test"), ("phone", "+12125550123")] {
            let input = app.textFields["hotel-checkout-" + name]; revealHotel(input); input.tap(); input.typeText(value)
        }
        if app.toolbars.buttons["Done"].exists { app.toolbars.buttons["Done"].tap() }
        XCTAssertTrue(submit.isEnabled); capture("Checkout — guest details"); submit.tap()
        XCTAssertTrue(app.buttons["hotel-checkout-confirm"].waitForExistence(timeout: 8))
    }
    func testHotelRichFiltersPhotoModesAndPinnedRoomAction() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true) { XCTAssertFalse(self.app.buttons["hotel-nationality"].exists) }
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8))
        app.buttons["hotel-filters"].tap()
        let maximum = app.sliders["hotel-price-max"]; XCTAssertTrue(maximum.waitForExistence(timeout: 5))
        capture("Hotels — expanded filters")
        maximum.adjust(toNormalizedSliderPosition: 0)
        app.buttons["hotel-filters-apply"].tap()
        XCTAssertTrue(app.staticTexts["No stays match these filters"].waitForExistence(timeout: 5))
        app.buttons["hotel-filters"].tap(); app.buttons["hotel-filters-reset"].tap(); app.buttons["hotel-filters-apply"].tap()
        XCTAssertTrue(hotel.waitForExistence(timeout: 5)); hotel.tap()
        let hero = app.buttons["hotel-gallery"]; XCTAssertTrue(hero.waitForExistence(timeout: 5)); capture("Hotels — edge-to-edge detail")
        XCTAssertEqual(hero.frame.minX, app.frame.minX, accuracy: 2); XCTAssertEqual(hero.frame.maxX, app.frame.maxX, accuracy: 2)
        let rating = app.descendants(matching: .any).matching(identifier: "hotel-average-rating").firstMatch
        XCTAssertTrue(rating.label.contains("9.4/10")); XCTAssertTrue(rating.label.contains("826"))
        hero.tap()
        XCTAssertTrue(app.buttons["hotel-photo-next"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["hotel-photo-count"].label, "1 / 12")
        app.buttons["hotel-photo-next"].tap(); XCTAssertEqual(app.staticTexts["hotel-photo-count"].label, "2 / 12")
        capture("Hotels — individual photo")
        app.segmentedControls.buttons["Gallery"].tap()
        let thumbnail = app.buttons["hotel-photo-thumb-3"]; XCTAssertTrue(thumbnail.waitForExistence(timeout: 5)); capture("Hotels — gallery grid"); thumbnail.tap()
        XCTAssertTrue(app.buttons["hotel-photo-next"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["hotel-photo-count"].label, "4 / 12")
        app.buttons["hotel-gallery-done"].tap()
        let room = app.buttons["hotel-room-details-room1"]; revealHotel(room); XCTAssertTrue(room.waitForExistence(timeout: 5)); room.tap()
        let plan = app.buttons["hotel-plan-room"]; XCTAssertTrue(plan.waitForExistence(timeout: 5)); XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty)
        let roomHero = app.buttons["hotel-room-photos"]
        XCTAssertTrue(roomHero.exists)
        XCTAssertEqual(roomHero.frame.minY, app.frame.minY, accuracy: 2)
        XCTAssertEqual(roomHero.frame.width, app.frame.width, accuracy: 2)
        XCTAssertFalse(app.staticTexts["Room details"].exists)
        let roomBack = app.buttons["hotel-room-back"]
        XCTAssertTrue(roomBack.isHittable)
        XCTAssertTrue(roomHero.frame.contains(roomBack.frame))
        capture("Hotels — full-bleed room header")
        roomHero.tap()
        XCTAssertTrue(app.buttons["hotel-photo-next"].waitForExistence(timeout: 5))
        app.buttons["hotel-gallery-done"].tap()
        XCTAssertGreaterThan(plan.frame.minY, app.frame.height * 0.80)
        let before = plan.frame; app.swipeUp(); XCTAssertEqual(plan.frame.minY, before.minY, accuracy: 2)
        capture("Hotels — pinned room action")
        roomBack.tap()
        XCTAssertTrue(app.buttons["hotel-view-rooms"].waitForExistence(timeout: 5))
    }
    func testHotelSandboxCheckoutRequiresFinalIntentAndShowsProviderReceipt() {
        openHotelCheckout()
        XCTAssertFalse(app.otherElements["hotel-booking-receipt"].exists)
        capture("Checkout — final review")
        app.buttons["hotel-checkout-confirm"].tap()
        XCTAssertTrue(app.staticTexts["Test booking confirmed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["TEST-SEUR-001"].exists)
        XCTAssertTrue(app.staticTexts["Nothing · Sandbox"].exists)
        XCTAssertTrue(app.buttons["hotel-checkout-done"].isHittable)
        capture("Checkout — test confirmation")
        XCTAssertTrue(app.buttons["hotel-checkout-done"].isHittable)
    }
    func testHotelChangedQuotePendingAttemptCanBeReopenedAfterAppTermination() {
        openHotelCheckout(flags: ["--hotel-checkout-changed", "--hotel-checkout-pending"])
        XCTAssertTrue(app.staticTexts["The price or terms changed. Review the updated details below."].exists)
        capture("Checkout — changed price")
        app.buttons["hotel-checkout-confirm"].tap()
        XCTAssertTrue(app.staticTexts["Confirming your test stay"].waitForExistence(timeout: 8)); capture("Checkout — pending confirmation")
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--hotel-checkout-pending"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps()
        app.buttons["hotel-checkouts"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "hotel-saved-checkout-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8)); saved.tap()
        XCTAssertTrue(app.staticTexts["Confirming your test stay"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["hotel-checkout-confirm"].exists); capture("Checkout — resumed attempt")
    }
    func testHotelViewRoomsCollectsMissingDatesAndMovesToOptions() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps()
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); hotel.tap()
        let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.waitForExistence(timeout: 8)); rooms.tap()
        XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5))
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        for offset in [2, 5] {
            let day = app.buttons["hotel-date-" + formatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)]
            revealHotel(day); day.tap()
        }
        XCTAssertTrue(app.buttons["hotel-guests-apply"].waitForExistence(timeout: 5)); app.buttons["hotel-guests-apply"].tap()
        let offer = app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"]
        XCTAssertTrue(offer.waitForExistence(timeout: 8)); XCTAssertTrue(offer.isHittable)
    }
    func testHotelFamilyOccupancyNationalityAndRoomRemoval() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--hotel-nationality-empty"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore()
        finishHotelSearchSteps(selectDates: true) {
            XCTAssertTrue(app.buttons["hotel-guests-apply"].isEnabled)
            XCTAssertFalse(app.buttons["hotel-nationality"].exists)
            let addRoom = app.buttons["hotel-add-room"]; XCTAssertTrue(addRoom.waitForExistence(timeout: 5)); addRoom.tap()
            let remove = app.buttons["hotel-remove-room-1"]; revealHotel(remove); remove.tap()
            revealHotel(addRoom); addRoom.tap()
            let adults = app.buttons["hotel-adults-1-minus"]; revealHotel(adults); adults.tap()
            let child = app.buttons["hotel-children-0-plus"]; revealHotel(child); child.tap()
            XCTAssertFalse(app.buttons["hotel-guests-apply"].isEnabled)
            let age = app.buttons["hotel-child-age-0-0"]; revealHotel(age); age.tap()
            let six = app.buttons["hotel-child-age-option-6"]; XCTAssertTrue(six.waitForExistence(timeout: 5)); revealHotel(six); XCTAssertTrue(app.sheets.allElementsBoundByIndex.isEmpty); capture("Stays — full-page child age"); six.tap()
            XCTAssertTrue(app.buttons["hotel-guests-apply"].isEnabled); capture("Rates — family occupancy")
        }
        XCTAssertTrue(app.buttons["hotel-guests"].label.contains("4 guests")); XCTAssertTrue(app.buttons["hotel-guests"].label.contains("2 rooms"))
    }
    func testHotelRatesRoomOptionsAndQuoteBreakdown() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true)
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); capture("Rates — total stay results"); hotel.tap()
        let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.waitForExistence(timeout: 8)); rooms.tap()
        let offer = app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"]; revealHotel(offer); XCTAssertTrue(offer.waitForExistence(timeout: 8)); capture("Rates — room packages"); offer.tap()
        XCTAssertTrue(app.staticTexts["Your room option"].waitForExistence(timeout: 8)); XCTAssertTrue(app.staticTexts["City tax"].exists)
        capture("Rates — quote and hotel charges")
        XCTAssertFalse(app.buttons["Pay & book"].exists)
    }
    func testHotelRatesEmptyAndErrorRemainDistinct() {
        for flag in ["--hotel-rates-empty", "--hotel-rates-error"] {
            app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", flag]; app.launch()
            XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
            beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true)
            let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); hotel.tap()
            let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.waitForExistence(timeout: 8)); rooms.tap()
            let message = app.staticTexts[flag == "--hotel-rates-empty" ? "No rooms available for these dates." : "Prices are temporarily unavailable. Try again."]
            revealHotel(message); XCTAssertTrue(message.exists); capture(flag == "--hotel-rates-empty" ? "Rates — unavailable" : "Rates — retry")
        }
    }
    func testHotelRatesExpiredOptionsRequireRefresh() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--hotel-rates-expired"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true)
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 8)); hotel.tap()
        let rooms = app.buttons["hotel-view-rooms"]; XCTAssertTrue(rooms.waitForExistence(timeout: 8)); rooms.tap()
        XCTAssertFalse(app.buttons["hotel-room-offer-rate-liteapi-lpfixture0-0"].exists)
        XCTAssertTrue(app.buttons["hotel-rates-refresh"].exists)
    }
    func testHotelDiscoverySearchDetailsReviewsAndSavedPersistence() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        let search = app.buttons["global-search"]; XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap()
        XCTAssertFalse(app.staticTexts["Find your next stay"].exists)
        beginHotelFromExplore()
        finishHotelSearchSteps(selectDates: true)
        let first = app.buttons["hotel-open-liteapi:lpfixture0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); capture("Stays — minimal results")
        XCTAssertLessThan(app.buttons["hotel-search-bar"].frame.minY, 150)
        app.buttons["hotel-map-toggle"].tap()
        let more = app.buttons["hotel-map-more"]; XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        XCTAssertTrue(app.staticTexts["hotel-result-count"].label.contains("23"))
        app.buttons["hotel-map-toggle"].tap()
        revealHotel(first); first.tap()
        XCTAssertTrue(app.staticTexts["hotel-detail-title"].waitForExistence(timeout: 5)); capture("Stays — hotel details")
        app.buttons["hotel-detail-save"].tap(); XCTAssertEqual(app.buttons["hotel-detail-save"].label, "Unsave hotel")
        app.buttons["hotel-gallery"].tap(); XCTAssertTrue(app.buttons["hotel-gallery-done"].waitForExistence(timeout: 5)); capture("Stays — photo gallery"); app.buttons["hotel-gallery-done"].tap()
        app.buttons["Reviews"].tap()
        let reviews = app.buttons["hotel-load-reviews"]; revealHotel(reviews); reviews.tap()
        XCTAssertTrue(app.staticTexts["Thoughtful service and a peaceful room."].firstMatch.waitForExistence(timeout: 5)); capture("Stays — guest reviews")
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--preserve-state"]; app.launch()
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); beginHotelFromExplore(); finishHotelSearchSteps()
        let saved = app.buttons["hotel-save-liteapi:lpfixture0"]; XCTAssertTrue(saved.waitForExistence(timeout: 5)); XCTAssertTrue(saved.label.hasPrefix("Unsave"))
    }
    func testHotelSearchEmptyAndProviderFailure() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps()
        app.buttons["hotel-filters"].tap()
        let name = app.textFields["hotel-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("empty")
        app.buttons["hotel-filters-apply"].tap()
        XCTAssertTrue(app.staticTexts["No matches this time"].waitForExistence(timeout: 5)); capture("Stays — minimal empty state")
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--hotel-error"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap(); beginHotelFromExplore(); finishHotelSearchSteps()
        XCTAssertTrue(app.staticTexts["Couldn't load hotels"].waitForExistence(timeout: 5)); capture("Stays — retry state")
    }
    func testHotelStepBackAndCancelledDateEditPreserveSelection() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore()
        XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5)); app.buttons["hotel-dates-apply"].tap()
        XCTAssertTrue(app.buttons["hotel-step-back"].waitForExistence(timeout: 5)); app.buttons["hotel-adults-plus"].tap(); app.buttons["hotel-step-back"].tap()
        XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5)); app.buttons["hotel-step-back"].tap()
        XCTAssertTrue(app.buttons["city-book-hotel"].waitForExistence(timeout: 5)); app.buttons["city-book-hotel"].tap()
        finishHotelSearchSteps()
        XCTAssertTrue(app.buttons["hotel-guests"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["hotel-guests"].label.contains("2 adults"))
        app.buttons["hotel-dates"].tap()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let day = app.buttons["hotel-date-" + formatter.string(from: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap(); app.buttons["hotel-step-back"].tap()
        XCTAssertTrue(app.buttons["hotel-dates"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["hotel-dates"].label.contains("Add dates"))
    }
    func testHotelPlanReviewUsesSearchDatesAndDoesNotBook() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "--hotel-plan-testing"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore(); finishHotelSearchSteps(selectDates: true)
        let hotel = app.buttons["hotel-open-liteapi:lpfixture0"]; XCTAssertTrue(hotel.waitForExistence(timeout: 5)); hotel.tap()
        let plan = app.buttons["hotel-plan-stay"]; XCTAssertTrue(plan.waitForExistence(timeout: 5)); plan.tap()
        let trip = app.buttons["hotel-plan-trip-EEEE0000-0000-4000-8000-000000000099"]
        XCTAssertTrue(trip.waitForExistence(timeout: 8)); trip.tap()
        let save = app.buttons["hotel-plan-save"]; XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isEnabled)
        capture("Stays — plan review"); save.tap()
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        plan.tap(); XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap(); XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(app.staticTexts["This hotel is already in your trip."].waitForExistence(timeout: 5))
    }
    func testHotelSheetsSupportLargeTextAndDarkMode() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--hotel-testing", "--city-testing", "--location-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-aurum.appearance", "Dark"]; app.launch()
        XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        beginHotelFromExplore()
        XCTAssertTrue(app.buttons["hotel-dates-apply"].waitForExistence(timeout: 5)); app.buttons["hotel-dates-apply"].tap()
        XCTAssertTrue(app.buttons["hotel-adults-plus"].waitForExistence(timeout: 5)); app.buttons["hotel-adults-plus"].tap()
        let apply = app.buttons["hotel-guests-apply"]
        let close = app.buttons["hotel-step-back"]
        XCTAssertTrue(close.isHittable); XCTAssertGreaterThanOrEqual(close.frame.minX, app.frame.minX); XCTAssertLessThanOrEqual(close.frame.maxX, app.frame.maxX)
        XCTAssertTrue(apply.isHittable); XCTAssertGreaterThan(apply.frame.minX, app.frame.minX); XCTAssertLessThan(apply.frame.maxX, app.frame.maxX)
        capture("Stays — accessible guests"); apply.tap()
        app.buttons["hotel-dates"].tap(); XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5)); capture("Stays — accessible calendar")
        XCTAssertTrue(app.buttons["hotel-dates-apply"].isHittable)
    }
    func testGuideCreateDraftPreviewPublishAndOfflinePersistence() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--guide-publishing-testing"]; app.launch()
        let travel = app.tabBars.buttons["Travel"]; XCTAssertTrue(travel.waitForExistence(timeout: 8)); travel.tap()
        app.buttons["travel-guides"].tap()
        XCTAssertTrue(app.buttons["guides-create"].waitForExistence(timeout: 5)); capture("Guides — library empty state")
        app.buttons["guides-create"].tap()
        let destination = app.textFields["guide-destination"]; XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap(); destination.typeText("Par")
        let citySuggestion = app.buttons["guide-destination-suggestion-0"]
        XCTAssertTrue(citySuggestion.waitForExistence(timeout: 5)); capture("Guides — destination autocomplete")
        citySuggestion.tap(); XCTAssertEqual(destination.value as? String, "Paris, France")
        XCTAssertFalse(citySuggestion.exists)
        app.textFields["guide-start-title"].tap(); app.textFields["guide-start-title"].typeText("Paris, at your pace")
        app.buttons["guide-start-writing"].tap()
        let intro = app.textViews["guide-introduction"].exists ? app.textViews["guide-introduction"] : app.textFields["guide-introduction"]
        XCTAssertTrue(intro.waitForExistence(timeout: 5)); intro.tap(); intro.typeText("A few favorite places for an unhurried weekend.")
        let addSection = app.buttons["guide-add-section"]; reveal(addSection); addSection.tap()
        let section = app.textFields["guide-section-title"]; XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap(); section.typeText("A perfect first morning")
        app.buttons["guide-add-place"].tap()
        let place = app.textFields["guide-place-name"]; XCTAssertTrue(place.waitForExistence(timeout: 5)); place.tap(); place.typeText("Eiffel Tower\n")
        let note = app.textViews["guide-place-note"].exists ? app.textViews["guide-place-note"] : app.textFields["guide-place-note"]
        reveal(note); note.tap(); note.typeText("Arrive early and walk over from Trocadero.")
        app.buttons["guide-place-save"].tap(); app.buttons["guide-section-save"].tap()
        capture("Guides — chapter editor")
        app.buttons["guide-preview"].tap()
        let publish = app.buttons["guide-publish-button"]; reveal(publish); XCTAssertTrue(publish.isEnabled)
        capture("Guides — publication preview")
        publish.tap(); app.buttons["guide-confirm-publish"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["guide-published"].waitForExistence(timeout: 8) || app.otherElements["guide-published"].exists)
        XCTAssertTrue(app.buttons["guide-share-link"].exists)
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state"]; app.launch()
        XCTAssertTrue(travel.waitForExistence(timeout: 8)); travel.tap(); app.buttons["travel-guides"].tap()
        app.buttons["guides-shelf-Your guides"].tap()
        XCTAssertTrue(app.staticTexts["Paris, at your pace"].waitForExistence(timeout: 5))
        app.staticTexts["Paris, at your pace"].tap()
        let restoredTitle = app.textViews["guide-title"].exists ? app.textViews["guide-title"] : app.textFields["guide-title"]
        XCTAssertTrue(restoredTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredTitle.value as? String, "Paris, at your pace")
        capture("Guides — restored draft")
    }
    func testTripPhotoCardsListGridCreditsAndNavigation() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--trip-card-testing"]; app.launch()
        let tab = app.tabBars.buttons["Travel"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        let title = app.staticTexts["Trip to Paris, France"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); reveal(title)
        capture("Trip cards — destination photography")
        let credits = app.buttons["trip-photo-credits"].firstMatch; reveal(credits); credits.tap()
        XCTAssertTrue(app.navigationBars["Destination photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Photo by Seur test fixture on Pexels"].exists)
        XCTAssertTrue(app.staticTexts["Test destination cover"].exists)
        XCTAssertTrue(app.links["View photo on Pexels"].exists || app.buttons["View photo on Pexels"].exists)
        capture("Trip cards — photo attribution")
        app.buttons["Done"].tap()
        let newYork = app.staticTexts["Trip to New York, NY, United States"]
        reveal(newYork); XCTAssertTrue(newYork.exists)
        XCTAssertFalse(app.staticTexts["Photo credits"].exists)
        capture("Trip cards — instant New York landmark")
        let grid = app.buttons["Grid view"]; reveal(grid); capture("Trip cards — layout control"); grid.tap()
        XCTAssertTrue(app.staticTexts["An Athenian autumn"].waitForExistence(timeout: 5))
        capture("Trip cards — compact grid and fallback")
        title.tap()
        XCTAssertTrue(app.staticTexts["journey-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["journey-title"].label, "Trip to Paris, France")
    }
    func testTemplateDiscoveryDateCloneAndSaveOwnTemplate() {
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertFalse(app.buttons["travel-section-Templates"].exists)
        XCTAssertTrue(app.buttons["travel-section-Wishlist"].exists)
        app.buttons["travel-new-trip"].tap()
        app.buttons["travel-use-template"].tap()
        let riviera = app.buttons.containing(.staticText, identifier: "The Riviera, slowly").firstMatch
        reveal(riviera); XCTAssertTrue(riviera.exists); riviera.tap()
        let use = app.buttons["template-use"]; XCTAssertTrue(use.waitForExistence(timeout: 5)); use.tap()
        XCTAssertTrue(app.datePickers["template-departure"].exists)
        app.buttons["template-create-trip"].tap()
        XCTAssertTrue(app.staticTexts["journey-title"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["journey-title"].label, "The Riviera, slowly")
        app.buttons["Share journey"].tap()
        app.buttons["trip-save-template"].tap()
        app.buttons["template-save"].tap()
        XCTAssertTrue(app.buttons["trip-save-template"].waitForExistence(timeout: 5))
    }
    func testDiscoverCurrentTripShowsTodayAndOpensItinerary() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--today-testing"]; app.launch()
        let card = app.buttons["discover-current-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(card.staticTexts["Today in Paris"].exists)
        XCTAssertFalse(app.buttons["discover-continue-trip"].exists)
        XCTAssertFalse(app.staticTexts["Or start with"].exists)
        XCTAssertTrue(card.staticTexts["Lunch by the river"].exists)
        XCTAssertTrue(card.staticTexts["13:00 – 14:30"].exists)
        XCTAssertFalse(card.staticTexts["Museum morning"].exists)
        XCTAssertLessThan(card.frame.minY, app.buttons["explore-cities"].frame.minY)
        XCTAssertFalse(app.staticTexts["Where to next?"].exists)
        XCTAssertFalse(app.staticTexts["Start from an itinerary"].exists)
        card.tap()
        XCTAssertTrue(app.staticTexts["journey-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["journey-title"].label, "Paris with family")
        app.terminate(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["explore-cities"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discover-current-trip"].exists)
    }
    func testTripBudgetOptInCancelSaveAndCollapse() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--today-testing"]; app.launch()
        let current = app.buttons["discover-current-trip"]
        XCTAssertTrue(current.waitForExistence(timeout: 5)); current.tap()
        let summary = app.buttons["trip-budget-toggle"]
        XCTAssertFalse(summary.exists)
        let menu = app.buttons["journey-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let setup = app.buttons["trip-budget-setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5)); XCTAssertEqual(setup.label, "Add budget"); setup.tap()
        XCTAssertTrue(app.textFields["budget-target"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertFalse(summary.exists)
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(setup.waitForExistence(timeout: 5)); setup.tap()
        let target = app.textFields["budget-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "900")
        app.buttons["budget-save"].tap()
        reveal(summary); XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["trip-budget-edit"].exists)
        summary.tap()
        XCTAssertTrue(app.buttons["trip-budget-edit"].waitForExistence(timeout: 5))
        reveal(summary); summary.tap()
        XCTAssertFalse(app.buttons["trip-budget-edit"].exists)
        app.terminate(); app.launchArguments += ["--preserve-state"]; app.launch()
        XCTAssertTrue(current.waitForExistence(timeout: 5)); current.tap()
        reveal(summary); XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.value as? String, "Collapsed")
        summary.tap()
        let edit = app.buttons["trip-budget-edit"]; reveal(edit); edit.tap()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue((target.value as? String ?? "").contains("900"))
        app.buttons["Cancel"].tap()
    }
    func testBudgetDashboardAddAndEditExpense() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--today-testing", "--budget-testing"]; app.launch()
        let current = app.buttons["discover-current-trip"]
        XCTAssertTrue(current.waitForExistence(timeout: 5)); current.tap()
        let summary = app.buttons["trip-budget-toggle"]; reveal(summary); summary.tap()
        let open = app.buttons["trip-budget-open"]; reveal(open); open.tap()
        app.buttons["budget-add-expense"].tap()
        let save = app.buttons["budget-expense-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        capture("Add expense editor")
        save.tap()
        XCTAssertTrue(app.staticTexts["Add a short expense name (up to 200 characters)."].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        let title = app.textFields["budget-expense-title"]; title.tap(); title.typeText("Morning coffee")
        let amount = app.textFields["budget-expense-amount"]; amount.tap(); amount.typeText(XCUIKeyboardKey.delete.rawValue + "25")
        save.tap()
        XCTAssertTrue(app.buttons["budget-add-expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["budget-spent-total"].label.contains("25"))
        capture("Budget dashboard with spending")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "budget-expense-", "Morning coffee")).firstMatch
        reveal(row); XCTAssertTrue(row.exists); row.tap()
        let paid = app.switches["budget-expense-paid"]
        XCTAssertTrue(paid.waitForExistence(timeout: 5))
        capture("Edit expense editor")
        XCTAssertEqual(paid.value as? String, "1")
        paid.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(paid.value as? String, "0")
        save.tap()
        let planned = app.buttons["budget-filter-Planned"]; reveal(planned); planned.tap()
        reveal(row); XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Planned"))
        let spentFilter = app.buttons["budget-filter-Spent"]; reveal(spentFilter)
        capture("Budget planned expenses")
        spentFilter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(spentFilter.isSelected)
        XCTAssertFalse(row.exists)
        capture("Budget expense filters")
    }
    func testBudgetTargetCompanionsDoneAndSettlement() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--today-testing", "--budget-testing"]; app.launch()
        let current = app.buttons["discover-current-trip"]
        XCTAssertTrue(current.waitForExistence(timeout: 5)); current.tap()
        let summary = app.buttons["trip-budget-toggle"]
        reveal(summary); XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.value as? String, "Collapsed")
        capture("Budget collapsed")
        summary.tap()
        let edit = app.buttons["trip-budget-edit"]
        reveal(edit); XCTAssertTrue(edit.isHittable)
        capture("Budget expanded")
        edit.tap()
        let target = app.textFields["budget-target"]
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        target.press(forDuration: 1.1)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap(); target.typeText("600") }
        else { target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "600") }
        let name = app.textFields["budget-companion-name"]
        name.tap(); name.typeText("Casey")
        app.buttons["Add"].tap()
        app.buttons["budget-save"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        for _ in 0..<4 { app.swipeDown() }
        let activity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "event-")).firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 5)); activity.tap()
        let done = app.switches["today-event-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(done.value as? String, "1")
        app.buttons["today-actions-done"].tap()
        let openBudget = app.buttons["trip-budget-open"]
        reveal(openBudget); openBudget.tap()
        capture("Budget dashboard")
        let settlement = app.buttons["trip-settlement"]
        reveal(settlement); XCTAssertTrue(settlement.exists); settlement.tap()
        XCTAssertTrue(app.staticTexts["Blair owes Alex"].waitForExistence(timeout: 5))
        app.buttons["budget-dashboard-settings"].tap()
        XCTAssertTrue(app.staticTexts["Casey"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textFields["budget-target"].value as? String ?? "").contains("600"))
        app.buttons["Cancel"].tap()
    }
    func testTodayAutomaticTimelineDayNavigationAndConfirmation() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--today-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.staticTexts["today-day-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["today-day-title"].label, "Today")
        XCTAssertTrue(app.descendants(matching: .any)["today-next"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "Lunch by the river").count, 1)
        XCTAssertFalse(app.buttons["today-open-trip"].exists)
        XCTAssertFalse(app.staticTexts["Your travel library"].exists)
        XCTAssertFalse(app.buttons["today-directions"].exists)
        let activity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "event-")).firstMatch
        activity.tap()
        XCTAssertTrue(app.buttons["today-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today-call"].exists)
        XCTAssertTrue(app.buttons["today-website"].exists)
        app.buttons["today-actions-done"].tap()
        app.buttons["today-next-day"].tap()
        XCTAssertEqual(app.staticTexts["today-day-title"].label, "Tomorrow")
        XCTAssertTrue(app.staticTexts["Museum morning"].exists)
        app.buttons["today-previous"].tap()
        let today = app.descendants(matching: .any)["today-view"]
        let from = today.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15))
        let to = today.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.15))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertEqual(app.staticTexts["today-day-title"].label, "Tomorrow")
        app.buttons["today-previous"].tap()
        let stay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "stay-")).firstMatch
        stay.tap()
        let confirmation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today-confirmation-")).firstMatch
        reveal(confirmation); XCTAssertTrue(confirmation.exists); confirmation.tap()
        XCTAssertTrue(confirmation.label.contains("copied"))
        app.buttons["today-actions-done"].tap()
        app.buttons["today-previous"].tap(); app.buttons["today-previous"].tap()
        XCTAssertTrue(app.staticTexts["today-day-title"].label.hasPrefix("No activities"))
        let trip = app.buttons.containing(.staticText, identifier: "Paris with family").firstMatch
        reveal(trip); trip.tap()
        let mode = app.buttons["trip-plan-view"]; reveal(mode)
        XCTAssertEqual(mode.value as? String, "Today")
        mode.tap(); app.buttons["List"].tap()
        XCTAssertEqual(mode.value as? String, "List")
    }
    func testWidgetsRegisterAndAddFromSystemGallery() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SEUR_WIDGET_GALLERY_TEST"] == "1", "Opt-in system UI check: enable SEUR_WIDGET_GALLERY_TEST=1 in the test scheme. Adds a widget to the test device.")
        app.terminate(); app.launchArguments = ["--ui-testing", "--widget-testing", "--location-testing", "--city-testing"]; app.launch()
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if !springboard.searchFields["Search Widgets"].exists {
            if !springboard.buttons["Edit"].exists {
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(forDuration: 1.5)
            }
            let edit = springboard.buttons["Edit"]
            XCTAssertTrue(edit.waitForExistence(timeout: 6), springboard.debugDescription); edit.tap()
            let addControl = springboard.buttons["Add Widget"]
            XCTAssertTrue(addControl.waitForExistence(timeout: 5), springboard.debugDescription); addControl.tap()
        }
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), springboard.debugDescription); search.tap(); if (search.value as? String) != "Seur" { search.typeText("Seur") }
        let result = springboard.cells["Seur"]
        XCTAssertTrue(result.waitForExistence(timeout: 8), springboard.debugDescription); result.tap()
        XCTAssertTrue(springboard.staticTexts["Today in Seur"].waitForExistence(timeout: 6), springboard.debugDescription)
        let shot = XCTAttachment(screenshot: springboard.screenshot()); shot.name = "Seur system widget gallery"; shot.lifetime = .keepAlways; add(shot)
        let addWidget = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add Widget")).firstMatch
        if addWidget.waitForExistence(timeout: 5) { addWidget.tap() }
        else { springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.905)).tap() }
        let done = springboard.buttons["Done"]; if done.waitForExistence(timeout: 5) { done.tap() }
        XCTAssertTrue(springboard.otherElements.containing(.staticText, identifier: "TODAY").firstMatch.waitForExistence(timeout: 5), springboard.debugDescription)
    }
    func testWidgetInvitationAfterFirstTripIsDismissedOnce() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--widget-discovery-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertFalse(app.buttons["travel-widgets"].exists)
        XCTAssertFalse(app.buttons["widget-invitation-guide"].exists)
        app.buttons["travel-create"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["widget-invitation-guide"].waitForExistence(timeout: 2))
        app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap(); destination.typeText("Par")
        let suggestion = app.buttons["trip-destination-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        app.buttons["journey-save"].tap()
        let invitation = app.buttons["widget-invitation-guide"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 8))
        capture("Widget invitation after first trip")
        app.buttons["widget-invitation-dismiss"].tap()
        app.tabBars.buttons["Discover"].tap(); app.tabBars.buttons["Travel"].tap()
        XCTAssertFalse(invitation.waitForExistence(timeout: 2))
        app.terminate(); app.launchArguments += ["--preserve-state"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.staticTexts["Trip to Paris, France"].waitForExistence(timeout: 5))
        XCTAssertFalse(invitation.waitForExistence(timeout: 2))
    }
    func testWidgetInvitationOpensGuide() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--widget-testing", "--widget-discovery-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let invitation = app.buttons["widget-invitation-guide"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 8)); invitation.tap()
        XCTAssertTrue(app.scrollViews["widget-guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Seur widgets"].exists)
        capture("Widget invitation guide")
    }
    func testWidgetGuideAndTripDeepLinks() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--widget-testing", "--location-testing", "--city-testing"]; app.launch()
        app.buttons["Your workspace"].tap()
        let guide = app.buttons["profile-widgets"]
        reveal(guide); XCTAssertTrue(guide.exists); guide.tap()
        XCTAssertTrue(app.navigationBars["Seur widgets"].waitForExistence(timeout: 5))
        capture("Widget guide")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.open(URL(string: "seur://trip/30000000-0000-0000-0000-000000000001?widget=SeurToday")!)
        XCTAssertTrue(app.staticTexts["Widget Paris trip"].waitForExistence(timeout: 5))
        let walk = app.staticTexts["Walk by the river"].firstMatch; reveal(walk); XCTAssertTrue(walk.exists)
        app.buttons["Done"].firstMatch.tap()
        app.open(URL(string: "seur://trip/30000000-0000-0000-0000-000000000001?widget=SeurTripBudget")!)
        XCTAssertTrue(app.navigationBars["Trip budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["budget-add-expense"].exists)
        capture("Widget budget destination")
        app.buttons["Done"].firstMatch.tap()
        app.open(URL(string: "seur://profile")!)
        XCTAssertTrue(app.staticTexts["Your travel story."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].firstMatch.exists)
        capture("Widget travel profile destination")
    }
    func testSeasonalityInDestinationDatePickingAndMonthCalendar() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        destination.tap(); destination.typeText("Par")
        let suggestion = app.buttons["trip-destination-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        let calendar = app.buttons["seasonality-calendar-paris"]
        reveal(calendar); XCTAssertTrue(calendar.exists); calendar.tap()
        XCTAssertTrue(app.navigationBars["Paris by season"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["January"].exists)
        let august = app.staticTexts["August"]; reveal(august); XCTAssertTrue(august.exists)
        capture("Seasonality monthly comparison")
        let notice = app.staticTexts["August restaurant holidays"]; reveal(notice); XCTAssertTrue(notice.exists)
        app.buttons["seasonality-calendar-done"].tap()
        XCTAssertTrue(app.buttons["journey-save"].waitForExistence(timeout: 5))
    }
    func testSeasonalityRouteReorderUpdatesAugustWarning() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--seasonality-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let trip = app.buttons.containing(.staticText, identifier: "Seasons in Europe").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        app.buttons["trip-route-planner"].tap()
        let august = app.staticTexts["seasonality-selected-paris-8"]
        reveal(august); XCTAssertTrue(august.exists)
        XCTAssertTrue(app.staticTexts["August restaurant holidays"].exists)
        let move = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Move Paris")).firstMatch
        reveal(move); move.tap(); app.buttons["Move later"].tap()
        let september = app.staticTexts["seasonality-selected-paris-9"]
        reveal(september); XCTAssertTrue(september.exists)
        XCTAssertFalse(app.staticTexts["August restaurant holidays"].exists)
        capture("Seasonality after route reorder")
        app.buttons["route-apply"].tap()
        XCTAssertTrue(app.staticTexts["London → Paris"].waitForExistence(timeout: 5))
    }
    func testMultiCityRouteSuggestionManualOrderAndPersistence() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--routing-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        let trip = app.buttons.containing(.staticText, identifier: "European route").firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let route = app.buttons["trip-route-planner"]; XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        XCTAssertTrue(app.staticTexts["route-suggestion-message"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["route-suggestion-message"].label.contains("Suggested order ready"))
        let restore = app.buttons["route-restore"]; reveal(restore); restore.tap()
        let move = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Move Amsterdam")).firstMatch
        for _ in 0..<5 { if move.exists && move.isHittable { break }; app.swipeDown(velocity: .slow) }
        XCTAssertTrue(move.exists, app.debugDescription); move.tap()
        app.buttons["Move later"].tap()
        app.buttons["route-apply"].tap()
        XCTAssertTrue(app.staticTexts["Paris → Brussels → Amsterdam"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments += ["--preserve-state"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        XCTAssertTrue(app.staticTexts["Paris → Brussels → Amsterdam"].waitForExistence(timeout: 5))
        app.buttons["trip-route-planner"].tap()
        XCTAssertTrue(app.buttons["route-apply"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        let transfer = app.staticTexts["Travel to Brussels"].firstMatch; reveal(transfer); XCTAssertTrue(transfer.exists)
    }
    func testFlightTimetableAndImmersedAirportDetails() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].tap(); XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 8))
        resizeMapPanel(expanded: true); app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap(); resizeMapPanel(expanded: true)
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 5))
        let time = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "30m late")).firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 8))
        let heading = app.staticTexts["flight-timetable-title"]; reveal(heading)
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(app.staticTexts["Gate departure"].exists)
        XCTAssertTrue(app.staticTexts["Taxi to runway"].exists)
        let landing = app.staticTexts["Landing"]; reveal(landing); XCTAssertTrue(landing.exists)
        let gate = app.staticTexts["Gate arrival"]; reveal(gate); XCTAssertTrue(gate.exists)
        let performance = app.buttons["flight-performance"]; reveal(performance); performance.tap()
        XCTAssertTrue(app.buttons["Load delay history"].waitForExistence(timeout: 5))
        app.buttons["All flights"].tap(); XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 5))
    }
    func testMapPanelReachesEdgesAndCollapsesAfterContentScrolling() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 8))
        let surface = app.otherElements["map-panel-surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        let compactWidth = surface.frame.width
        XCTAssertEqual(compactWidth, app.frame.width - 24, accuracy: 2)
        resizeMapPanel(expanded: true)
        XCTAssertEqual(surface.frame.width, app.frame.width, accuracy: 2)
        app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap(); resizeMapPanel(expanded: true)
        let scroll = app.scrollViews["map-panel-scroll"].firstMatch
        scroll.swipeUp(); scroll.swipeUp()
        reveal(app.buttons["flight-performance"]); XCTAssertTrue(app.buttons["flight-performance"].exists)
        let contentY = app.buttons["flight-performance"].frame.minY
        resizeMapPanel(expanded: false)
        XCTAssertEqual(surface.frame.width, compactWidth, accuracy: 2)
        resizeMapPanel(expanded: true)
        XCTAssertEqual(surface.frame.width, app.frame.width, accuracy: 2)
        XCTAssertEqual(app.buttons["flight-performance"].frame.minY, contentY, accuracy: 3, "Resizing must preserve the content scroll position")
        XCTAssertEqual(app.scrollViews.matching(identifier: "map-panel-scroll").count, 1)
    }
    func testMapPanelContentPanHandsOffWithoutMovingMap() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 8))
        resizeMapPanel(expanded: true); app.buttons["map-section-Flights"].tap()
        let surface = app.otherElements["map-panel-surface"].firstMatch
        // Pull within the scroll content, not the handle: the native pan owns this path.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
        XCTAssertEqual(surface.frame.width, app.frame.width - 24, accuracy: 2)
        let scroll = app.scrollViews["map-panel-scroll"].firstMatch
        let start = scroll.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: scroll.frame.width * 0.5, dy: 55))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
        XCTAssertEqual(surface.frame.width, app.frame.width, accuracy: 2)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch.isHittable)
        XCTAssertEqual(app.scrollViews.matching(identifier: "map-panel-scroll").count, 1)
    }
    func testOrganizedFlightDetailSectionsAndTimingLabels() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 8))
        resizeMapPanel(expanded: true); app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap(); resizeMapPanel(expanded: true)
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 5))
        let departure = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "30m late")).firstMatch
        XCTAssertTrue(departure.waitForExistence(timeout: 8)); XCTAssertTrue(departure.label.contains("30m late"))
        let arrival = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "35m late")).firstMatch; reveal(arrival)
        XCTAssertTrue(arrival.label.contains("35m late"))
        let performance = app.buttons["flight-performance"]; reveal(performance); performance.tap()
        XCTAssertTrue(app.buttons["Load delay history"].waitForExistence(timeout: 5))
        app.buttons["All flights"].tap()
        XCTAssertTrue(app.buttons["map-section-Flights"].waitForExistence(timeout: 5))
    }
    private func openWishlist(preserve: Bool = false) {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"] + (preserve ? ["--preserve-state"] : []); app.launch()
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.buttons["travel-section-Wishlist"].waitForExistence(timeout: 8)); app.buttons["travel-section-Wishlist"].tap()
    }
    private func firstWishlistItem() -> XCUIElement { app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wishlist-item-")).firstMatch }
    func testWishlistTypedDestinationSearchAndSave() {
        openWishlist()
        XCTAssertFalse(app.staticTexts["Add your first idea"].exists)
        for type in ["trip", "destination", "hotel", "restaurant", "activity", "sight"] {
            XCTAssertTrue(app.buttons["wishlist-save-" + type].exists)
        }
        capture("Wishlist — choose a trip or place")
        app.buttons["wishlist-save-destination"].tap()
        let name = app.textFields["wishlist-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Paris")
        let suggestion = app.buttons["wishlist-name-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 8)); capture("Wishlist — destination suggestions"); suggestion.tap()
        XCTAssertTrue(app.buttons["wishlist-save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["wishlist-collection"].exists)
        capture("Wishlist — review destination")
        app.buttons["wishlist-save"].tap()
        let item = firstWishlistItem(); XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
        XCTAssertEqual(app.staticTexts["wishlist-detail-title"].label, "Paris")
        openWishlist(preserve: true)
        XCTAssertTrue(firstWishlistItem().waitForExistence(timeout: 5))
        app.buttons["wishlist-actions"].tap(); app.buttons["wishlist-menu-hotel"].tap()
        XCTAssertTrue(app.staticTexts["Find a hotel"].waitForExistence(timeout: 5))
        app.textFields["wishlist-name"].tap(); app.textFields["wishlist-name"].typeText("Paris")
        XCTAssertTrue(app.buttons["wishlist-name-suggestion-0"].waitForExistence(timeout: 8))
        app.buttons["wishlist-name-suggestion-0"].tap()
        XCTAssertTrue(app.buttons["wishlist-save"].waitForExistence(timeout: 5)); capture("Wishlist — review hotel")
        app.buttons["wishlist-save"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wishlist-item-")).count, 2)
    }
    func testWishlistFullTripUsesNightsThenDatesOnlyAfterScheduling() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-section-Wishlist"].tap()
        app.buttons["wishlist-actions"].tap()
        app.buttons["wishlist-menu-trip"].tap()
        XCTAssertTrue(app.steppers["wishlist-trip-nights"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.datePickers["trip-departure-date"].exists)
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris\n")
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.buttons["wishlist-schedule-trip"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wishlist-trip-plan-")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5)); capture("Wishlist organized trip plans"); plan.tap()
        app.buttons["journey-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Edit journey"].waitForExistence(timeout: 3)); app.buttons["Edit journey"].tap()
        XCTAssertFalse(app.segmentedControls["Plan with"].exists)
        let stop = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-stop-")).firstMatch
        reveal(stop); stop.tap()
        XCTAssertTrue(app.steppers["stop-nights"].waitForExistence(timeout: 5))
        app.buttons["stop-save"].tap(); app.buttons["journey-save"].tap()
        app.buttons["wishlist-schedule-trip"].tap()
        XCTAssertTrue(app.datePickers["wishlist-departure-date"].waitForExistence(timeout: 5))
        app.buttons["wishlist-confirm-dates"].tap()
        XCTAssertTrue(app.buttons["journey-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wishlist-schedule-trip"].exists)
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        XCTAssertFalse(app.segmentedControls["Plan with"].exists)
        reveal(stop); stop.tap()
        XCTAssertFalse(app.steppers["stop-nights"].exists)
        XCTAssertEqual(app.datePickers.count, 2)
    }
    func testWishlistCustomIdeaPersistencePlanningAndRemoval() {
        openWishlist()
        capture("Wishlist clear starting point")
        XCTAssertTrue(app.buttons["wishlist-save-activity"].waitForExistence(timeout: 5), app.buttons.debugDescription)
        XCTAssertTrue(app.buttons["wishlist-save-activity"].isHittable)
        XCTAssertFalse(app.buttons["wishlist-filters"].exists)
        XCTAssertFalse(app.textFields["wishlist-search"].exists)
        XCTAssertFalse(app.buttons["travel-widgets"].exists)
        XCTAssertFalse(app.buttons["travel-new-trip"].exists)
        app.buttons["wishlist-save-activity"].tap()
        let name = app.textFields["wishlist-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("An evening at the museum")
        app.textFields["wishlist-destination"].tap(); app.textFields["wishlist-destination"].typeText("London\n")
        let next = app.buttons["wishlist-continue"]; reveal(next); next.tap()
        XCTAssertTrue(app.buttons["wishlist-save"].waitForExistence(timeout: 5))
        capture("Wishlist — optional details collapsed")
        app.buttons["Add a note or collection"].tap()
        let notes = app.descendants(matching: .any).matching(identifier: "wishlist-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5)); notes.tap(); notes.typeText("Go after lunch")
        app.swipeUp()
        let collection = app.textFields["wishlist-collection"]; collection.tap(); collection.typeText("Summer")
        app.buttons["wishlist-save"].tap()
        let item = firstWishlistItem(); XCTAssertTrue(item.waitForExistence(timeout: 5))
        capture("Wishlist organized saved ideas")
        let search = app.textFields["wishlist-search"]
        XCTAssertTrue(search.exists); search.tap(); search.typeText("No matching destination")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 3))
        app.buttons["Clear search & filters"].tap()
        app.buttons["wishlist-filters"].tap(); app.buttons["Top picks only"].tap()
        XCTAssertTrue(app.staticTexts["No places match these filters."].waitForExistence(timeout: 3))
        app.buttons["wishlist-reset"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 3)); item.tap()
        XCTAssertTrue(app.staticTexts["wishlist-notes-display"].waitForExistence(timeout: 5))
        app.buttons["wishlist-top-pick"].tap()
        XCTAssertEqual(app.buttons["wishlist-top-pick"].value as? String, "Selected")
        app.buttons["wishlist-plan"].tap()
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wishlist-trip-")).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        XCTAssertTrue(app.buttons["event-save"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["place-name"].value as? String, "An evening at the museum")
        app.buttons["event-save"].tap()
        XCTAssertTrue(app.buttons["wishlist-planned-trip"].waitForExistence(timeout: 8))
        openWishlist(preserve: true)
        firstWishlistItem().tap()
        XCTAssertEqual(app.staticTexts["wishlist-notes-display"].label, "Go after lunch")
        XCTAssertEqual(app.buttons["wishlist-top-pick"].value as? String, "Selected")
        app.buttons["wishlist-planned-trip"].tap()
        XCTAssertTrue(app.staticTexts["An evening at the museum"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        let remove = app.buttons["wishlist-remove"]; reveal(remove); remove.tap()
        let confirms = app.buttons.matching(identifier: "wishlist-confirm-remove"); XCTAssertTrue(confirms.firstMatch.waitForExistence(timeout: 5)); let confirm = confirms.allElementsBoundByIndex.first { $0.isHittable }; XCTAssertNotNil(confirm); confirm?.tap()
        XCTAssertTrue(app.otherElements["wishlist-empty"].waitForExistence(timeout: 5) || !firstWishlistItem().exists)
        app.buttons["travel-section-Trips"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Map QA journey")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["An evening at the museum"].waitForExistence(timeout: 5))
    }
    func testWishlistSavedHotelAndNewTripContinuation() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing"]; app.launch()
        let hotel = app.buttons["hero-hotel"]; reveal(hotel); hotel.tap()
        XCTAssertTrue(app.buttons["detail-save"].waitForExistence(timeout: 5)); app.buttons["detail-save"].tap()
        app.navigationBars.buttons.firstMatch.tap(); app.tabBars.buttons["Travel"].tap(); app.buttons["travel-section-Wishlist"].tap()
        capture("Wishlist saved hotel")
        let item = firstWishlistItem(); XCTAssertTrue(item.waitForExistence(timeout: 5), app.buttons.debugDescription); item.tap()
        XCTAssertTrue(app.buttons["wishlist-source"].waitForExistence(timeout: 5))
        app.buttons["wishlist-plan"].tap(); app.buttons["wishlist-new-trip"].tap()
        let destination = app.textFields["trip-destination"]; XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.value as? String, "Bangkok")
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.buttons["hotel-record-save"].waitForExistence(timeout: 8))
        app.buttons["hotel-record-save"].tap()
        XCTAssertTrue(app.buttons["wishlist-planned-trip"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["wishlist-actions"].tap()
        app.buttons["wishlist-menu-destination"].tap()
        app.textFields["wishlist-name"].tap(); app.textFields["wishlist-name"].typeText("Paris\n")
        app.buttons["wishlist-continue"].tap()
        app.buttons["wishlist-save"].tap()
        let paris = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "wishlist-item-", "Paris")).firstMatch
        XCTAssertTrue(paris.waitForExistence(timeout: 5)); paris.tap(); app.buttons["wishlist-plan"].tap()
        XCTAssertTrue(app.textFields["trip-destination"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["trip-destination"].value as? String, "Paris")
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.buttons["wishlist-planned-trip"].waitForExistence(timeout: 5))
    }
    func testDiscoverClearStartingPointAndCategoryDestinations() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing"]; app.launch()
        let start = app.buttons["explore-cities"]
        XCTAssertTrue(start.waitForExistence(timeout: 8)); XCTAssertTrue(start.isHittable)
        for name in ["Stays", "Dining", "Experiences", "Flights"] {
            XCTAssertTrue(app.buttons["category-" + name].isHittable)
        }
        XCTAssertLessThan(start.frame.minY, app.buttons["category-Stays"].frame.minY)
        start.tap(); XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["category-Stays"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Mandarin Oriental, Bangkok"].exists || app.buttons["search-explore-cities"].exists)
        app.buttons["Done"].tap()
        app.buttons["category-Flights"].tap()
        XCTAssertTrue(app.textFields["flight-origin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["flight-destination"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        for category in [("Dining", "Restaurants"), ("Experiences", "Things to do")] {
            app.buttons["category-" + category.0].tap()
            XCTAssertTrue(app.navigationBars[category.1].waitForExistence(timeout: 5))
            let query = app.textFields["explore-city-query"]; query.tap(); query.typeText("Lis")
            let suggestion = app.buttons["explore-city-query-suggestion-0"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
            XCTAssertTrue(app.buttons["city-all-interests"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["city-all-interests"].label.contains(category.1))
            app.navigationBars.buttons.firstMatch.tap(); app.navigationBars.buttons.firstMatch.tap()
        }
        let create = app.buttons["discover-create-trip"]; reveal(create); create.tap()
        XCTAssertTrue(app.textFields["trip-destination"].waitForExistence(timeout: 5))
    }
    func testDiscoverResumeTripAndInspirationWithLargeText() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]; app.launch()
        XCTAssertTrue(app.buttons["explore-cities"].waitForExistence(timeout: 8))
        let resume = app.buttons["discover-continue-trip"]; reveal(resume); resume.tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        let hero = app.buttons["hero-hotel"]; reveal(hero); hero.tap()
        XCTAssertTrue(app.buttons["detail-save"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        let concierge = app.buttons["discover-concierge"]; reveal(concierge); concierge.tap()
        XCTAssertTrue(app.tabBars.buttons["Concierge"].isSelected)
    }
    func testFriendsTabSharedItineraryPeopleAndSearch() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--friends-testing"]; app.launch()
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.buttons["Friends"].waitForExistence(timeout: 8))
        XCTAssertTrue(bar.buttons["Concierge"].exists); XCTAssertFalse(bar.buttons["More"].exists)
        XCTAssertGreaterThan(bar.buttons["Friends"].frame.minX, bar.buttons["Travel"].frame.minX)
        bar.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["friends-home-title"].waitForExistence(timeout: 8))
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "friends-trip-")).firstMatch
        if !trip.isHittable { app.swipeUp() }
        XCTAssertTrue(trip.waitForExistence(timeout: 8)); trip.tap()
        XCTAssertTrue(app.staticTexts["shared-itinerary-title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["shared-itinerary-copy"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeDown()
        app.buttons["friends-section-People"].tap()
        XCTAssertTrue(app.staticTexts["Maya Chen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Accept"].exists)
        app.buttons["friends-add-person"].tap()
        XCTAssertTrue(app.textFields["friend-invite-username"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["friends-section-Messages"].tap()
        XCTAssertTrue(app.staticTexts["Paris planning"].waitForExistence(timeout: 5))
        bar.buttons["Travel"].tap(); XCTAssertFalse(app.segmentedControls["travel-tool"].exists)
        bar.buttons["Discover"].tap(); app.buttons["global-search"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(bar.buttons["Friends"].exists)
    }
    func testGlobeFlightsTripsAndSaved() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        app.tabBars.buttons["Map"].firstMatch.tap()
        let content = app.buttons["map-section-Flights"]; XCTAssertTrue(content.waitForExistence(timeout: 8)); capture("63 Globe map")
        resizeMapPanel(expanded: true); app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap()
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 5)); capture("64 Flight route panel")
        resizeMapPanel(expanded: true)
        XCTAssertTrue(app.staticTexts["UI test · Delayed"].waitForExistence(timeout: 5)); capture("65 Flight intelligence")
        let performance = app.buttons["flight-performance"]; reveal(performance); performance.tap()
        let history = app.buttons["Load delay history"]; reveal(history); history.tap()
        XCTAssertTrue(app.staticTexts["UI test sample only"].waitForExistence(timeout: 5)); capture("66 Flight delay history")
        app.buttons["All flights"].tap(); app.buttons["map-section-Trips"].tap()
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-trip-")).firstMatch; XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        XCTAssertTrue(app.buttons["Open trip"].waitForExistence(timeout: 5))
        app.buttons["map-saved"].tap(); XCTAssertTrue(app.navigationBars["Saved places"].waitForExistence(timeout: 5))
    }
    func testMapTripRecapPlaybackAndReturnToOverview() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-section-Trips"].waitForExistence(timeout: 8))
        resizeMapPanel(expanded: true)
        app.buttons["map-section-Trips"].tap()
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-trip-")).firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        resizeMapPanel(expanded: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.buttons["map-trip-recap"].tap()
        let play = app.buttons["map-recap-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["recap-replay"].exists, "Recap should use the main map, not embed another map")
        play.tap()
        XCTAssertTrue(app.staticTexts["map-recap-current-stop"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["map-recap-current-stop"].label.contains("London"))
        let finished = expectation(for: NSPredicate(format: "label CONTAINS %@", "Play route"), evaluatedWith: play)
        wait(for: [finished], timeout: 8)
        app.buttons["map-recap-memories"].tap()
        reveal(app.buttons["recap-share"])
        XCTAssertTrue(app.buttons["recap-share"].exists, app.debugDescription)
        reveal(app.staticTexts["Day by day"])
        XCTAssertTrue(app.staticTexts["Day by day"].exists)
        let close = app.buttons["map-recap-close"]
        for _ in 0..<5 { if close.isHittable { break }; app.swipeDown() }
        close.tap()
        XCTAssertTrue(app.buttons["map-trip-recap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map-recap-play"].exists)
        app.buttons["map-section-Flights"].tap()
        XCTAssertTrue(app.buttons["map-add-flight"].waitForExistence(timeout: 5))
    }
    func testSheetDraggingPreservesMapCameraAndViewport() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["map-section-Explore"].waitForExistence(timeout: 8))
        let probe = app.staticTexts["map-camera-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 8))
        func camera() -> [Double] { probe.label.split(separator: ",").compactMap { Double($0) } }
        expectation(for: NSPredicate { _, _ in camera().count == 5 }, evaluatedWith: probe); waitForExpectations(timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let baseline = camera(), tabY = app.tabBars.firstMatch.frame.minY
        guard baseline.count == 5 else { return XCTFail("Missing camera measurement") }
        for section in ["Explore", "Trips", "Flights"] {
            app.buttons["map-section-" + section].tap()
            for expanded in [true, false] {
                resizeMapPanel(expanded: expanded)
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                let current = camera()
                XCTAssertEqual(current.count, 5)
                guard current.count == 5 else { continue }
                XCTAssertEqual(current[0], baseline[0], accuracy: 0.0001, "Sheet moved map latitude")
                XCTAssertEqual(current[1], baseline[1], accuracy: 0.0001, "Sheet moved map longitude")
                XCTAssertEqual(current[2], baseline[2], accuracy: 20, "Sheet changed map zoom")
                XCTAssertEqual(current[3], baseline[3], accuracy: 0.01)
                XCTAssertEqual(current[4], baseline[4], accuracy: 0.01)
                XCTAssertEqual(app.tabBars.firstMatch.frame.minY, tabY, accuracy: 2)
                XCTAssertEqual(app.scrollViews.matching(identifier: "map-panel-scroll").count, 1)
            }
        }
    }
    func testNativeMapSheetExpandsAndReturnsToTabBar() {
        let mapTab = app.tabBars.buttons["Map"].firstMatch
        expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: mapTab)
        waitForExpectations(timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let originalBarY = app.tabBars.firstMatch.frame.minY
        mapTab.tap()
        let expand = app.buttons["map-section-Explore"]; XCTAssertTrue(expand.waitForExistence(timeout: 8))
        let compactY = expand.frame.minY; capture("68 Native map sheet compact")
        app.buttons["map-section-Trips"].tap(); capture("84 Compact trips panel")
        app.buttons["map-section-Flights"].tap(); capture("85 Compact flights panel")
        app.buttons["map-section-Explore"].tap()
        XCTAssertGreaterThanOrEqual(app.otherElements["map-panel-surface"].frame.maxY, app.frame.maxY - 1)
        resizeMapPanel(expanded: true)
        let raised = NSPredicate { _, _ in expand.frame.minY < compactY - 200 }
        expectation(for: raised, evaluatedWith: expand); waitForExpectations(timeout: 8)
        capture("69 Native map sheet expanded")
        XCTAssertGreaterThanOrEqual(app.otherElements["map-panel-surface"].frame.maxY, app.frame.maxY - 1)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY, originalBarY, accuracy: 2)
        resizeMapPanel(expanded: false)
        expectation(for: NSPredicate { _, _ in expand.frame.minY > compactY - 50 }, evaluatedWith: expand); waitForExpectations(timeout: 8)
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5)); XCTAssertTrue(bar.buttons["Travel"].isHittable)
        bar.buttons["Travel"].tap()
        XCTAssertTrue(app.buttons["travel-create"].waitForExistence(timeout: 5)); capture("83 Minimal travel dashboard")
        app.tabBars.buttons["Map"].firstMatch.tap(); XCTAssertTrue(expand.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        resizeMapPanel(expanded: true)
        expectation(for: raised, evaluatedWith: expand); waitForExpectations(timeout: 8)
        capture("70 Native dragged sheet with navigation")
        XCTAssertFalse(app.buttons["map-panel-expand"].exists)
        XCTAssertFalse(app.buttons["map-panel-options"].exists)
        resizeMapPanel(expanded: false)
        expectation(for: NSPredicate { _, _ in expand.frame.minY > compactY - 50 }, evaluatedWith: expand); waitForExpectations(timeout: 8)
        app.buttons["map-saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved places"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.scrollViews["map-panel-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map-section-Explore"].isHittable)
        XCTAssertFalse(app.buttons["map-show-panel"].exists)
        capture("101 Map sheet remains visible after Saved places")
    }
    func testMapSectionSwitchKeepsLayoutAndSearch() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "--location-testing", "--city-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        app.tabBars.buttons["Map"].tap()
        let expand = app.buttons["map-section-Explore"]
        XCTAssertTrue(expand.waitForExistence(timeout: 8))
        let tabY = app.tabBars.firstMatch.frame.minY
        for expanded in [false, true] {
            if expanded { resizeMapPanel(expanded: true); RunLoop.current.run(until: Date().addingTimeInterval(0.7)) }
            let handle = app.otherElements["map-panel-handle"]
            let headerY = handle.frame.minY
            let legal = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Legal")).firstMatch
            if !expanded {
                XCTAssertTrue(legal.waitForExistence(timeout: 5))
                XCTAssertLessThan(legal.frame.maxY, app.otherElements["map-panel-handle"].frame.minY)
            }
            let legalY = legal.exists ? legal.frame.minY : 0
            for _ in 0..<2 {
                for section in ["Trips", "Flights", "Explore"] {
                    app.buttons["map-section-" + section].tap()
                    XCTAssertEqual(handle.frame.minY, headerY, accuracy: 2)
                    XCTAssertEqual(app.tabBars.firstMatch.frame.minY, tabY, accuracy: 2)
                    XCTAssertEqual(app.scrollViews.matching(identifier: "map-panel-scroll").count, 1)
                    if !expanded {
                        XCTAssertTrue(legal.exists)
                        XCTAssertEqual(legal.frame.minY, legalY, accuracy: 2)
                    }
                }
                let search = app.textFields["world-city-search"]
                XCTAssertTrue(search.isHittable)
                XCTAssertGreaterThan(search.frame.minY, expand.frame.minY)
                XCTAssertLessThan(search.frame.maxY, expand.frame.maxY + 100)
            }
            capture(expanded ? "88 Stable expanded Explore" : "87 Stable compact Explore")
        }
        let search = app.textFields["world-city-search"]
        search.tap(); search.typeText("Par")
        let result = app.buttons["world-city-search-suggestion-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["map-city-guide"].waitForExistence(timeout: 8))
        app.buttons["map-section-Flights"].tap(); app.buttons["map-section-Explore"].tap()
        XCTAssertEqual(search.value as? String, "Paris")
        XCTAssertTrue(search.isHittable)
    }
    func testMapBodyDragAndStandaloneFlight() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch()
        let originalBar = app.tabBars.firstMatch.frame
        app.tabBars.buttons["Map"].tap()
        let expand = app.buttons["map-section-Explore"]; XCTAssertTrue(expand.waitForExistence(timeout: 8))
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
        let number = app.textFields["flight-number-query"]; XCTAssertTrue(number.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["flight-airline-query"].exists)
        XCTAssertFalse(app.datePickers["flight-search-date"].exists)
        XCTAssertFalse(app.buttons["flight-step-continue"].isEnabled)
        capture("90 Separate flight number page")
        number.tap(); number.typeText("178\n")
        XCTAssertTrue(app.buttons["flight-find"].waitForExistence(timeout: 5))
        XCTAssertFalse(number.exists)
        capture("91 Separate departure date page")
        app.buttons["flight-find"].tap()
        let result = app.buttons["flight-result-BAW178-ui-test"]; XCTAssertTrue(result.waitForExistence(timeout: 8))
        capture("92 Clear flight search result")
        result.tap()
        XCTAssertTrue(app.staticTexts["flight-added-confirmation"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["flight-record-save"].exists)
        XCTAssertFalse(app.staticTexts["map-flight-title"].exists)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-standalone-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertLessThan(saved.frame.height, 175, "Flight rows should stay compact at normal text size")
        XCTAssertTrue(saved.label.contains("Scheduled time passed"))
        capture("93 Flight saved directly to map")
        saved.tap()
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 8))
        capture("94 Redesigned flight overview")
        resizeMapPanel(expanded: true)
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
        let from = app.textFields["flight-route-origin"]; from.tap(); from.typeText("JFK")
        app.buttons["flight-step-continue"].tap()
        let to = app.textFields["flight-route-destination"]; XCTAssertTrue(to.waitForExistence(timeout: 5)); XCTAssertFalse(from.exists)
        to.tap(); to.typeText("LHR")
        app.buttons["flight-step-continue"].tap()
        app.buttons["flight-find"].tap()
        reveal(result); XCTAssertTrue(result.waitForExistence(timeout: 5)); capture("74 Flight route search")
        app.buttons["flight-add-cancel"].tap()
        app.tabBars.buttons["Travel"].tap(); app.tabBars.buttons["Map"].tap()
        XCTAssertEqual(expand.frame.minY, compactY, accuracy: 2)
        XCTAssertEqual(app.tabBars.firstMatch.frame.minY, originalBar.minY, accuracy: 2)
    }
    func testZFlightPagesKeepInputAndSupportLargeText() {
        defer { app.terminate(); app.launchArguments = ["--ui-testing", "--map-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]; app.launch() }
        app.terminate()
        app.launchArguments = ["--ui-testing", "--map-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        let map = app.tabBars.buttons["Map"]; XCTAssertTrue(map.waitForExistence(timeout: 8)); map.tap()
        let section = app.buttons["map-section-Flights"]; XCTAssertTrue(section.waitForExistence(timeout: 8)); section.tap()
        XCTAssertLessThan(section.frame.height, 65, "Navigation labels must not wrap at accessibility sizes")
        XCTAssertLessThan(app.buttons["map-add-flight"].frame.height, 65, "The add action must remain compact")
        resizeMapPanel(expanded: true)
        let add = app.buttons["map-add-flight"]; XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let airline = app.textFields["flight-airline-query"]; XCTAssertTrue(airline.waitForExistence(timeout: 5)); airline.tap(); airline.typeText("BA")
        let british = app.buttons["flight-airline-BA"]; reveal(british); british.tap()
        let number = app.textFields["flight-number-query"]; XCTAssertTrue(number.waitForExistence(timeout: 5)); number.tap(); number.typeText("178\n")
        XCTAssertTrue(app.buttons["flight-find"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(number.waitForExistence(timeout: 5)); XCTAssertEqual(number.value as? String, "178")
        capture("95 Flight step keeps input at large text")
        let next = app.buttons["flight-step-continue"]; reveal(next); next.tap()
        let find = app.buttons["flight-find"]; reveal(find); find.tap()
        let result = app.buttons["flight-result-BAW178-ui-test"]; XCTAssertTrue(result.waitForExistence(timeout: 8))
        capture("96 Accessible dark flight result")
        XCTAssertTrue(app.buttons["flight-add-cancel"].isHittable); app.buttons["flight-add-cancel"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5)); flight.tap()
        XCTAssertTrue(app.staticTexts["map-flight-title"].waitForExistence(timeout: 5)); capture("97 Accessible dark flight detail")
        app.buttons["All flights"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
    }
    func testGlobeCitySearchAndGuide() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing"]; app.launch()
        app.tabBars.buttons["Map"].firstMatch.tap(); XCTAssertTrue(app.buttons["map-section-Explore"].waitForExistence(timeout: 8))
        let city = app.textFields["world-city-search"]; XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap(); city.typeText("Lis")
        let suggestion = app.buttons["world-city-search-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        let guide = app.buttons["map-city-guide"]; reveal(guide); XCTAssertTrue(guide.waitForExistence(timeout: 5)); guide.tap()
        XCTAssertTrue(app.buttons["city-save"].waitForExistence(timeout: 5)); capture("67 Map to city guide")
    }
    private func resizeMapPanel(expanded: Bool) {
        let handle = app.descendants(matching: .any).matching(identifier: "map-panel-handle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: expanded ? 0.10 : 0.86)))
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
        reveal(hero); hero.tap()
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
        app.tabBars.buttons["Discover"].tap(); app.buttons["global-search"].tap()
        let offline = app.buttons["hotel-offline-collection"]
        revealHotel(offline); offline.tap()
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
        reveal(app.buttons["hero-hotel"]); app.buttons["hero-hotel"].tap()
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
        reveal(app.buttons["hero-hotel"]); app.buttons["hero-hotel"].tap()
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
    func testCityDirectoryUsesOnePageForCategoriesSavedAndSearch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing", "--hotel-testing"]
        app.launch(); XCTAssertTrue(app.buttons["global-search"].waitForExistence(timeout: 8)); app.buttons["global-search"].tap()
        XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
        app.buttons["explore-city-region"].tap(); app.buttons["Oceania"].tap()
        let sydney = app.buttons["explore-city-Sydney"]; XCTAssertTrue(sydney.waitForExistence(timeout: 5)); sydney.tap()
        XCTAssertTrue(app.navigationBars["City guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["city-book-hotel"].exists); capture("City — unified overview")
        let seeAll = app.buttons["city-see-restaurants"]; revealHotel(seeAll); seeAll.tap()
        XCTAssertTrue(app.navigationBars["City guide"].exists); XCTAssertTrue(app.buttons["city-save"].exists)
        let filters = app.buttons["city-filters"]; revealHotel(filters); filters.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["Cuisine"].exists || app.buttons["Any cuisine"].exists); app.buttons["Done"].tap()
        let result = firstCityResult(); revealHotel(result); XCTAssertTrue(result.waitForExistence(timeout: 5)); capture("City — restaurants in place"); result.tap()
        XCTAssertTrue(app.buttons["explore-place-save"].waitForExistence(timeout: 5)); app.buttons["explore-place-save"].tap(); app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["City guide"].exists)
        let saved = app.buttons["city-saved-places"]; revealHotel(saved); saved.tap()
        XCTAssertEqual(saved.value as? String, "Selected"); XCTAssertTrue(app.navigationBars["City guide"].exists)
        let query = app.textFields["city-place-query"]; revealHotel(query); query.tap(); query.typeText("noresults\n")
        let empty = app.staticTexts["No saved places match this search. Try another interest or reset your filters."]; revealHotel(empty); XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let clear = app.buttons["Clear city search"]; revealHotel(clear); clear.tap()
        revealHotel(saved); saved.tap(); chooseCityInterest("attractions")
        XCTAssertTrue(app.navigationBars["City guide"].exists); XCTAssertTrue(app.buttons["city-all-interests"].label.contains("Things to do")); capture("City — things to do in place")
        // One back action leaves the city, rather than exposing another city page.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(sydney.waitForExistence(timeout: 5))
    }
    func testDiningAndExperiencesEnterTheSameCityPage() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing", "--city-testing", "--hotel-testing"]; app.launch()
        for (category, label) in [("Dining", "Restaurants"), ("Experiences", "Things to do")] {
            app.buttons["category-" + category].tap()
            let query = app.textFields["explore-city-query"]; XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("Lis")
            let city = app.buttons["explore-city-query-suggestion-0"]; XCTAssertTrue(city.waitForExistence(timeout: 5)); city.tap()
            XCTAssertTrue(app.navigationBars["City guide"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["city-save"].exists)
            let booking = app.buttons["city-book-hotel"]; XCTAssertTrue(booking.waitForExistence(timeout: 5)); XCTAssertTrue(booking.isHittable)
            let chooser = app.buttons["city-all-interests"]; revealHotel(chooser); XCTAssertTrue(chooser.label.contains(label))
            chooseCityInterest("highlights"); XCTAssertTrue(app.navigationBars["City guide"].exists)
            app.navigationBars.buttons.firstMatch.tap(); XCTAssertTrue(query.waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
    private func openCityExplorer(fixtures: Bool, createTrip: Bool = false) {
        app.terminate(); app.launchArguments = ["--ui-testing"] + (fixtures ? ["--location-testing", "--city-testing"] : ["--live-apple-places"]); app.launch()
        if createTrip {
            app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
            let field = app.textFields["trip-destination"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Lis")
            XCTAssertTrue(app.buttons["trip-destination-suggestion-0"].waitForExistence(timeout: 5)); app.buttons["trip-destination-suggestion-0"].tap(); app.buttons["journey-save"].tap()
            XCTAssertTrue(app.staticTexts["Trip to Lisbon, Portugal"].waitForExistence(timeout: 5)); app.tabBars.buttons["Discover"].tap()
        }
        let explore = app.buttons["global-search"]; XCTAssertTrue(explore.waitForExistence(timeout: 8)); explore.tap()
        XCTAssertTrue(app.textFields["explore-city-query"].waitForExistence(timeout: 5))
    }
    private func chooseCityInterest(_ interest: String) {
        let chooser = app.buttons["city-all-interests"]; revealHotel(chooser); chooser.tap()
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
        selectTripPlanView("Map"); XCTAssertTrue(app.staticTexts["trip-map-count"].waitForExistence(timeout: 5))
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
        let shortlist = app.buttons["city-saved-places"]
        reveal(shortlist); shortlist.tap()
        XCTAssertEqual(shortlist.value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["Lisbon Museum 1"].exists)
        let query = app.textFields["city-place-query"]; revealHotel(query); query.tap(); query.typeText("noresults\n")
        let empty = app.staticTexts["No saved places match this search. Try another interest or reset your filters."]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        app.buttons["Clear city search"].tap()
        let openMap = app.buttons["city-open-map"]; revealHotel(openMap); XCTAssertTrue(openMap.isHittable); openMap.tap()
        XCTAssertTrue(app.buttons["map-section-Explore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["world-city-search"].value as? String, "Lisbon")
        XCTAssertTrue(app.staticTexts["Lisbon Museum 1"].exists)
        // Opening from a guide inside Map must return to the map root as well.
        app.buttons["map-city-guide"].tap()
        let mapAgain = app.buttons["city-open-map"]
        XCTAssertTrue(mapAgain.waitForExistence(timeout: 5)); mapAgain.tap()
        XCTAssertTrue(app.buttons["map-section-Explore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["world-city-search"].value as? String, "Lisbon")
    }

    private func selectTripPlanView(_ view: String) {
        let selector = app.buttons["trip-plan-view"]
        reveal(selector); selector.tap()
        app.buttons[view].tap()
    }
    private func createAddFlowTrip(fixtures: Bool = true) {
        app.terminate(); app.launchArguments = ["--ui-testing"] + (fixtures ? ["--location-testing"] : ["--live-apple-places"]); app.launch()
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
            if option == "flight" {
                XCTAssertTrue(app.textFields["flight-airline-query"].waitForExistence(timeout: 5))
                app.buttons["flight-add-cancel"].tap()
                XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5))
                app.buttons["journey-add"].tap()
                continue
            }
            XCTAssertTrue(app.buttons[save].waitForExistence(timeout: 5), "No editor for " + option)
            app.buttons["Back"].firstMatch.tap()
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
        app.buttons["flight-manual"].tap()
        let airline = app.textFields["booking-airline"]; XCTAssertTrue(airline.waitForExistence(timeout: 5)); airline.tap(); airline.typeText("Air France\n")
        for identifier in ["booking-departure", "booking-arrival"] {
            let airport = app.textFields[identifier]; reveal(airport); airport.tap(); airport.typeText("Par")
            let suggestion = app.buttons[identifier + "-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
        }
        app.buttons["flight-record-save"].tap(); XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Paris"].tap()
        selectTripPlanView("Map")
        XCTAssertTrue(app.staticTexts["trip-map-count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["trip-map-count"].label, "4 places on your map")
        capture("50 Saved trip map with bookings and meeting")
    }
    func testInlinePlaceSearchKeepsOneEditorAndRepeatDays() {
        createAddFlowTrip()
        for choice in ["place", "hotel", "attraction", "journal"] {
            if choice == "journal" { app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap() }
            else { app.buttons["journey-add"].tap(); app.buttons["add-plan-" + choice].tap() }
            let query = app.textFields["place-name"]
            XCTAssertTrue(query.waitForExistence(timeout: 5))
            let save = choice == "hotel" ? "hotel-record-save" : choice == "journal" ? "rated-save" : "event-save"
            let top = app.buttons[save].frame.minY
            XCTAssertEqual(app.textFields.matching(identifier: "place-name").count, 1)
            XCTAssertFalse(app.buttons["Find a restaurant or place"].exists)
            XCTAssertFalse(app.buttons["Search hotels"].exists)
            XCTAssertFalse(app.textFields["Latitude"].exists)
            XCTAssertFalse(app.textFields["Longitude"].exists)
            XCTAssertFalse(app.textFields["place-address"].exists)
            if choice == "place" { let day = app.buttons["event-day-1"]; reveal(day); day.tap(); reveal(query) }
            query.tap(); query.typeText("Par")
            let suggestion = app.buttons["place-name-suggestion-0"]
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons[save].frame.minY, top, accuracy: 2, "Place search must stay in the same sheet")
            if choice == "place" { capture("76 Inline restaurant search") }
            suggestion.tap()
            XCTAssertEqual(query.value as? String, "Paris Test Hotel")
            XCTAssertTrue(app.staticTexts["place-map-ready"].exists)
            if choice == "place" {
                let day = app.buttons["event-day-1"]; reveal(day)
                XCTAssertEqual(day.value as? String, "Selected")
                capture("77 Restaurant with automatic map details")
            }
            if choice == "hotel" { capture("78 Simplified hotel stay") }
            app.buttons[save].tap()
            XCTAssertTrue(app.buttons[choice == "journal" ? "trip-add-place" : "journey-add"].waitForExistence(timeout: 8))
        }
    }
    func testTripFlightSearchSavesToTripAndMap() {
        createAddFlowTrip()
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state", "--map-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Paris"].tap()
        app.buttons["journey-add"].tap(); app.buttons["add-plan-flight"].tap()
        XCTAssertTrue(app.textFields["flight-airline-query"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["flight-record-save"].exists)
        app.buttons["flight-add-cancel"].tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 5))
        app.buttons["journey-add"].tap(); app.buttons["add-plan-flight"].tap()
        let airline = app.textFields["flight-airline-query"]
        XCTAssertTrue(airline.waitForExistence(timeout: 5)); airline.tap(); airline.typeText("British")
        app.buttons["flight-airline-BA"].tap()
        let number = app.textFields["flight-number-query"]
        XCTAssertTrue(number.waitForExistence(timeout: 5)); number.tap(); number.typeText("178\n")
        XCTAssertTrue(app.buttons["flight-find"].waitForExistence(timeout: 5))
        app.buttons["flight-find"].tap()
        let result = app.buttons["flight-result-BAW178-ui-test"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Tap a flight to add it to your trip."].exists)
        capture("104 Shared flight search from trip")
        result.tap()
        XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["flight-record-save"].exists)
        XCTAssertFalse(app.buttons["add-plan-flight"].exists)
        let booking = app.staticTexts["JFK → LHR"]
        reveal(booking); XCTAssertTrue(booking.waitForExistence(timeout: 5))
        capture("105 Flight saved directly to trip")
        app.terminate(); app.launch()
        app.tabBars.buttons["Travel"].tap(); app.staticTexts["Trip to Paris"].tap()
        reveal(booking); XCTAssertTrue(booking.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "JFK → LHR").count, 1)
        app.navigationBars.buttons["BackButton"].tap()
        app.tabBars.buttons["Map"].firstMatch.tap()
        app.buttons["map-section-Flights"].tap()
        let flight = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).firstMatch
        XCTAssertTrue(flight.waitForExistence(timeout: 5))
        XCTAssertTrue(flight.label.contains("Trip to Paris"))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-flight-")).count, 1)
    }
    func testFlightAirportsStayInline() {
        createAddFlowTrip()
        app.buttons["journey-add"].tap(); app.buttons["add-plan-flight"].tap()
        app.buttons["flight-manual"].tap()
        XCTAssertTrue(app.buttons["flight-record-save"].waitForExistence(timeout: 5))
        let top = app.buttons["flight-record-save"].frame.minY
        XCTAssertFalse(app.buttons["Search flights"].exists)
        for identifier in ["booking-departure", "booking-arrival"] {
            let field = app.textFields[identifier]; reveal(field); field.tap(); field.typeText("Par")
            let suggestion = app.buttons[identifier + "-suggestion-0"]; XCTAssertTrue(suggestion.waitForExistence(timeout: 5)); suggestion.tap()
            XCTAssertEqual(field.value as? String, "Paris Charles de Gaulle Airport")
            XCTAssertEqual(app.buttons["flight-record-save"].frame.minY, top, accuracy: 2)
        }
        XCTAssertFalse(app.textFields["booking-departure-zone"].exists)
        capture("79 Inline flight airports and native times")
    }
    func testLivePlaceAutocompleteResolvesMapLocation() {
        createAddFlowTrip(fixtures: false)
        app.buttons["journey-add"].tap(); capture("48 Stays first add menu"); app.buttons["add-plan-hotel"].tap()
        let field = app.textFields["place-name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("The Savoy London")
        XCTAssertTrue(app.buttons["place-name-suggestion-0"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Google Maps"].exists || app.staticTexts["Apple Maps suggestions"].exists)
        capture("51 Live place suggestions")
        app.buttons["place-name-suggestion-0"].tap()
        XCTAssertTrue(app.staticTexts["place-map-ready"].waitForExistence(timeout: 20))
        capture("52 Resolved Savoy hotel")
        app.buttons["hotel-record-save"].tap(); XCTAssertTrue(app.buttons["journey-add"].waitForExistence(timeout: 8))
        selectTripPlanView("Map")
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
        let more = app.buttons["More details"]; reveal(more); more.tap()
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
        selectTripPlanView("Calendar")
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
        XCTAssertTrue(app.navigationBars["Where did you go?"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal-entry-")).count, 1)
        app.buttons["trip-journal-planned"].tap()
        let plannedPlace = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal-plan-place-")).firstMatch
        XCTAssertTrue(plannedPlace.waitForExistence(timeout: 5)); plannedPlace.tap()
        XCTAssertTrue(app.navigationBars["New journal entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["place-name"].value as? String, "Dinner by the river")
        let notes = app.descendants(matching: .any).matching(identifier: "rated-notes").firstMatch
        reveal(notes); notes.tap(); notes.typeText("A beautiful evening by the water.")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.buttons["trip-add-place"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Dinner by the river"])
        XCTAssertTrue(app.staticTexts["Dinner by the river"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A favourite cafe"].exists)
        XCTAssertTrue(app.staticTexts["A beautiful evening by the water."].exists)
        reveal(app.buttons["trip-journal-planned"]); app.buttons["trip-journal-planned"].tap()
        XCTAssertTrue(plannedPlace.waitForExistence(timeout: 5)); plannedPlace.tap()
        XCTAssertTrue(app.navigationBars["Edit journal entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(notes.value as? String, "A beautiful evening by the water.")
        app.buttons["rated-save"].tap()
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
        let travel = app.tabBars.buttons["Travel"]
        XCTAssertTrue(travel.waitForExistence(timeout: 5)); travel.tap()
        let create = app.buttons["travel-new-trip"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        app.buttons["travel-create-blank"].tap()
        XCTAssertTrue(app.textFields["trip-destination"].waitForExistence(timeout: 5))
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris")
        app.buttons["journey-save"].tap(); app.staticTexts["Trip to Paris"].tap()
        app.buttons["Journal"].tap(); app.buttons["trip-add-place"].tap()
        XCTAssertFalse(app.buttons["rated-save"].isEnabled)
        app.textFields["place-name"].tap(); app.textFields["place-name"].typeText("My favorite table\n")
        let date = app.switches["rated-has-date"]; reveal(date)
        date.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(date.value as? String, "1")
        XCTAssertTrue(app.staticTexts["Visited on"].waitForExistence(timeout: 3))
        let notes = app.descendants(matching: .any).matching(identifier: "rated-notes").firstMatch
        reveal(notes); notes.tap(); notes.typeText("Try the tasting menu next time.")
        let rating = app.steppers["Overall-stepper"]
        reveal(rating)
        XCTAssertTrue(rating.isHittable)
        let increase = rating.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        increase.tap(); increase.tap(); increase.tap()
        capture("18 Personal rating editor")
        let photos = app.buttons["rated-add-photos"]; reveal(photos)
        XCTAssertTrue(photos.isHittable)
        XCTAssertFalse(app.steppers["Food & drink-stepper"].exists)
        capture("107 Simple journal details and photos")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.staticTexts["My favorite table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0.3"].exists)
        XCTAssertTrue(app.staticTexts["Try the tasting menu next time."].exists)
        capture("16 Trip journal")
        let entry = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journal-entry-")).firstMatch
        reveal(entry); entry.tap()
        XCTAssertTrue(app.navigationBars["Edit journal entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(notes.value as? String, "Try the tasting menu next time.")
        XCTAssertEqual(app.switches["rated-has-date"].value as? String, "1")
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
        app.segmentedControls["account-mode"].buttons["Create account"].tap()
        capture("21 Account signup form")
        let handle = app.textFields["account-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5)); handle.tap(); handle.typeText("ui_" + UUID().uuidString.prefix(8).lowercased())
        let displayName = app.textFields["account-name"]
        displayName.tap(); displayName.typeText("Native Test Traveler")
        let password = app.secureTextFields["account-password"]
        password.tap(); password.typeText("Strong-simulator-password-123")
        let confirm = app.secureTextFields["account-confirmation"]; reveal(confirm); confirm.tap(); confirm.typeText("Strong-simulator-password-123")
        reveal(app.buttons["account-submit"]); app.buttons["account-submit"].tap()
        let connected = app.buttons["Sign out"].waitForExistence(timeout: 10)
        capture("22 Account registration result")
        XCTAssertTrue(connected)
        capture("19 Backend account connected")
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.secureTextFields["account-password"].waitForExistence(timeout: 8))
    }
    @MainActor func testGuestCanCreateAccountAndSignInFromProfile() throws {
        let root = "https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api"
        let username = "guest_" + UUID().uuidString.prefix(8).lowercased()
        let passwordValue = "Seur-Travel-" + UUID().uuidString.prefix(12)
        addTeardownBlock {
            var login = URLRequest(url: URL(string: root + "/v1/auth/login")!)
            login.httpMethod = "POST"; login.setValue("application/json", forHTTPHeaderField: "Content-Type")
            login.httpBody = try JSONSerialization.data(withJSONObject: ["handle": username, "password": passwordValue])
            let (data, response) = try await URLSession.shared.data(for: login)
            if (response as? HTTPURLResponse)?.statusCode == 401 { return }
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let token = try XCTUnwrap(body?["token"] as? String)
            var removal = URLRequest(url: URL(string: root + "/v1/account")!); removal.httpMethod = "DELETE"
            removal.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (_, removed) = try await URLSession.shared.data(for: removal)
            XCTAssertEqual((removed as? HTTPURLResponse)?.statusCode, 200)
        }
        let server = ["--travel-test-server", root + "?guest-test=" + username]
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"] + server; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        app.textFields["trip-destination"].tap(); app.textFields["trip-destination"].typeText("Paris\n")
        app.buttons["journey-save"].tap()
        app.tabBars.buttons["Discover"].tap(); app.buttons["Your workspace"].tap()
        XCTAssertTrue(app.buttons["profile-create-account"].waitForExistence(timeout: 8)); capture("89 Guest profile account access")
        app.buttons["profile-create-account"].tap()
        let name = app.textFields["account-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Avery Traveler")
        app.keyboards.buttons["next"].tap()
        let handle = app.textFields["account-handle"]; handle.typeText(username)
        app.keyboards.buttons["next"].tap(); dismissStrongPasswordIfNeeded()
        let password = app.secureTextFields["account-password"]
        for character in passwordValue { password.typeText(String(character)) }
        app.keyboards.buttons["next"].tap(); dismissStrongPasswordIfNeeded()
        let confirm = app.secureTextFields["account-confirmation"]; confirm.typeText("does-not-match")
        let submit = app.buttons["account-submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.staticTexts["account-message"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["account-message"].label.contains("don’t match"))
        reveal(confirm); confirm.tap(); confirm.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 14))
        for character in passwordValue { confirm.typeText(String(character)) }
        reveal(submit); capture("90 Create a Seur account"); submit.tap(); dismissSavePasswordIfNeeded()
        XCTAssertTrue(app.staticTexts["account-success"].waitForExistence(timeout: 25), app.staticTexts["account-message"].exists ? app.staticTexts["account-message"].label : "No account response")
        capture("91 Guest account created")
        app.buttons["account-continue"].tap(); XCTAssertTrue(app.buttons["profile-account"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.staticTexts["Trip to Paris"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-state", "--location-testing"] + server; app.launch()
        app.buttons["Your workspace"].tap()
        XCTAssertTrue(app.buttons["profile-account"].waitForExistence(timeout: 15), "Session must restore from Keychain")
        app.buttons["profile-account"].tap(); app.buttons["Sign out"].tap()
        XCTAssertTrue(handle.waitForExistence(timeout: 8))
        handle.tap(); handle.typeText(username); app.keyboards.buttons["next"].tap()
        password.typeText("wrong-password-value"); reveal(submit); submit.tap()
        XCTAssertTrue(app.staticTexts["account-message"].waitForExistence(timeout: 15))
        reveal(password); password.tap(); password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + passwordValue)
        reveal(submit); capture("92 Sign in after onboarding"); submit.tap(); dismissSavePasswordIfNeeded()
        XCTAssertTrue(app.staticTexts["account-success"].waitForExistence(timeout: 25))
    }
    func testAccountFullPageDesign() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--travel-test-server", "http://127.0.0.1:1"]; app.launch()
        app.tabBars.buttons["Travel"].tap()
        app.buttons["Travel account"].tap()
        XCTAssertTrue(app.buttons["account-email-option"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["account-email"].exists)
        XCTAssertFalse(app.segmentedControls["account-mode"].exists)
        let google = app.buttons["account-google"], apple = app.buttons["account-apple"]
        XCTAssertTrue(google.exists); XCTAssertTrue(google.isEnabled); XCTAssertTrue(apple.isEnabled)
        let googleFrame = google.frame
        capture("Account welcome — stable provider buttons")
        google.tap()
        XCTAssertTrue(app.staticTexts["account-message"].waitForExistence(timeout: 12))
        XCTAssertTrue(google.isEnabled)
        XCTAssertEqual(google.frame.minY, googleFrame.minY, accuracy: 1)
        XCTAssertEqual(google.frame.height, googleFrame.height, accuracy: 1)
        app.buttons["account-email-option"].tap()
        XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
        capture("Account email sign-in")
        let mode = app.buttons["account-mode-link"]; reveal(mode); mode.tap()
        XCTAssertTrue(app.textFields["account-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["account-handle"].exists)
        XCTAssertFalse(app.secureTextFields["account-confirmation"].exists)
        XCTAssertFalse(app.textFields["account-email"].exists)
        XCTAssertFalse(app.secureTextFields["account-password"].exists)
        capture("Account registration — profile step")
        reveal(mode); mode.tap()
        XCTAssertFalse(app.textFields["account-name"].exists)
        let other = app.buttons["account-other-options"]; reveal(other); other.tap()
        XCTAssertTrue(google.waitForExistence(timeout: 5)); XCTAssertTrue(google.isEnabled)
        XCTAssertFalse(app.buttons["account-mode-link"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 5))
    }
    func testAccountAccessAtLargeText() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--travel-test-server", "http://127.0.0.1:1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["Travel account"].tap()
        let emailOption = app.buttons["account-email-option"]
        XCTAssertTrue(emailOption.waitForExistence(timeout: 8)); reveal(emailOption)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        emailOption.tap()
        XCTAssertTrue(app.textFields["account-email"].waitForExistence(timeout: 5))
        let mode = app.buttons["account-mode-link"]; reveal(mode); mode.tap()
        let name = app.textFields["account-name"], handle = app.textFields["account-handle"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); reveal(name); XCTAssertTrue(name.isHittable)
        name.tap(); name.typeText("Jamie")
        reveal(handle); handle.tap(); handle.typeText("jamie_travels")
        let submit = app.buttons["account-submit"]; reveal(submit); XCTAssertTrue(submit.isHittable)
        capture("Account profile — accessibility text")
        submit.tap()
        let email = app.textFields["account-email"]; XCTAssertTrue(email.waitForExistence(timeout: 5))
        reveal(email); email.tap(); email.typeText("jamie@example.com")
        reveal(submit); XCTAssertTrue(submit.isHittable); capture("Account email — accessibility text"); submit.tap()
        let password = app.secureTextFields["account-password"]; XCTAssertTrue(password.waitForExistence(timeout: 5))
        reveal(password); XCTAssertTrue(password.isHittable)
        reveal(submit); XCTAssertTrue(submit.isHittable); capture("Account password — accessibility text")
        app.buttons["Done"].tap(); XCTAssertTrue(app.buttons["travel-create"].waitForExistence(timeout: 5))
    }
    func testOnboardingUsesVerifiedAccountFlow() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--onboarding-testing", "--travel-test-server", "http://127.0.0.1:1"]; app.launch()
        app.buttons["onboarding-sign-in"].tap()
        XCTAssertTrue(app.buttons["account-email-option"].waitForExistence(timeout: 8))
        app.buttons["account-email-option"].tap()
        let mode = app.buttons["account-mode-link"]; reveal(mode); mode.tap()
        let name = app.textFields["account-name"], handle = app.textFields["account-handle"]
        let next = app.buttons["account-submit"], back = app.buttons["account-step-back"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["account-email"].exists)
        XCTAssertFalse(app.secureTextFields["account-password"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["account-message"].waitForExistence(timeout: 3))
        name.tap(); name.typeText("Jamie Traveller")
        handle.tap(); handle.typeText("jamie_travels")
        reveal(next); next.tap()
        let email = app.textFields["account-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertFalse(name.exists); XCTAssertFalse(app.secureTextFields["account-password"].exists)
        capture("Onboarding account — email step")
        next.tap()
        XCTAssertTrue(app.staticTexts["account-message"].exists)
        email.tap(); email.typeText("jamie@example.com")
        reveal(next); next.tap()
        let password = app.secureTextFields["account-password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        XCTAssertFalse(email.exists); XCTAssertFalse(name.exists)
        capture("Onboarding account — password step")
        next.tap()
        XCTAssertTrue(app.staticTexts["account-message"].exists)
        password.tap(); password.typeText("sample-password-123")
        back.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertEqual(email.value as? String, "jamie@example.com")
        back.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Jamie Traveller")
        XCTAssertEqual(handle.value as? String, "jamie_travels")
        capture("Onboarding account — profile step")
        next.tap(); XCTAssertTrue(email.waitForExistence(timeout: 5))
        next.tap(); XCTAssertTrue(password.waitForExistence(timeout: 5))
        app.buttons["Show password"].tap()
        XCTAssertEqual(app.textFields["account-password"].value as? String, "sample-password-123")
        app.buttons["Hide password"].tap()
        next.tap()
        // No external account is created: the isolated server is deliberately unreachable.
        XCTAssertTrue(app.staticTexts["account-message"].waitForExistence(timeout: 12))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(back.isEnabled)
        app.buttons["onboarding-account-skip"].tap()
        XCTAssertTrue(app.buttons["membership-preview"].waitForExistence(timeout: 5))
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
    func testConciergeChatAndPlanSave() {
        app.terminate(); app.launchArguments.append("--concierge-testing"); app.launch()
        app.tabBars.buttons["Concierge"].tap()
        let prompt = app.buttons["concierge-prompt-calendar"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5)); prompt.tap()
        let review = app.buttons["concierge-review-plan"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        if !review.isHittable { app.swipeUp() }
        review.tap()
        let save = app.buttons["concierge-save-plan"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(app.buttons["Added to your trips"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Travel"].tap()
        XCTAssertTrue(app.staticTexts["A thoughtful Paris weekend"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Concierge"].tap()
        app.buttons["New conversation"].tap(); app.buttons["Clear this conversation"].tap()
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
        finishNotificationOnboarding()
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
        finishNotificationOnboarding()
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
        let dining = app.buttons["interest-1"]
        XCTAssertTrue(dining.waitForExistence(timeout: 5)); reveal(dining)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4)) // Let the welcome transition finish before selecting.
        dining.tap()
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
        finishNotificationOnboarding()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
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
    private func finishNotificationOnboarding() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        if prompt.waitForExistence(timeout: 3) {
            let deny = prompt.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Don")).firstMatch
            if deny.exists { deny.tap() }
        }
        let next = app.buttons["onboarding-notifications-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
    }
    func testOnboardingNotificationPromptAutomaticallyAppearsAndDenialCanContinue() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SEUR_NOTIFICATION_PROMPT_TEST"] == "1", "Requires a fresh simulator for the system permission prompt")
        beginOnboarding()
        app.buttons["onboarding-explore"].tap()
        XCTAssertTrue(app.buttons["membership-skip"].waitForExistence(timeout: 5)); app.buttons["membership-skip"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "A fresh simulator must show the permission prompt without tapping Enable")
        let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Don")).firstMatch
        XCTAssertTrue(deny.exists); deny.tap()
        let settings = app.buttons["onboarding-notification-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        capture("Onboarding notifications — declined")
        app.buttons["onboarding-notifications-back"].tap()
        XCTAssertTrue(app.buttons["membership-skip"].waitForExistence(timeout: 5)); app.buttons["membership-skip"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertFalse(alert.exists)
        app.terminate(); app.launchArguments += ["--preserve-state"]; app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); XCTAssertFalse(alert.exists)
        app.buttons["onboarding-notifications-continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-notifications-continue"].exists)
    }
    func testOnboardingSkipWithoutSubscription() {
        beginOnboarding()
        app.buttons["onboarding-explore"].tap()
        reveal(app.buttons["membership-restore"]); app.buttons["membership-restore"].tap()
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No preview has been saved'")).firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["membership-skip"].tap()
        finishNotificationOnboarding()
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
        XCTAssertTrue(app.buttons["onboarding-notifications-continue"].waitForExistence(timeout: 5))
        capture("Onboarding notifications — accessibility text")
        finishNotificationOnboarding()
        XCTAssertTrue(app.tabBars.buttons["Discover"].waitForExistence(timeout: 5))
    }

    func testSimpleTripCreationBuildsRouteAutomatically() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--location-testing"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-new-trip"].tap()
        app.buttons["travel-create-blank"].tap()
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
        XCTAssertEqual(app.segmentedControls.count, 0)
        let add = app.buttons["journey-add"]
        XCTAssertEqual(add.value as? String, "Expanded")
        capture("47 Automatically prepared trip")
        let scroll = app.scrollViews["journey-scroll"]
        scroll.swipeUp()
        let collapsed = expectation(for: NSPredicate(format: "value == %@", "Compact"), evaluatedWith: add)
        wait(for: [collapsed], timeout: 3)
        capture("101 Compact trip add button")
        add.tap()
        XCTAssertTrue(app.buttons["add-plan-hotel"].waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        for _ in 0..<5 { if add.value as? String == "Expanded" { break }; scroll.swipeDown() }
        XCTAssertEqual(add.value as? String, "Expanded")
        XCTAssertFalse(app.buttons["Calendar"].exists)
        selectTripPlanView("Calendar")
        XCTAssertTrue(app.buttons["Plan"].isSelected)
        XCTAssertEqual(app.buttons["trip-plan-view"].value as? String, "Calendar")
        selectTripPlanView("Map")
        XCTAssertTrue(app.staticTexts["trip-map-count"].waitForExistence(timeout: 5))
        app.buttons["Journal"].tap()
        XCTAssertTrue(app.buttons["trip-add-place"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["trip-plan-view"].exists)
        XCTAssertTrue(app.staticTexts["Your visits & memories"].exists)
        capture("106 Journal visits and memories")
        app.buttons["Plan"].tap()
        XCTAssertEqual(app.buttons["trip-plan-view"].value as? String, "Map")
        selectTripPlanView("List")
        app.buttons["journey-menu"].tap(); app.buttons["Edit journey"].tap()
        XCTAssertEqual(app.textFields["journey-name"].value as? String, "Trip to Paris, France")
        let savedStop = app.collectionViews.staticTexts["Paris, France"]
        reveal(savedStop); savedStop.tap()
        XCTAssertEqual(app.textFields["stop-country"].value as? String, "France")
        app.buttons["stop-save"].tap(); app.buttons["journey-save"].tap()
    }
    func testLondonDestinationPrioritizesEnglandAndSaves() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--live-apple-places"]; app.launch()
        app.tabBars.buttons["Travel"].tap(); app.buttons["travel-create"].tap()
        let destination = app.textFields["trip-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5)); destination.tap(); destination.typeText("London")
        let suggestion = app.buttons["trip-destination-suggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(suggestion.label.contains("England, United Kingdom"))
        capture("London destination ranking")
        suggestion.tap()
        XCTAssertEqual(destination.value as? String, "London, United Kingdom")
        app.buttons["journey-save"].tap()
        XCTAssertTrue(app.staticTexts["Trip to London, United Kingdom"].waitForExistence(timeout: 5))
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
        app.terminate(); app.launchArguments = ["--ui-testing", "--live-apple-places"]; app.launch()
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
        XCTAssertTrue(app.staticTexts["10 Avenue Example, Paris, France"].exists)
        XCTAssertTrue(app.staticTexts["place-map-ready"].exists)
        XCTAssertFalse(app.textFields["place-address"].exists)
        XCTAssertFalse(app.buttons["Map coordinates"].exists)
        capture("37 Autocomplete place details")
        app.buttons["rated-save"].tap()
        XCTAssertTrue(app.staticTexts["Paris Test Hotel"].waitForExistence(timeout: 5))
    }

}
