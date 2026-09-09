# Agenda conflict detection

Agenda and Calendar display restrained inline warnings beneath affected events and hotel bookings. Tap **Review timing** to edit that item. Changes and deletions recompute warnings immediately; warnings never prevent saving or silently rearrange a plan.

`JourneyConflicts.detect(_:)` is a pure projection of the local document:

- **Overlapping events:** compares recorded durations, including overnight events and start-time collisions. Back-to-back end/start boundaries are allowed. An event without a duration is a start point, not an invented hour-long booking. All-day entries are excluded.
- **Plans before arrival:** finds the first relevant incoming flight for each destination stay, including an arrival just before the stay starts. It compares the event and saved arrival in the destination’s time zone, including overnight arrivals. A later return flight does not invalidate plans after the first arrival. Arrival airport proximity (within 150 km) or an explicitly matching airport code establishes relevance.
- **Hotel checkout after departure:** warns when the saved stay extends beyond a departing flight from that destination, or when a recorded planned checkout time is later than departure that day. Date-only reservations never acquire an assumed same-day checkout hour. Hotel coordinates can establish location without an agenda stop; otherwise a matching city and stop are needed.

Add an optional **planned checkout time** in the hotel editor’s Your stay section. It means the traveler’s intended time to leave the hotel, not the hotel’s latest permitted checkout. `checkOutTime` is optional for legacy archives and validated natively and in the cloud. Templates strip this personal timing choice. No database migration or new provider is required.

Times are compared as instants when zones are known. Cross-destination event comparisons are skipped without reliable zones. Same-location wall-clock comparisons remain possible without a zone. Invalid clocks and nonexistent daylight-saving times are excluded. Flexible-date itineraries support relative event overlaps within a stop, but no absolute hotel/flight warnings.

These are advisory checks based on recorded plans. They do not fetch live flight delays, infer unrecorded activity durations, or invent airport/ground-transfer buffers. No paid API calls, notifications, or shared-document mutations are involved.

Verification: 13 detector/compatibility tests plus 40 journey regression tests; 19 backend contract/template/recap tests; disposable-account checkout-time persistence and invalid-value rejection. See Validation.md for build results.
