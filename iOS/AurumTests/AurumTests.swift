import XCTest
@testable import Aurum

@MainActor final class AurumTests: XCTestCase {
    func testSavedTravelerRequiresCompleteDetailsAndMatchingRateNationality() throws {
        var profile = SavedTravelerProfile(firstName: "Test", lastName: "Traveler", email: "test@example.test", phone: "+12125550123", nationality: "CA")
        var stay = HotelStayPreferences(); stay.checkIn = Date(); stay.checkOut = Date().addingTimeInterval(86400); stay.guestNationality = "US"
        XCTAssertTrue(profile.valid); XCTAssertFalse(profile.canUse(for: try XCTUnwrap(HotelRateCriteria(stay))))
        stay.guestNationality = "CA"; XCTAssertTrue(profile.canUse(for: try XCTUnwrap(HotelRateCriteria(stay))))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(TravelerProfileWrite(profile))) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["expectedVersion", "isDefault", "firstName", "lastName", "email", "phone", "nationality"]))
        profile.nationality = "XX"; XCTAssertFalse(profile.valid)
        profile.nationality = "CA"; profile.email = "bad"; XCTAssertFalse(profile.valid)
    }
    func testSavedTravelerNationalityChangeInvalidatesPrices() throws {
        let model = HotelSearchModel(); model.stay.checkIn = Date(); model.stay.checkOut = Date().addingTimeInterval(86400); model.stay.guestNationality = "US"
        model.rates.criteria = try XCTUnwrap(HotelRateCriteria(model.stay)); model.rates.results["old"] = .init(hotelId: "old", offers: [], status: "unavailable")
        model.stay.travelerID = UUID().uuidString; model.stay.guestNationality = "CA"
        XCTAssertTrue(model.rates.results.isEmpty); XCTAssertNil(model.rates.criteria)
        XCTAssertEqual(try XCTUnwrap(HotelRateCriteria(model.stay)).guestNationality, "CA")
    }
    func testSavedTravelerLoadCannotRestoreDetailsAfterSignOutOrMutation() async {
        let profiles = TravelerProfilesStore()
        let p = SavedTravelerProfile(firstName: "Test", lastName: "Traveler", email: "test@example.test", phone: "+12125550123", nationality: "US")
        await profiles.load { profiles.clear(); return .init(profiles: [p]) }
        XCTAssertTrue(profiles.profiles.isEmpty); XCTAssertFalse(profiles.loading)
        await profiles.load { profiles.replace([p]); return .init(profiles: []) }
        XCTAssertEqual(profiles.profiles, [p]); XCTAssertFalse(profiles.loading)
        profiles.clear(); XCTAssertNil(profiles.defaultProfile); XCTAssertNil(profiles.error)
    }
    func testBookingFiltersKeepUnverifiedConfirmationsOutOfConfirmed() throws {
        let rows = try HotelCheckoutFixtures.servicingExamples()
        for filter in HotelBookingFilter.allCases where filter != .all { XCTAssertEqual(rows.filter(filter.matches).count, filter == .confirmed ? 3 : filter == .cancelled ? 0 : 1) }
        XCTAssertTrue(rows[0].matchesBookingSearch("testa TEST-SEUR-001")); XCTAssertFalse(rows[0].matchesBookingSearch("unknown"))
        var invalid = rows[0]; invalid.booking = nil
        XCTAssertFalse(HotelBookingFilter.confirmed.matches(invalid)); XCTAssertTrue(HotelBookingFilter.attention.matches(invalid))
        invalid = rows[0]; invalid.environment = "production"
        XCTAssertFalse(invalid.confirmed); XCTAssertEqual(invalid.paymentDescription, "Payment status not verified")
        XCTAssertFalse(invalid.shareSummary.contains("Charged: nothing"))
    }
    func testCancellationIntentExpiresAndPendingRemainsRecoverable() throws {
        var value = try HotelCheckoutFixtures.servicingExamples()[0]
        value.cancellation = .init(state: "review", version: UUID().uuidString, expiresAt: Date().addingTimeInterval(120).ISO8601Format(), checkedAt: Date().ISO8601Format())
        XCTAssertTrue(value.cancellation!.canConfirm); XCTAssertFalse(value.cancellation!.pending)
        value.cancellation?.expiresAt = "2000-01-01T00:00:00Z"; XCTAssertFalse(value.cancellation!.canConfirm)
        value.cancellation?.state = "pending"; XCTAssertTrue(value.cancellation!.pending); XCTAssertTrue(HotelBookingFilter.pending.matches(value))
        XCTAssertEqual(value.title, "Cancelling test booking")
        value.cancellation?.state = "needs_support"; XCTAssertTrue(HotelBookingFilter.attention.matches(value))
        XCTAssertEqual(value.title, "Cancellation needs attention")
        value.state = "cancelled"; value.cancellation?.state = "cancelled"; value.review.providerStatus = "CANCELLED_WITH_CHARGES"; value.review.providerCheckedAt = Date().ISO8601Format()
        XCTAssertTrue(value.cancelled); XCTAssertFalse(value.confirmed)
        let restored = try JSONDecoder().decode(HotelCheckout.self, from: JSONEncoder().encode(value)); XCTAssertTrue(restored.cancelled)
    }
    func testProviderCancellationRequiresEvidenceAndCannotAppearUpcoming() throws {
        var value = try HotelCheckoutFixtures.servicingExamples()[0]
        value.state = "cancelled"; XCTAssertFalse(value.cancelled)
        value.review.providerStatus = "CANCELLED"; value.review.providerCheckedAt = Date().ISO8601Format()
        XCTAssertTrue(value.cancelled); XCTAssertEqual(value.title, "Test booking cancelled")
        XCTAssertFalse(value.confirmed); XCTAssertNil(value.stayPeriod(today: "2026-09-12"))
        XCTAssertTrue(HotelBookingFilter.cancelled.matches(value)); XCTAssertFalse(HotelBookingFilter.attention.matches(value))
        XCTAssertFalse(value.shareSummary.contains("SANDBOX TEST RECEIPT")); XCTAssertTrue(value.shareSummary.contains("Test booking cancelled"))
    }
    func testBookingPeriodsUseStayDatesAndRequireVerifiedConfirmation() throws {
        var value = try HotelCheckoutFixtures.servicingExamples()[0]
        value.review.criteria.checkin = "2026-10-10"; value.review.criteria.checkout = "2026-10-13"
        XCTAssertEqual(value.stayPeriod(today: "2026-10-09"), .upcoming)
        XCTAssertEqual(value.stayPeriod(today: "2026-10-10"), .current)
        XCTAssertEqual(value.stayPeriod(today: "2026-10-12"), .current)
        XCTAssertEqual(value.stayPeriod(today: "2026-10-13"), .past)
        XCTAssertFalse(HotelBookingFilter.upcoming.matches(value, today: "2026-10-10"))
        for state in ["needs_support", "pending_confirmation", "expired", "cancelled"] {
            value.state = state
            XCTAssertNil(value.stayPeriod(today: "2026-10-09"))
            XCTAssertFalse(HotelBookingFilter.past.matches(value, today: "2026-10-14"))
        }
        value.state = "confirmed"; value.booking = nil
        XCTAssertNil(value.stayPeriod(today: "2026-10-09"))
    }
    func testBookingPeriodsRejectInvalidDatesAndHandleLeapDays() throws {
        var value = try HotelCheckoutFixtures.servicingExamples()[0]
        value.review.criteria.checkin = "2028-02-28"; value.review.criteria.checkout = "2028-03-01"
        XCTAssertEqual(value.stayPeriod(today: "2028-02-29"), .current)
        for bad in ["2026-02-30", "2026-2-02", "unknown", "2028-03-01", "2028-03-02"] {
            value.review.criteria.checkin = bad
            XCTAssertNil(value.stayPeriod(today: "2028-02-29"))
        }
        value.review.criteria.checkin = "2028-02-28"
        XCTAssertNil(value.stayPeriod(today: "2026-02-29"))
    }
    func testBookingOrderingPrioritizesAttentionAndSortsStayDates() throws {
        let examples = try HotelCheckoutFixtures.servicingExamples(), today = TravelDay.key(.now)
        let ordered = HotelBookingFilter.all.results(examples, query: "", today: today)
        XCTAssertEqual(ordered.map(\.id), [examples[2], examples[1], examples[5], examples[0], examples[4], examples[3]].map(\.id))
        var nearer = examples[0]; nearer.id = "nearer"; nearer.review.criteria.checkin = TravelDay.adding(4, to: today)
        var older = examples[4]; older.id = "older"; older.review.criteria.checkin = TravelDay.adding(-30, to: today); older.review.criteria.checkout = TravelDay.adding(-27, to: today)
        XCTAssertEqual(HotelBookingFilter.upcoming.results([examples[0], nearer], query: "", today: today).map(\.id), [nearer.id, examples[0].id])
        XCTAssertEqual(HotelBookingFilter.past.results([older, examples[4]], query: "", today: today).map(\.id), [examples[4].id, older.id])
        XCTAssertEqual(HotelBookingFilter.past.results(examples, query: "TEST-SEUR-PAST", today: today).map(\.id), [examples[4].id])
        XCTAssertTrue(HotelBookingFilter.upcoming.results(examples, query: "TEST-SEUR-PAST", today: today).isEmpty)
    }
    func testBookingSummaryWhitelistsReceiptDetailsAndLabelsUnresolvedTerms() throws {
        var rows = try HotelCheckoutFixtures.servicingExamples()
        rows[0].review.offer.quote = "SECRET-QUOTE"; rows[0].quoteVersion = "PRIVATE-VERSION"
        let receipt = rows[0].shareSummary
        XCTAssertTrue(receipt.contains("SANDBOX TEST RECEIPT")); XCTAssertTrue(receipt.contains("TEST-SEUR-001")); XCTAssertTrue(receipt.contains("Breakfast included")); XCTAssertTrue(receipt.contains("City tax"))
        XCTAssertFalse(receipt.contains("SECRET-QUOTE")); XCTAssertFalse(receipt.contains("PRIVATE-VERSION")); XCTAssertFalse(receipt.contains("guestNationality"))
        let support = rows[2].shareSummary
        XCTAssertTrue(support.contains("SUPPORT SUMMARY")); XCTAssertTrue(support.contains("Requested stay details")); XCTAssertTrue(support.contains("TEST-SUPPORT-003")); XCTAssertFalse(support.contains("Provider booking:"))
    }
    func testBookingsLoadingDiscardsResponseAfterAccountClear() async throws {
        let model = HotelBookingsModel(), examples = try HotelCheckoutFixtures.servicingExamples()
        var continuation: CheckedContinuation<HotelCheckoutList, Never>?
        let work = Task { await model.load { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        model.clear(); continuation?.resume(returning: .init(checkouts: examples)); await work.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.loading); XCTAssertNil(model.error)
        await model.load { .init(checkouts: [examples[0], examples[0]]) }; XCTAssertEqual(model.rows.count, 1)
    }
    func testHistoryPaginationRetainsRowsAfterFailureAndMergesRetry() async throws {
        let model = HotelBookingsModel(), values = try HotelCheckoutFixtures.servicingExamples()
        await model.load { .init(checkouts: [values[0]], nextCursor: "page2") }
        await model.loadMore { _ in throw JourneyError.message("Offline") }
        XCTAssertEqual(model.rows.count, 1); XCTAssertEqual(model.nextCursor, "page2"); XCTAssertNotNil(model.moreError)
        await model.loadMore { cursor in XCTAssertEqual(cursor, "page2"); return .init(checkouts: [values[0], values[1]], nextCursor: "page3") }
        XCTAssertEqual(model.rows.count, 2); XCTAssertNil(model.moreError)
        await model.loadMore { _ in .init(checkouts: [values[2]]) }
        XCTAssertEqual(model.rows.count, 3); XCTAssertNil(model.nextCursor)
        await model.loadMore { _ in XCTFail("Must not fetch beyond final page"); return .init(checkouts: []) }
        await model.refreshRecord(values[1].id) { var updated = values[1]; updated.state = "needs_support"; return updated }
        XCTAssertEqual(model.rows.count,3); XCTAssertEqual(model.rows[1].state,"needs_support")
    }
    func testHistoryPaginationIgnoresStalePageAndDuplicateTap() async throws {
        let model = HotelBookingsModel(), values = try HotelCheckoutFixtures.servicingExamples()
        await model.load { .init(checkouts: [values[0]], nextCursor: "older") }
        var continuation: CheckedContinuation<HotelCheckoutList, Never>?
        let work = Task { await model.loadMore { _ in await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        await model.loadMore { _ in XCTFail("Duplicate page request"); return .init(checkouts: []) }
        await model.load { .init(checkouts: [values[2]], nextCursor: "refreshed") }
        continuation?.resume(returning: .init(checkouts: [values[1]], nextCursor: "stale")); await work.value
        XCTAssertEqual(model.rows.map(\.id), [values[2].id]); XCTAssertEqual(model.nextCursor,"refreshed")
        await model.loadMore { _ in .init(checkouts: [], nextCursor: "refreshed") }
        XCTAssertNotNil(model.moreError); XCTAssertEqual(model.rows.count,1)
        model.clear(); XCTAssertNil(model.nextCursor); XCTAssertNil(model.moreError)
    }
    func testHistoryAccountClearDiscardsOlderPage() async throws {
        let model = HotelBookingsModel(), values = try HotelCheckoutFixtures.servicingExamples()
        await model.load { .init(checkouts: [values[0]], nextCursor: "older") }
        var continuation: CheckedContinuation<HotelCheckoutList, Never>?
        let work = Task { await model.loadMore { _ in await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        model.clear(); continuation?.resume(returning: .init(checkouts: [values[1]], nextCursor: "more")); await work.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertNil(model.nextCursor); XCTAssertFalse(model.loadingMore)
    }
    func testHotelFiltersUseKnownTotalsMatchingCurrencyAndUnexpiredOffers() throws {
        var stay = HotelStayPreferences(); stay.guestNationality = "US"
        stay.checkIn = Calendar.current.startOfDay(for: .now); stay.checkOut = Calendar.current.date(byAdding: .day, value: 3, to: stay.checkIn!)
        let page = try HotelRateFixtures.page(ids: ["liteapi:lpfixture0"], criteria: XCTUnwrap(HotelRateCriteria(stay)), detail: true)
        var offer = try XCTUnwrap(page.hotels.first?.offers.first)
        var filters = HotelResultFilters(); filters.minimumPrice = 540; filters.maximumPrice = 540
        XCTAssertTrue(filters.matches(offer, currency: "USD"))
        filters.maximumPrice = 539; XCTAssertFalse(filters.matches(offer, currency: "USD"))
        filters.maximumPrice = 600; XCTAssertFalse(filters.matches(offer, currency: "EUR"))
        offer.total = nil; XCTAssertFalse(filters.matches(offer, currency: "USD"))
        filters = HotelResultFilters(); filters.breakfast = true
        XCTAssertFalse(filters.matches(offer, currency: "USD"))
        let breakfast = try XCTUnwrap(page.hotels.first?.offers.last); XCTAssertTrue(filters.matches(breakfast, currency: "USD"))
        filters.freeCancellation = true; XCTAssertTrue(filters.matches(breakfast, currency: "USD"))
        offer = breakfast; offer.expiresAt = "2000-01-01T00:00:00Z"; XCTAssertFalse(filters.matches(offer, currency: "USD"))
    }
    func testHotelFiltersRejectMissingMetadataAndKeepProviderAverage() throws {
        var hotel = HotelFixtures.hotel(); var filters = HotelResultFilters()
        XCTAssertEqual(hotel.guestRating, 9.4)
        filters.minimumRating = 9; filters.minimumReviews = 500; filters.minimumStars = 5; filters.photosOnly = true
        XCTAssertTrue(filters.matches(hotel, destination: nil))
        hotel.reviewCount = nil; XCTAssertFalse(filters.matches(hotel, destination: nil)); XCTAssertEqual(hotel.guestRating, 9.4)
        hotel.reviewCount = 0; XCTAssertNil(hotel.guestRating)
        hotel.rating = .nan; XCTAssertNil(hotel.guestRating)
        hotel = HotelFixtures.hotel(); filters.maximumDistanceKM = 1
        XCTAssertFalse(filters.matches(hotel, destination: nil))
        let city = ExploreCity(name: "Rome", country: "Italy", latitude: hotel.latitude!, longitude: hotel.longitude!)
        XCTAssertTrue(filters.matches(hotel, destination: city))
        hotel.latitude = nil; XCTAssertFalse(filters.matches(hotel, destination: city))
    }
    func testHotelFilteredCardAndResultUseTheSameEligibleOffer() throws {
        let model = HotelSearchModel(); model.stay.checkIn = Calendar.current.startOfDay(for: .now); model.stay.checkOut = Calendar.current.date(byAdding: .day, value: 3, to: model.stay.checkIn!)
        let hotel = HotelFixtures.hotel(); model.hotels = [hotel]
        let criteria = try XCTUnwrap(HotelRateCriteria(model.stay)); let page = try HotelRateFixtures.page(ids: [hotel.id], criteria: criteria, detail: true)
        model.rates.criteria = criteria; model.rates.expiresAt = page.expiresAt; model.rates.results[hotel.id] = page.hotels.first
        model.filters.breakfast = true
        XCTAssertEqual(model.results.count, 1); XCTAssertEqual(model.matchingRate(for: hotel)?.offers.first?.total?.amount, "640.00")
        model.filters.maximumPrice = 600; XCTAssertTrue(model.results.isEmpty)
        model.stay.currency = "EUR"; XCTAssertNil(model.filters.maximumPrice); XCTAssertTrue(model.results.isEmpty)
    }
    func testHotelCheckoutGuestRequiresCountryCodeAndValidContact() {
        var guest = HotelCheckoutGuest(firstName: "Test", lastName: "Guest", email: "test@example.test", phone: "+12125550123")
        XCTAssertTrue(guest.valid)
        guest.phone = "2125550123"; XCTAssertFalse(guest.valid)
        guest.phone = "+12125550123"; guest.email = "invalid"; XCTAssertFalse(guest.valid)
        guest.email = "test@example.test"; guest.firstName = "<Test>"; XCTAssertFalse(guest.valid)
    }
    @MainActor func testHotelCheckoutNeverConfirmsFromAStatusStringAlone() throws {
        var stay = HotelStayPreferences(); stay.checkIn = Date(); stay.checkOut = Date().addingTimeInterval(86400); stay.guestNationality = "US"
        let criteria = try XCTUnwrap(HotelRateCriteria(stay))
        let offer = try XCTUnwrap(HotelRateFixtures.page(ids: ["liteapi:lpfixture0"], criteria: criteria, detail: false).hotels.first?.offers.first)
        let review = HotelQuoteReview(offer: offer, criteria: criteria, environment: "sandbox", checkoutEnabled: true)
        var checkout = HotelCheckout(id: UUID().uuidString, state: "confirmed", environment: "sandbox", paymentState: "test_no_charge", quoteVersion: UUID().uuidString, review: review, expiresAt: offer.expiresAt, createdAt: offer.expiresAt)
        XCTAssertFalse(checkout.confirmed)
        checkout.booking = .init(id: "TEST-1", hotelName: "Test hotel", confirmedAt: offer.expiresAt); XCTAssertTrue(checkout.confirmed)
        checkout.environment = "production"; XCTAssertFalse(checkout.confirmed)
        checkout.state = "pending_confirmation"; XCTAssertTrue(checkout.canPoll); XCTAssertFalse(checkout.confirmed)
        checkout.state = "review"; checkout.expiresAt = "2000-01-01T00:00:00Z"; XCTAssertTrue(checkout.expired)
        let decoded = try JSONDecoder().decode(HotelCheckout.self, from: JSONEncoder().encode(checkout)); XCTAssertEqual(decoded.id, checkout.id)
    }
    @MainActor func testHotelRateCriteriaUseExplicitNationalityRoomAllocationAndChildAges() throws {
        var stay = HotelStayPreferences()
        stay.checkIn = Calendar.current.startOfDay(for: .now); stay.checkOut = Calendar.current.date(byAdding: .day, value: 3, to: stay.checkIn!)
        XCTAssertNil(HotelRateCriteria(stay))
        stay.guestNationality = "US"; XCTAssertNotNil(HotelRateCriteria(stay))
        stay.rooms = 2; stay.adults = 3; stay.roomGuests = [HotelOccupancy(adults: 2, children: [5]), HotelOccupancy(adults: 1)]
        let criteria = try XCTUnwrap(HotelRateCriteria(stay)); XCTAssertEqual(criteria.occupancies[0].children, [5]); XCTAssertEqual(criteria.occupancies[1].adults, 1)
        let decoded = try JSONDecoder().decode(HotelRateCriteria.self, from: JSONEncoder().encode(criteria)); XCTAssertEqual(decoded, criteria)
        let request = HotelRatesRequest(hotelIds: ["liteapi:lp123"], detail: true, criteria: criteria)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(encoded["checkin"] as? String, criteria.checkin); XCTAssertEqual(encoded["hotelIds"] as? [String], ["liteapi:lp123"])
        XCTAssertEqual(encoded["detail"] as? Bool, true); XCTAssertNil(encoded["criteria"])
        let occupancy = try XCTUnwrap((encoded["occupancies"] as? [[String: Any]])?.first)
        XCTAssertEqual(occupancy["children"] as? [Int], [5]); XCTAssertNil(occupancy["id"])

        stay.roomGuests[0].children = [-1]; XCTAssertNil(HotelRateCriteria(stay))
        stay.roomGuests[0].children = [5]; stay.checkOut = Calendar.current.date(byAdding: .day, value: 31, to: stay.checkIn!); XCTAssertNil(HotelRateCriteria(stay))
    }
    func testHotelRateEnvelopeDecodesDecimalStringsAndUnknownFeeTiming() throws {
        let data = Data(#"""
        {"hotels":[{"hotelId":"liteapi:lp123","status":"available","offers":[{"id":"quote-id","hotelId":"liteapi:lp123","rooms":[{"number":1,"name":"King","mappedRoomId":null,"adults":2,"children":[],"board":"Room only","breakfast":false,"paymentTypes":["NUITEE_PAY"],"cancellation":{"nonrefundable":true,"freeUntil":null,"penalties":[],"remarks":[]},"remarks":"","perks":[]}],"base":{"amount":"100.10","currency":"USD"},"total":null,"fees":[{"description":"Local charge","included":null,"charge":null,"room":1}],"publicPriceEligible":false,"publicPriceFloor":{"amount":"120.00","currency":"USD"},"breakfast":false,"freeCancellationUntil":null,"expiresAt":"2020-01-01T12:00:00.123Z","quote":"opaque"}]}],"criteria":{"checkin":"2026-10-01","checkout":"2026-10-04","currency":"USD","guestNationality":"US","occupancies":[{"adults":2,"children":[]}]},"environment":"sandbox","expiresAt":"2020-01-01T12:00:00.123Z","checkoutEnabled":false}
        """#.utf8)
        let page = try JSONDecoder().decode(HotelRatePage.self, from: data)
        let offer = try XCTUnwrap(page.hotels.first?.offers.first)
        XCTAssertEqual(offer.base.decimal, Decimal(string: "100.10")); XCTAssertNil(offer.total); XCTAssertNil(offer.fees[0].included)
        XCTAssertTrue(offer.expired); XCTAssertFalse(offer.publicPriceEligible); XCTAssertFalse(page.checkoutEnabled)
    }
    func testHotelMoneyAndFractionalSecondQuoteExpiry() throws {
        XCTAssertEqual(HotelMoney(amount: "0.10", currency: "USD").decimal! + HotelMoney(amount: "0.20", currency: "USD").decimal!, Decimal(string: "0.30"))
        XCTAssertEqual(HotelRateClock.date("2026-09-10T12:00:00.000Z"), HotelRateClock.date("2026-09-10T12:00:00Z"))
        XCTAssertNil(HotelRateClock.date("not-a-date"))
    }
    @MainActor func testChangingHotelCriteriaInvalidatesPreviousRatesImmediately() throws {
        let model = HotelSearchModel(); model.stay.guestNationality = "US"
        model.stay.checkIn = Calendar.current.startOfDay(for: .now); model.stay.checkOut = Calendar.current.date(byAdding: .day, value: 3, to: model.stay.checkIn!)
        let context = try XCTUnwrap(HotelRateCriteria(model.stay)); model.rates.criteria = context; model.rates.results["old-hotel"] = .init(hotelId: "old-hotel", offers: [], status: "unavailable")
        model.stay.currency = "EUR"; XCTAssertTrue(model.rates.results.isEmpty); XCTAssertNil(model.rates.criteria)
    }
    func testStayRangeSelectionRestartsAndUsesCalendarNights() throws {
        var stay = HotelStayPreferences()
        let start = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 2, to: .now)!)
        let end = Calendar.current.date(byAdding: .day, value: 3, to: start)!
        stay.select(start); XCTAssertFalse(stay.datesValid); XCTAssertNil(stay.checkOut)
        stay.select(end); XCTAssertEqual(stay.nights, 3); XCTAssertTrue(stay.datesValid)
        stay.select(start); XCTAssertNil(stay.checkOut)
        stay.select(Calendar.current.date(byAdding: .day, value: -1, to: start)!); XCTAssertNil(stay.checkOut)
        XCTAssertEqual(stay.adults, 2); XCTAssertEqual(stay.rooms, 1)
        XCTAssertTrue(HotelStayPreferences().datesValid)
    }
    @MainActor func testProviderHotelBookmarkSurvivesWithoutBundledHotelOrLicensedContent() throws {
        let suite = "hotel-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TravelStore(defaults: defaults)
        var hotel = HotelFixtures.hotel()
        hotel.photo = "https://example.com/licensed-photo.jpg"
        store.toggleHotelSave(hotel)
        XCTAssertTrue(store.isHotelSaved(hotel))
        let restored = TravelStore(defaults: defaults)
        let entry = try XCTUnwrap(restored.wishlistEntries.first { $0.place.id == hotel.id })
        XCTAssertEqual(entry.kind, .stays)
        XCTAssertEqual(entry.place.name, hotel.name)
        XCTAssertNil(entry.place.rating)
        XCTAssertFalse(String(data: try XCTUnwrap(defaults.data(forKey: "seur.wishlist.v1")), encoding: .utf8)!.contains("licensed-photo"))
        restored.toggleHotelSave(hotel)
        XCTAssertFalse(restored.isHotelSaved(hotel))
    }
    @MainActor func testVerifiedProviderMappingKeepsExistingCollectionBookmark() {
        let suite = "hotel-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TravelStore(defaults: defaults)
        var hotel = HotelFixtures.hotel(); hotel.id = "liteapi:lp2a32f"
        store.toggleHotelSave(hotel)
        XCTAssertTrue(store.saved.contains("lon-savoy"))
        XCTAssertTrue(store.wishlist.ideas.isEmpty)
        XCTAssertTrue(store.isHotelSaved(hotel))
    }
    @MainActor func testHotelEndpointGuardBlocksLiveProviderCallsInUnitTests() async {
        let api = TravelAPI()
        do { _ = try await api.hotelDetail("liteapi:lp2a32f"); XCTFail("Should block live request") }
        catch { XCTAssertTrue(error.localizedDescription.contains("disabled during tests")) }
    }
    var store: TravelStore!
    var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "com.aurum.travel.unittests")!
        defaults.removePersistentDomain(forName: "com.aurum.travel.unittests")
        store = TravelStore(defaults: defaults)
    }
    func testWishlistSelectedPlaceSurvivesSaveAndLegacyDataStillDecodes() throws {
        let old = Data(#"{"id":"legacy","name":"A museum","destination":"London","kind":"Things to do","website":""}"#.utf8)
        let legacy = try JSONDecoder().decode(WishlistIdea.self, from: old)
        XCTAssertNil(legacy.selectedPlace)
        XCTAssertEqual(legacy.record.name, "A museum")
        let place = PlaceRecord(id: "apple-landmark", name: "Tower Bridge", category: .landmark, city: "London", address: "Tower Bridge Road", latitude: 51.505, longitude: -0.075, source: "Apple Maps")
        var value = WishlistIdea(name: place.name, destination: place.city, kind: .sights, selectedPlace: place)
        XCTAssertTrue(store.wishlist.saveIdea(value, details: WishlistDetails()))
        let restored = try XCTUnwrap(TravelStore(defaults: defaults).wishlistEntries.first)
        XCTAssertEqual(restored.kind, .sights)
        XCTAssertEqual(restored.place.id, place.id)
        XCTAssertEqual(restored.place.latitude, place.latitude)
        XCTAssertEqual(restored.place.address, place.address)
        value.destination = "Paris"
        XCTAssertTrue(store.wishlist.saveIdea(value, details: WishlistDetails()))
        XCTAssertNil(store.wishlistEntries.first?.place.latitude)
        XCTAssertEqual(WishlistSaveType.hotel.kind.category, .hotel)
        XCTAssertEqual(WishlistSaveType.restaurant.kind.category, .restaurant)
        XCTAssertEqual(WishlistSaveType.activity.kind.category, .attraction)
        XCTAssertEqual(WishlistSaveType.sight.kind.category, .landmark)
    }
    func testWishlistBookmarksUnifyAndRemoveWithoutDuplicateDining() throws {
        let hotel = try XCTUnwrap(store.featured.first)
        let restaurant = RestaurantPlace(hotel: hotel, venue: hotel.venues[0])
        let city = try XCTUnwrap(ExploreCity.collection.first { $0.name == hotel.city })
        store.toggleSave(hotel); store.toggleRestaurantSave(restaurant); store.toggleExploreCity(city)
        XCTAssertEqual(store.wishlistEntries.count, 3)
        XCTAssertEqual(store.wishlistEntries.filter { $0.kind == .dining }.count, 1)
        let entry = try XCTUnwrap(store.wishlistEntries.first { $0.kind == .dining })
        XCTAssertTrue(store.wishlist.update(WishlistDetails(notes: "Window table", collection: "Anniversary", topPick: true), for: entry.id))
        let reload = TravelStore(defaults: defaults)
        XCTAssertEqual(reload.wishlistEntries.count, 3)
        XCTAssertEqual(reload.wishlist.info(entry.id).notes, "Window table")
        XCTAssertTrue(reload.removeFromWishlist(entry))
        XCTAssertFalse(reload.savedRestaurants.contains(restaurant.id))
        XCTAssertFalse(reload.savedDiscoveries.contains { $0.record.id == restaurant.id })
        XCTAssertEqual(TravelStore(defaults: defaults).wishlistEntries.count, 2)
        XCTAssertTrue(reload.saved.contains(hotel.id))
    }
    func testWishlistIdeasValidationPersistenceEditingAndFilters() throws {
        var idea = WishlistIdea(name: "  Museum after hours  ", destination: " London ", website: "https://example.com/tickets")
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails(notes: "Book a quiet evening", collection: " Summer ", topPick: true, addedAt: 10)))
        let id = "idea:" + idea.id
        XCTAssertEqual(store.wishlistEntries.first?.title, "Museum after hours")
        XCTAssertEqual(store.wishlistCollections, ["Summer"])
        XCTAssertEqual(store.wishlistMatches(query: "quiet", kind: .experiences, collection: "Summer", topPicks: true).map(\.id), [id])
        XCTAssertTrue(store.wishlistMatches(query: "", kind: .dining).isEmpty)
        XCTAssertTrue(store.wishlistMatches(query: "", collection: "Winter").isEmpty)
        let second = WishlistIdea(name: "A table", destination: "Paris", kind: .dining)
        XCTAssertTrue(store.wishlist.saveIdea(second, details: WishlistDetails(collection: "summer", addedAt: 20)))
        XCTAssertEqual(store.wishlistCollections, ["Summer"])
        XCTAssertEqual(store.wishlistMatches(query: "").first?.title, "A table")
        XCTAssertEqual(store.wishlistMatches(query: "", sort: .destination).first?.title, "Museum after hours")
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: "museum after hours", destination: "London"), details: WishlistDetails()))
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: " "), details: WishlistDetails()))
        XCTAssertFalse(store.wishlist.saveIdea(WishlistIdea(name: "Unsafe link", website: "javascript:alert(1)"), details: WishlistDetails()))
        idea.name = "A private museum visit"
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails(notes: "Updated", collection: "Summer")))
        let reload = TravelStore(defaults: defaults)
        XCTAssertEqual(reload.wishlistEntries.count, 2)
        XCTAssertEqual(reload.wishlist.info(id).notes, "Updated")
        XCTAssertTrue(reload.wishlistMatches(query: "Updated").contains { $0.title == "A private museum visit" })
        XCTAssertTrue(reload.removeFromWishlist(try XCTUnwrap(reload.wishlistEntries.first { $0.id == id })))
        XCTAssertFalse(TravelStore(defaults: defaults).wishlistEntries.contains { $0.id == id })
    }
    func testWishlistPlanningIdentityAndCorruptDataProtection() throws {
        let idea = WishlistIdea(name: "Museum", destination: "London")
        XCTAssertTrue(store.wishlist.saveIdea(idea, details: WishlistDetails()))
        let entry = try XCTUnwrap(store.wishlistEntries.first)
        let stop = JourneyStop(name: "London")
        var document = JourneyDocument(title: "London", stops: [stop])
        document.events = [JourneyEvent(stopID: stop.id, place: entry.place)]
        XCTAssertTrue(entry.isPlanned(in: document))
        XCTAssertTrue(store.removeFromWishlist(entry)); XCTAssertEqual(document.events.count, 1)
        document.events[0].place.source = "Different source"
        XCTAssertFalse(entry.isPlanned(in: document))
        let destination = WishlistIdea(name: "Paris", destination: "France", kind: .destinations)
        XCTAssertTrue(store.wishlist.saveIdea(destination, details: WishlistDetails()))
        let city = try XCTUnwrap(store.wishlistEntries.first)
        XCTAssertEqual(city.subtitle, "France"); XCTAssertEqual(city.tripDestination, "Paris, France")
        XCTAssertTrue(city.isPlanned(in: JourneyDocument(title: "Paris", stops: [JourneyStop(name: "Paris, France")])))
        XCTAssertFalse(city.isPlanned(in: JourneyDocument(title: "Paris", stops: [JourneyStop(name: "Paris, Texas")])))
        let corrupt = Data("unreadable wishlist".utf8); defaults.set(corrupt, forKey: "seur.wishlist.v1")
        let blocked = WishlistLibrary(defaults: defaults)
        XCTAssertNotNil(blocked.error)
        XCTAssertFalse(blocked.saveIdea(idea, details: WishlistDetails()))
        XCTAssertEqual(defaults.data(forKey: "seur.wishlist.v1"), corrupt)
    }
    func testImportedCatalogIntegrity() {
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.hotels.count, 1513)
        XCTAssertEqual(Set(store.hotels.map(\.id)).count, 1513)
        XCTAssertEqual(store.hotels.reduce(0) { $0 + $1.venues.count }, 5755)
        XCTAssertEqual(Set(store.hotels.map(\.city)).count, 12)
    }
    func testCuisineAndCitySearch() {
        let results = store.search(query: "Cantonese", city: "Paris", sort: .dining)
        XCTAssertTrue(results.contains { $0.id == "par-peninsula" })
        XCTAssertTrue(results.allSatisfy { $0.city == "Paris" })
        XCTAssertEqual(results.map { $0.venues.count }, results.map { $0.venues.count }.sorted(by: >))
        XCTAssertTrue(store.search(query: "__missing_hotel__").isEmpty)
        XCTAssertEqual(store.search(query: "  savoy  ", city: "London").first?.id, "lon-savoy")
    }
    func testSavedHotelsPersist() {
        let hotel = store.featured[0]
        store.toggleSave(hotel)
        XCTAssertTrue(TravelStore(defaults: defaults).saved.contains(hotel.id))
        store.toggleSave(hotel)
        XCTAssertFalse(TravelStore(defaults: defaults).saved.contains(hotel.id))
    }
    func testRestaurantPersistenceAndHotelScoping() {
        let hotel = store.featured[0]
        let place = RestaurantPlace(hotel: hotel, venue: hotel.venues[0])
        let other = RestaurantPlace(hotel: store.featured[1], venue: hotel.venues[0])
        XCTAssertNotEqual(place.id, other.id)
        store.toggleRestaurantSave(place)
        store.saveRestaurantVisit(RestaurantVisit(rating: 5, note: "Quiet table"), for: place)
        let restored = TravelStore(defaults: defaults)
        XCTAssertEqual(restored.savedDiningPlaces.map(\.id), [place.id])
        XCTAssertEqual(restored.restaurantVisits[place.id]?.rating, 5)
        XCTAssertEqual(restored.restaurantVisits[place.id]?.note, "Quiet table")
        XCTAssertNil(restored.restaurantVisits[other.id])
        store.toggleRestaurantSave(place)
        store.saveRestaurantVisit(RestaurantVisit(), for: place)
        XCTAssertTrue(TravelStore(defaults: defaults).savedRestaurants.isEmpty)
        XCTAssertTrue(TravelStore(defaults: defaults).restaurantVisits.isEmpty)
    }

    func testTripPersistenceDuplicateAndInvalidDates() {
        let hotel = store.featured[0]
        let dates = BookingDates()
        XCTAssertTrue(store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: dates))
        XCTAssertFalse(store.addPlan(name: hotel.name, city: hotel.city, kind: "Stay", hotelID: hotel.id, dates: dates))
        XCTAssertEqual(TravelStore(defaults: defaults).plans.count, 1)
        var invalid = dates; invalid.end = invalid.start
        XCTAssertFalse(store.addPlan(name: "Invalid", city: "Paris", kind: "Stay", hotelID: nil, dates: invalid))
        store.removePlan(store.plans[0])
        XCTAssertTrue(TravelStore(defaults: defaults).plans.isEmpty)
    }
    func testSafeLinksAndFlightValidation() {
        XCTAssertNil(validatedURL("javascript:alert(1)"))
        XCTAssertNil(validatedURL("n/a"))
        XCTAssertNotNil(validatedURL("https://www.google.com"))
        var flight = FlightSearch()
        XCTAssertNotNil(flight.url)
        let query = URLComponents(url: flight.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
        XCTAssertTrue(query.contains("returning"))
        XCTAssertTrue(query.contains("2 adults Business"))
        flight.oneWay = true
        XCTAssertFalse(URLComponents(url: flight.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!.contains("returning"))
        flight.destination = flight.origin
        XCTAssertNil(flight.url)
    }
    func testComparisonLimit() {
        for hotel in store.hotels.prefix(4) { store.toggleCompare(hotel) }
        XCTAssertEqual(store.compared.count, 3)
        store.toggleCompare(store.hotels[0])
        XCTAssertEqual(store.compared.count, 2)
    }
}
