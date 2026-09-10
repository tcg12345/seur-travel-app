import { requireValue, validateDocument } from "./validation.ts";

/** Explicit allowlists prevent extra client fields, booking links and private notes escaping. */
export function sanitizedTemplate(d: any, author: string) {
  validateDocument(d);
  requireValue(d.isTemplate === true && d.dateMode === "nights" && d.stops.length > 0, "Templates need destinations and night counts.");
  const meta = d.templateMeta ?? {};
  const costs = meta.includesCosts === true, ratings = meta.includesRatings === true;
  const pick = (source: any, keys: string[]) => Object.fromEntries(keys.filter(k => source[k] != null).map(k => [k, source[k]]));
  const place = (p: any) => ({ ...pick(p, ["id", "name", "category", "city", "address", "phone", "website", "latitude", "longitude", "source", "sourceURL", "brand"]), overview: "", ...(ratings && p.rating != null ? { rating: p.rating } : {}) });
  const add = (day: string, nights: number) => new Date(Date.parse(day) + nights * 86400000).toISOString().slice(0, 10);
  const distance = (a: string, b: string) => Math.round((Date.parse(b) - Date.parse(a)) / 86400000);
  let arrival = "2000-01-01";
  const stops = d.stops.map((s: any) => { const stop = { ...pick(s, ["id", "name", "code", "country", "nights", "latitude", "longitude", "timeZone", "countryCode"]), arrival }; arrival = add(arrival, s.nights); return stop; });
  const hotels = d.hotels.map((h: any) => {
    const matches = d.stops.filter((s: any) => s.arrival <= h.checkIn && h.checkIn < add(s.arrival, s.nights) && h.checkOut <= add(s.arrival, s.nights));
    requireValue(matches.length === 1, "Match each hotel stay to one destination before publishing.");
    const stop = matches[0], shifted = stops.find((s: any) => s.id === stop.id);
    return { id: h.id, place: place(h.place), checkIn: add(shifted.arrival, distance(stop.arrival, h.checkIn)), checkOut: add(shifted.arrival, distance(stop.arrival, h.checkOut)), guests: 2, rooms: 1, roomType: "", confirmation: "", notes: "", overview: "", ...(costs && h.cost ? { cost: pick(h.cost, ["amount", "currency"]) } : {}) };
  });
  const clean = {
    id: d.id, kind: "journey", title: d.title, destination: d.destination ?? "", description: "", dateMode: "nights", visibility: d.visibility,
    isTemplate: true, updatedAt: d.updatedAt,
    templateMeta: { tagline: meta.tagline ?? "", tags: meta.tags ?? [], suggestedSeason: meta.suggestedSeason ?? "", authorHandle: author, cloneCount: 0, includesCosts: costs, includesRatings: ratings },
    stops, hotels, flights: [],
    events: d.events.map((e: any) => ({ ...pick(e, ["id", "seriesID", "stopID", "day", "minute", "kind", "title", "allDay", "durationMinutes"]), place: place(e.place), description: "", links: [], ...(costs && e.cost ? { cost: pick(e.cost, ["amount", "currency"]) } : {}) })),
    places: ratings ? d.places.map((r: any) => ({ ...pick(r, ["id", "overall", "scores", "michelinStars"]), place: place(r.place), notes: "", photos: [], priceRange: "" })) : [],
  };
  validateDocument(clean); return clean;
}
export function templateSummary(remote: any) {
  return { ...remote, isSummary: true, document: { ...remote.document, events: [], hotels: [], flights: [], places: [] } };
}
