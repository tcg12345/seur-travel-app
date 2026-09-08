export class Problem extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}
export function requireValue(
  ok: unknown,
  message: string,
  status = 400,
): asserts ok {
  if (!ok) throw new Problem(message, status);
}
export const object = (v: any) =>
  v !== null && typeof v === "object" && !Array.isArray(v);
export const uuid = (v: any) =>
  typeof v === "string" &&
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v);
export const finite = (v: any) => typeof v === "number" && Number.isFinite(v);
export const day = (v: any) =>
  typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v) &&
  Number.isFinite(Date.parse(v)) &&
  new Date(v).toISOString().slice(0, 10) === v;
export function text(v: any, name: string, limit = 10000, optional = false) {
  requireValue(
    typeof v === "string" && v.length <= limit && (optional || v.trim()),
    `Invalid ${name}.`,
  );
}
export function safeURL(v: any) {
  try {
    const u = new URL(v);
    return typeof v === "string" && v.length <= 5000 &&
      ["http:", "https:"].includes(u.protocol) &&
      !!u.hostname && !u.username && !u.password;
  } catch {
    return false;
  }
}
export const categories = new Set([
  "restaurant",
  "attraction",
  "hotel",
  "museum",
  "park",
  "monument",
  "shopping",
  "entertainment",
  "bar",
  "cafe",
  "beach",
  "spa",
  "landmark",
  "other",
]);
export const eventKinds: Record<string, string> = {
  place: "Restaurant or activity",
  meeting: "Meeting",
  appointment: "Appointment",
  conference: "Conference",
  celebration: "Celebration",
  concert: "Concert",
  performance: "Theatre & performance",
  sport: "Sporting event",
  tour: "Tour & excursion",
  transfer: "Car & transfer",
  train: "Train",
  ferry: "Boat & ferry",
  shopping: "Shopping",
  wellness: "Wellness",
  freeTime: "Free time",
  custom: "Custom event",
};
export function place(p: any, empty = false) {
  requireValue(object(p), "Invalid place.");
  text(p.id, "place ID", 500);
  if (p.brand != null) text(p.brand, "hotel brand", 200, true);
  text(p.name, "place name", 500, empty);
  requireValue(categories.has(p.category), "Invalid place category.");
  for (
    const k of ["city", "address", "phone", "website", "source", "overview"]
  ) {
    text(p[k] ?? "", k, 15000, true);
  }
  if (p.latitude != null || p.longitude != null) {
    requireValue(
      finite(p.latitude) && finite(p.longitude) && Math.abs(p.latitude) <= 90 &&
        Math.abs(p.longitude) <= 180,
      "Invalid coordinates.",
    );
  }
  if (p.rating != null) {
    requireValue(
      finite(p.rating) && p.rating >= 0 && p.rating <= 5,
      "Invalid provider rating.",
    );
  }
}
export function money(v: any) {
  if (v == null) return;
  requireValue(
    object(v) && finite(v.amount) && v.amount >= 0 && v.amount <= 1e9,
    "Invalid price.",
  );
  requireValue(
    typeof v.currency === "string" && /^[A-Z]{3}$/.test(v.currency),
    "Invalid currency.",
  );
}
export function decodePhoto(v: any): Uint8Array {
  requireValue(
    typeof v === "string" && v.length <= 2000000 &&
      /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        v,
      ),
    "Invalid photo encoding.",
  );
  const raw = Uint8Array.from(atob(v), (c) => c.charCodeAt(0));
  requireValue(
    raw.length <= 1500000 && raw[0] === 255 && raw[1] === 216 && raw[2] === 255,
    "Photos must be JPEG, below 1.5 MB each.",
  );
  return raw;
}
export function validateDocument(d: any) {
  requireValue(object(d) && uuid(d.id), "Invalid journey ID.");
  requireValue(
    ["journey", "trip", "itinerary"].includes(d.kind),
    "Invalid journey type.",
  );
  requireValue(
    ["private", "friends", "public"].includes(d.visibility),
    "Invalid audience.",
  );
  requireValue(d.isTemplate == null || typeof d.isTemplate === "boolean", "Invalid template flag.");
  if (d.templateMeta != null) {
    const m = d.templateMeta;
    requireValue(object(m), "Invalid template metadata.");
    text(m.tagline ?? "", "template tagline", 250, true);
    text(m.suggestedSeason ?? "", "suggested season", 120, true);
    text(m.authorHandle ?? "", "template author", 32, true);
    requireValue(Array.isArray(m.tags) && m.tags.length <= 8 && m.tags.every((t: any) => typeof t === "string" && /^[a-z0-9 -]{1,30}$/.test(t)), "Use up to eight short style tags.");
    requireValue(m.cloneCount == null || Number.isSafeInteger(m.cloneCount) && m.cloneCount >= 0, "Invalid template count.");
  }
  text(d.title, "title", 200);
  text(d.description ?? "", "description", 20000, true);
  text(d.destination ?? "", "destination", 1000, true);
  requireValue(["dates", "nights"].includes(d.dateMode), "Invalid date mode.");
  for (const k of ["startDate", "endDate"]) {
    requireValue(d[k] == null || day(d[k]), "Invalid journey date.");
  }
  requireValue(
    !d.startDate || !d.endDate || d.endDate >= d.startDate,
    "Journey end precedes start.",
  );
  requireValue(finite(d.updatedAt), "Invalid updated timestamp.");
  for (
    const [k, limit] of Object.entries({
      stops: 40,
      events: 2000,
      hotels: 200,
      flights: 200,
      places: 500,
    })
  ) {
    requireValue(
      Array.isArray(d[k]) && d[k].length <= limit,
      `Too many or invalid ${k}.`,
    );
    requireValue(
      d[k].every((v: any) => object(v) && uuid(v.id)),
      `Invalid ${k} identifiers.`,
    );
    requireValue(
      new Set(d[k].map((v: any) => v.id.toLowerCase())).size === d[k].length,
      `Duplicate ${k} identifiers.`,
    );
  }
  const stops = new Map<string, any>();
  let previous = 0;
  for (const s of d.stops) {
    text(s.name, "destination name", 500);
    requireValue(s.countryCode == null || typeof s.countryCode === "string" && /^[A-Z]{2}$/.test(s.countryCode), "Invalid ISO country code.");
    requireValue(
      Number.isInteger(s.nights) && s.nights >= 1 && s.nights <= 365 &&
        day(s.arrival),
      "Invalid destination dates or nights.",
    );
    requireValue(
      d.dateMode !== "dates" || Date.parse(s.arrival) >= previous,
      "Destination dates overlap.",
    );
    previous = Date.parse(s.arrival) + s.nights * 86400000;
    stops.set(s.id, s);
    if (s.latitude != null || s.longitude != null) {
      requireValue(
        finite(s.latitude) && finite(s.longitude) &&
          Math.abs(s.latitude) <= 90 &&
          Math.abs(s.longitude) <= 180,
        "Invalid destination coordinates.",
      );
    }
  }
  for (const e of d.events) {
    requireValue(
      stops.has(e.stopID) && Number.isInteger(e.day) && e.day >= 0 &&
        e.day <= stops.get(e.stopID).nights,
      "Invalid event day or destination.",
    );
    requireValue(
      Number.isInteger(e.minute) && e.minute >= 0 && e.minute < 1440,
      "Invalid event time.",
    );
    requireValue(uuid(e.seriesID), "Invalid recurring-event identifier.");
    const kind = e.kind || "place";
    requireValue(Object.hasOwn(eventKinds, kind), "Invalid event type.");
    if (kind !== "place") text(e.title, "event title", 500);
    else if (e.title != null) text(e.title, "event title", 500, true);
    requireValue(
      e.allDay == null || typeof e.allDay === "boolean",
      "Invalid all-day setting.",
    );
    requireValue(
      e.durationMinutes == null ||
        (Number.isInteger(e.durationMinutes) && e.durationMinutes >= 1 &&
          e.durationMinutes <= 1440),
      "Invalid event duration.",
    );
    text(e.attendees ?? "", "event guests", 2000, true);
    place(e.place, kind !== "place");
    money(e.cost);
    text(e.description ?? "", "event description", 20000, true);
    requireValue(
      Array.isArray(e.links) && e.links.length <= 30 && e.links.every(safeURL),
      "Invalid event links.",
    );
  }
  for (const h of d.hotels) {
    place(h.place);
    money(h.cost);
    requireValue(
      day(h.checkIn) && day(h.checkOut) && h.checkOut > h.checkIn,
      "Invalid hotel dates.",
    );
    requireValue(
      Number.isInteger(h.guests) && h.guests >= 1 && h.guests <= 99 &&
        Number.isInteger(h.rooms) &&
        h.rooms >= 1 && h.rooms <= 50,
      "Invalid hotel guests or rooms.",
    );
    for (const k of ["roomType", "confirmation", "notes", "overview"]) {
      text(h[k] ?? "", k, 20000, true);
    }
  }
  for (const f of d.flights) {
    for (const k of ["airline", "departureAirport", "arrivalAirport"]) {
      text(f[k], k, 300);
    }
    for (const k of ["departureDay", "arrivalDay"]) {
      requireValue(day(f[k]), "Invalid flight date.");
    }
    for (const k of ["departureTime", "arrivalTime"]) {
      requireValue(
        typeof f[k] === "string" && /^(?:[01]?\d|2[0-3]):[0-5]\d$/.test(f[k]),
        "Invalid flight time.",
      );
    }
    requireValue(
      !f.bookingLink || safeURL(f.bookingLink),
      "Invalid booking link.",
    );
    money(f.cost);
  }
  let total = 0;
  for (const p of d.places) {
    place(p.place);
    requireValue(
      finite(p.overall) && p.overall >= 0 && p.overall <= 10,
      "Invalid personal score.",
    );
    requireValue(
      object(p.scores) && Object.keys(p.scores).length <= 20 &&
        Object.entries(p.scores).every(([k, v]) =>
          k.length <= 100 && finite(v) && (v as number) >= 0 &&
          (v as number) <= 10
        ),
      "Invalid category scores.",
    );
    requireValue(
      p.visitedOn == null || day(p.visitedOn),
      "Invalid visit date.",
    );
    requireValue(
      p.michelinStars == null ||
        (Number.isInteger(p.michelinStars) && p.michelinStars >= 0 &&
          p.michelinStars <= 3),
      "Invalid Michelin star record.",
    );
    text(p.notes ?? "", "visit notes", 20000, true);
    requireValue(
      Array.isArray(p.photos) && p.photos.length <= 6,
      "Use up to six photos per place.",
    );
    requireValue(
      new Set(p.photos.map((v: any) => v.id?.toLowerCase())).size ===
        p.photos.length,
      "Duplicate photo identifiers.",
    );
    for (const photo of p.photos) {
      requireValue(object(photo) && uuid(photo.id), "Invalid photo.");
      total += decodePhoto(photo.jpeg).length;
    }
  }
  requireValue(
    total <= 28000000,
    "This shared journey exceeds the 28 MB photo limit.",
  );
}

export function validateFlight(f: any) {
  requireValue(object(f) && uuid(f.id), "Invalid flight record.");
  for (const k of ["airline", "departureAirport", "arrivalAirport"]) {
    text(f[k], k, 300);
  }
  text(f.flightNumber ?? "", "flight number", 20, true);
  text(f.notes ?? "", "flight notes", 20000, true);
  for (const k of ["departureDay", "arrivalDay"]) {
    requireValue(day(f[k]), "Invalid flight date.");
  }
  for (const k of ["departureTime", "arrivalTime"]) {
    requireValue(
      typeof f[k] === "string" && /^(?:[01]?\d|2[0-3]):[0-5]\d$/.test(f[k]),
      "Invalid flight time.",
    );
  }
  for (const prefix of ["departure", "arrival"]) {
    const lat = f[prefix + "Latitude"], lon = f[prefix + "Longitude"];
    requireValue(
      (lat == null && lon == null) ||
        (finite(lat) && finite(lon) && Math.abs(lat) <= 90 &&
          Math.abs(lon) <= 180),
      "Invalid airport coordinates.",
    );
    text(f[prefix + "Zone"] ?? "", "airport time zone", 100, true);
  }
  requireValue(
    !f.bookingLink || safeURL(f.bookingLink),
    "Invalid booking link.",
  );
  money(f.cost);
}
