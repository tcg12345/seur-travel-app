import assert from "node:assert/strict";
import { sanitizedTemplate, templateSummary } from "../functions/travel-api/templates.ts";
import { validateDocument } from "../functions/travel-api/validation.ts";
const seeds = JSON.parse(await Deno.readTextFile(new URL("../../iOS/Aurum/Resources/TripTemplates.json", import.meta.url)));
Deno.test("all ten editorial templates satisfy the public contract", () => {
  assert.equal(seeds.length, 10);
  for (const seed of seeds) {
    validateDocument(seed);
    const clean = sanitizedTemplate(seed, "seur_editors");
    assert.equal(clean.hotels.length, seed.hotels.length);
    assert.equal(clean.events.length, seed.events.length);
    assert.equal(clean.stops[0].arrival, "2000-01-01");
  }
});
Deno.test("template allowlist strips private fields and ignores forged author and counts", () => {
  const d = structuredClone(seeds[0]);
  d.description = "PRIVATE"; d.secret = "PRIVATE"; d.importedFrom = "PRIVATE";
  d.hotels[0].confirmation = "PRIVATE"; d.hotels[0].notes = "PRIVATE"; d.hotels[0].roomType = "PRIVATE";
  d.events[0].attendees = "PRIVATE"; d.events[0].description = "PRIVATE"; d.events[0].links = ["https://example.com/PRIVATE"];
  d.events[0].place.overview = "PRIVATE"; d.events[0].place.privateNote = "PRIVATE";
  d.events[0].cost = { amount: 300, currency: "EUR" }; d.templateMeta.authorHandle = "forged"; d.templateMeta.cloneCount = 999;
  const clean = sanitizedTemplate(d, "real_author");
  assert(!JSON.stringify(clean).includes("PRIVATE"));
  assert.equal(clean.templateMeta.authorHandle, "real_author"); assert.equal(clean.templateMeta.cloneCount, 0);
  assert.equal(clean.events[0].cost, undefined);
  d.templateMeta.includesCosts = true;
  assert.equal(sanitizedTemplate(d, "real_author").events[0].cost.amount, 300);
});
Deno.test("summary omits full itinerary and malformed styles or hotel mappings fail", () => {
  const d = structuredClone(seeds[0]);
  const summary = templateSummary({ document: d });
  assert(summary.isSummary); assert.equal(summary.document.events.length, 0); assert.equal(summary.document.stops.length, 3);
  assert.equal(d.events.length, 18);
  d.hotels[0].checkOut = "2000-01-20";
  assert.throws(() => sanitizedTemplate(d, "author"));
  d.templateMeta.tags = ["bad!tag"];
  assert.throws(() => validateDocument(d));
});
Deno.test("country codes and hotel brands survive sharing and reject malformed metadata", () => {
  const d = structuredClone(seeds[0]);
  d.stops[0].countryCode = "MC"; d.hotels[0].place.brand = "Monte-Carlo Société des Bains de Mer";
  validateDocument(d);
  const clean = sanitizedTemplate(d, "editor");
  assert.equal(clean.stops[0].countryCode,"MC");
  assert.equal(clean.hotels[0].place.brand,d.hotels[0].place.brand);
  d.stops[0].countryCode = "Monaco"; assert.throws(()=>validateDocument(d));
  d.stops[0].countryCode = "MC"; d.hotels[0].place.brand = "x".repeat(201); assert.throws(()=>validateDocument(d));
});
