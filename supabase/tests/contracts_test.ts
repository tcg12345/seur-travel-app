import assert from "node:assert/strict";
import {
  day,
  Problem,
  safeURL,
  validateDocument,
  validateFlight,
} from "../functions/travel-api/validation.ts";
import { localDay, normalize } from "../functions/travel-api/flights.ts";
import { sharedLines, sharePDF } from "../functions/travel-api/shared.ts";
function fixture() {
  const id = () => crypto.randomUUID();
  const stop = id();
  return {
    id: id(),
    kind: "journey",
    title: "A thoughtful visit",
    description: "",
    destination: "Paris",
    dateMode: "dates",
    visibility: "private",
    startDate: "2026-10-01",
    endDate: "2026-10-03",
    updatedAt: 1,
    stops: [{ id: stop, name: "Paris", arrival: "2026-10-01", nights: 2 }],
    events: [{
      id: id(),
      seriesID: id(),
      stopID: stop,
      day: 0,
      minute: 1410,
      kind: "meeting",
      title: "Late review",
      durationMinutes: 90,
      attendees: "Alex",
      place: { id: "venue", name: "", category: "other" },
      description: "",
      links: ["https://example.com"],
      cost: { amount: 25, currency: "EUR" },
    }],
    hotels: [],
    flights: [],
    places: [],
  };
}
Deno.test("Unified, legacy and venue-free meeting documents preserve their contract", () => {
  for (const kind of ["journey", "trip", "itinerary"]) {
    const d = fixture();
    d.kind = kind;
    assert.doesNotThrow(() => validateDocument(d));
  }
});
Deno.test("Reject invalid dates, coordinates and out-of-route scheduling", () => {
  assert.equal(day("2026-02-30"), false);
  const bad: any = fixture();
  bad.events[0].day = 3;
  assert.throws(() => validateDocument(bad), Problem);
  bad.events[0].day = 0;
  bad.events[0].place.latitude = 91;
  bad.events[0].place.longitude = 10;
  assert.throws(() => validateDocument(bad), Problem);
});
Deno.test("Reject duplicate identifiers and unbounded costs", () => {
  const d = fixture();
  d.events.push(structuredClone(d.events[0]));
  assert.throws(() => validateDocument(d), Problem);
  d.events.pop();
  d.events[0].cost.amount = Infinity;
  assert.throws(() => validateDocument(d), Problem);
});
Deno.test("Reject scripts, credential URLs and arbitrary storage references", () => {
  assert.equal(safeURL("javascript:alert(1)"), false);
  assert.equal(safeURL("https://user:pass@example.com"), false);
  const d: any = fixture();
  d.places = [{
    id: crypto.randomUUID(),
    place: { id: "x", name: "Somewhere", category: "park" },
    overall: 8,
    scores: {},
    photos: [{ id: crypto.randomUUID(), storagePath: "someone-elses-photo" }],
  }];
  assert.throws(() => validateDocument(d), Problem);
});
Deno.test("Departure dates follow origin time zone across midnight", () => {
  assert.equal(
    localDay({
      scheduled_out: "2026-09-08T01:00:00Z",
      origin: { timezone: "America/New_York" },
    }),
    "2026-09-07",
  );
  assert.equal(
    localDay({
      scheduled_out: "2026-09-08T01:00:00Z",
      origin: { timezone: "Asia/Tokyo" },
    }),
    "2026-09-08",
  );
});
Deno.test("Missing flight delays and aircraft are not invented", () => {
  const r = normalize({
    fa_flight_id: "flight",
    ident_iata: "BA178",
    scheduled_out: "2026-09-07T10:00:00Z",
    arrival_delay: 0,
    origin: { code_iata: "JFK" },
    destination: { code_iata: "LHR" },
  });
  assert.equal(r.arrivalDelay, 0);
  assert.equal(r.departureDelay, undefined);
  assert.equal(r.aircraft, undefined);
  assert.equal(r.origin, "JFK");
});
Deno.test("Shared text preserves international names and meeting detail", () => {
  const d = fixture();
  d.title = "東京 · Café";
  const lines = sharedLines(d, "Traveler");
  assert.equal(lines[0].text, d.title);
  assert(lines.some((v) => v.text === "Late review"));
  assert(lines.some((v) => v.text.includes("90 min")));
});
Deno.test("Read-only PDF supports long paragraphs and includes portable source data", async () => {
  const d = fixture();
  d.description = "A wonderful journey. ".repeat(300);
  const pdf = await sharePDF(d, "Traveler");
  assert.equal(new TextDecoder().decode(pdf.slice(0, 4)), "%PDF");
  assert(pdf.length > 3000);
});

Deno.test("standalone flights reject invalid coordinates and preserve local dates", () => {
  const f = {
    id: crypto.randomUUID(),
    airline: "British Airways",
    flightNumber: "BA178",
    departureAirport: "JFK",
    arrivalAirport: "LHR",
    departureDay: "2026-09-06",
    arrivalDay: "2026-09-07",
    departureTime: "18:00",
    arrivalTime: "06:00",
    departureLatitude: 40.6,
    departureLongitude: -73.7,
  };
  validateFlight(f);
  assert.throws(() => validateFlight({ ...f, departureLatitude: 91 }), Problem);
  assert.throws(
    () => validateFlight({ ...f, departureLongitude: null }),
    Problem,
  );
  assert.throws(
    () => validateFlight({ ...f, departureTime: "26:00" }),
    Problem,
  );
  assert.throws(
    () => validateFlight({ ...f, bookingLink: "javascript:alert(1)" }),
    Problem,
  );
});

Deno.test("Runway estimates survive flight normalization without fabricated values", () => {
  const row = normalize({ fa_flight_id: "timeline", estimated_off: "2026-09-08T01:27:00Z", estimated_on: "2026-09-08T08:40:00Z" });
  assert.equal(row.estimatedOff, "2026-09-08T01:27:00Z");
  assert.equal(row.estimatedOn, "2026-09-08T08:40:00Z");
  assert.equal(normalize({ fa_flight_id: "missing" }).estimatedOff, undefined);
});

Deno.test("Route planning metadata and transfer blocks retain the journey contract", () => {
  const d: any = fixture();
  d.routePlan = { keepFirst: true, keepLast: false, preferTrain: true, objective: "distance", choices: [], reserveTransfers: true, returnHome: true };
  d.events[0].kind = "train";
  d.events[0].title = "Travel to Brussels";
  d.events[0].routeLegID = d.stops[0].id + ">destination";
  d.events[0].routeMode = "train";
  d.events[0].allDay = true;
  d.events[0].description = "Planning allowance, not a booking.";
  assert.doesNotThrow(() => validateDocument(d));
  const restored = JSON.parse(JSON.stringify(d));
  assert.deepEqual(restored.routePlan, d.routePlan);
  assert.equal(restored.events[0].routeLegID, d.events[0].routeLegID);
});

Deno.test("planned hotel checkout time is optional and validates clock bounds", () => {
  const d: any = fixture();
  d.hotels = [{id:crypto.randomUUID(),place:{id:"hotel",name:"Paris hotel",category:"hotel"},checkIn:"2026-10-01",checkOut:"2026-10-03",guests:2,rooms:1}];
  validateDocument(d);
  for (const value of ["00:00","09:30","9:30","23:59",null]) { d.hotels[0].checkOutTime=value; validateDocument(d); }
  for (const value of ["24:00","12:60","noon",930,""]) { d.hotels[0].checkOutTime=value; assert.throws(() => validateDocument(d),Problem); }
});
