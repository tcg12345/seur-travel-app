import { Problem, requireValue } from "./validation.ts";
import { hotelID, hotelText, hotelsConfigured } from "./hotels.ts";

// Sandbox-only read model. No reservations, prebooks or payments are submitted here.
export const RATE_TTL = 5 * 60_000;
export const rateCurrencies = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "SGD", "THB", "AED", "HKD", "NZD", "INR", "KWD", "BHD"];
export const countries = new Set("AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW".split(" "));
const currencies = new Set(Intl.supportedValuesOf("currency"));
const array = (v: unknown): any[] => Array.isArray(v) ? v : [];
export type Occupancy = { adults: number; children: number[] };
export type RateCriteria = { checkin: string; checkout: string; currency: string; guestNationality: string; occupancies: Occupancy[] };
export function rateRequest(body: any, now = Date.now()) {
  requireValue(body && typeof body === "object", "Choose your stay details.");
  const date = (v: unknown) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v) && Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0,10) === v;
  requireValue(date(body.checkin) && date(body.checkout), "Choose valid stay dates.");
  const start = Date.parse(body.checkin), end = Date.parse(body.checkout), today = Math.floor(now / 86400000) * 86400000;
  requireValue(start >= today - 86400000 && start <= today + 730 * 86400000 && end > start && end - start <= 30 * 86400000, "Choose a stay of 1–30 nights within the next two years.");
  requireValue(rateCurrencies.includes(body.currency), "Choose a supported currency.");
  requireValue(countries.has(body.guestNationality), "Choose the lead guest's nationality.");
  requireValue(Array.isArray(body.occupancies) && body.occupancies.length >= 1 && body.occupancies.length <= 8, "Choose 1–8 rooms.");
  const occupancies: Occupancy[] = body.occupancies.map((o: any) => {
    requireValue(o && Number.isInteger(o.adults) && o.adults >= 1 && o.adults <= 8, "Each room needs 1–8 adults.");
    requireValue(Array.isArray(o.children) && o.children.length <= 4 && o.children.every((a: any) => Number.isInteger(a) && a >= 0 && a <= 17), "Enter every child's age from 0–17.");
    return { adults: o.adults, children: [...o.children] };
  });
  requireValue(occupancies.reduce((s,o) => s + o.adults + o.children.length,0) <= 24, "Search for up to 24 guests at once.");
  requireValue(Array.isArray(body.hotelIds) && body.hotelIds.length >= 1 && body.hotelIds.length <= 20 && body.hotelIds.every((x: any) => typeof x === "string"), "Search up to 20 hotels at once.");
  const hotelIds = [...new Set<string>(body.hotelIds)]; hotelIds.forEach(hotelID);
  requireValue(body.detail === undefined || typeof body.detail === "boolean", "Invalid rate search.");
  requireValue(!body.detail || hotelIds.length === 1, "Open one hotel to see its room options.");
  const criteria: RateCriteria = {checkin: body.checkin, checkout: body.checkout, currency: body.currency, guestNationality: body.guestNationality, occupancies};
  return { hotelIds, detail: body.detail === true, criteria };
}
export type Money = { amount: string; currency: string };
function digits(currency: string) { return new Intl.NumberFormat("en",{style:"currency",currency}).resolvedOptions().maximumFractionDigits!; }
export function minor(value: unknown, currency: string): bigint | null {
  if (!currencies.has(currency) || (typeof value !== "number" && typeof value !== "string")) return null;
  const s = String(value); if (!/^\d{1,10}(?:\.\d{1,6})?$/.test(s)) return null;
  const [whole, fraction = ""] = s.split("."), d = digits(currency);
  if (fraction.slice(d).replace(/0/g, "")) return null;
  return BigInt(whole) * 10n ** BigInt(d) + BigInt(fraction.slice(0,d).padEnd(d,"0") || "0");
}
function money(n: bigint, currency: string): Money {
  const d = digits(currency), s = n.toString().padStart(d + 1,"0");
  return {amount: d ? s.slice(0,-d) + "." + s.slice(-d) : s, currency};
}
function readMoney(v: any, currency?: string): Money | null {
  if (!v || typeof v.currency !== "string" || (currency && v.currency !== currency)) return null;
  const n = minor(v.amount,v.currency); return n === null ? null : money(n,v.currency);
}
function oneMoney(v: any, currency: string): Money | null {
  const values = Array.isArray(v) ? v : v ? [v] : [];
  const matching = values.filter(x => x?.currency === currency);
  return matching.length === 1 ? readMoney(matching[0],currency) : null;
}
const sum = (values: Money[], currency: string) => money(values.reduce((s,m) => s + minor(m.amount,currency)!,0n),currency);
function instant(value: any, zone: any): string | null {
  if (typeof value !== "string") return null;
  const explicit = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(value);
  if (zone && !["GMT","UTC"].includes(zone)) return null;
  if (explicit && zone && !/(?:Z|[+-]00:?00)$/i.test(value)) return null;
  if (!explicit && !["GMT","UTC"].includes(zone)) return null;
  const raw = explicit ? value : value.replace(" ","T") + "Z", time = Date.parse(raw);
  return Number.isFinite(time) ? new Date(time).toISOString() : null;
}
export function cancellation(policy: any, now: number) {
  const tag = policy?.refundableTag;
  const raw = array(policy?.cancelPolicyInfos);
  const penalties = raw.map(p => ({from: instant(p?.cancelTime,p?.timezone), charge: p?.type === "amount" ? readMoney(p) : null, text: hotelText(p?.cancelTime,80) + (p?.timezone ? " " + hotelText(p.timezone,50) : "") }));
  const positive = penalties.filter(p => p.charge && minor(p.charge.amount,p.charge.currency)! > 0n);
  const reliable = raw.length > 0 && penalties.every(p => p.from && p.charge);
  const firstPenalty = reliable && positive.length ? positive.map(p => p.from!).sort()[0] : null;
  const freeUntil = tag === "RFN" && firstPenalty && Date.parse(firstPenalty) > now ? firstPenalty : null;
  return { nonrefundable: tag === "NRFN", freeUntil, penalties, remarks: array(policy?.hotelRemarks).map(x => hotelText(x,1000)).filter(Boolean) };
}
export function packageRestricted(value: unknown): boolean {
  return /must (?:only )?be sold as part of a package|package[ -]only|only (?:sold|available) (?:as|in) (?:a )?package/i.test(hotelText(value,30000));
}
export function normalizeOffer(offer: any, hotelId: string, criteria: RateCriteria, now = Date.now()) {
  if (!offer || typeof offer.offerId !== "string" || !offer.offerId.length || offer.offerId.length > 30000 || offer.rateType !== "standard") return null;
  const rates = array(offer.rates);
  if (rates.length !== criteria.occupancies.length) return null;
  const used = new Set<number>(), rooms: any[] = [], totals: Money[] = [], fees: any[] = [], floors: Money[] = [];
  let complete = true, roomFloorsMet = true;
  for (const r of rates) {
    if (packageRestricted(r?.remarks) || array(r?.cancellationPolicies?.hotelRemarks).some(packageRestricted)) return null;
    const index = r?.occupancyNumber;
    if (!Number.isInteger(index) || index < 1 || index > rates.length || used.has(index)) return null;
    used.add(index); const wanted = criteria.occupancies[index - 1];
    if (r.adultCount !== wanted.adults || r.childCount !== wanted.children.length || !Array.isArray(r.childrenAges) || JSON.stringify([...r.childrenAges].sort()) !== JSON.stringify([...wanted.children].sort()) || !r.name) return null;
    if (r.maxOccupancy != null && (!Number.isInteger(r.maxOccupancy) || r.maxOccupancy < wanted.adults + wanted.children.length)) return null;
    const total = oneMoney(r.retailRate?.total,criteria.currency); if (!total || minor(total.amount,total.currency)! <= 0n) return null;
    totals.push(total);
    const floor = oneMoney(r.retailRate?.suggestedSellingPrice,criteria.currency);
    if (r.retailRate?.suggestedSellingPrice != null && (!Array.isArray(r.retailRate.suggestedSellingPrice) || r.retailRate.suggestedSellingPrice.length > 0) && !floor) return null;
    if (floor) { floors.push(floor); if (minor(total.amount,total.currency)! < minor(floor.amount,floor.currency)!) roomFloorsMet = false; }
    if (array(r.retailRate?.taxesAndFees).length > 50 || array(r.cancellationPolicies?.cancelPolicyInfos).length > 50 || array(r.cancellationPolicies?.hotelRemarks).length > 20) return null;
    if (!Array.isArray(r.retailRate?.taxesAndFees)) complete = false;
    for (const f of array(r.retailRate?.taxesAndFees)) {
      const charge = readMoney(f); if (typeof f?.included !== "boolean" || !charge) complete = false;
      fees.push({description: hotelText(f?.description,200) || "Hotel charge", included: typeof f?.included === "boolean" ? f.included : null, charge, room: index});
      if (f?.included !== true && (!charge || charge.currency !== criteria.currency)) complete = false;
    }
    const payments = array(r.paymentTypes ?? offer.paymentTypes).filter(x => ["NUITEE_PAY","PROPERTY_PAY"].includes(x));
    if (!payments.length) return null;
    const policy = cancellation(r.cancellationPolicies,now);
    rooms.push({number:index, name:hotelText(r.name,300), mappedRoomId:r.mappedRoomId == null ? null : String(r.mappedRoomId), adults:wanted.adults, children:wanted.children, board:hotelText(r.boardName,100) || hotelText(r.boardType,30), breakfast:["BI","BB","HB","FB","AI","TI","BD","BL","BDI","BLI"].includes(r.boardType), paymentTypes:payments, cancellation:policy, remarks:hotelText(r.remarks,3000), perks:array(r.perks).map(p=>hotelText(p?.name,200)).filter(Boolean).slice(0,20)});
  }
  rooms.sort((a,b) => a.number-b.number);
  const commonPayments = rooms[0].paymentTypes.filter((p: string) => rooms.every(r => r.paymentTypes.includes(p)));
  if (!commonPayments.length) return null;
  rooms.forEach(r => { r.paymentTypes = commonPayments; });
  const base = sum(totals,criteria.currency), provided = oneMoney(offer.offerRetailRate,criteria.currency);
  if (offer.offerRetailRate != null && (!provided || provided.amount !== base.amount)) return null;
  const topFloor = oneMoney(offer.suggestedSellingPrice,criteria.currency);
  if (offer.suggestedSellingPrice != null && !topFloor) return null;
  const floor = topFloor ?? (floors.length ? sum(floors,criteria.currency) : null);
  const propertyFees = fees.filter(f=>f.included === false && f.charge).map(f=>f.charge as Money);
  const total = complete ? sum([base,...propertyFees],criteria.currency) : null;
  return {hotelId, rooms, base, total, fees, publicPriceEligible: roomFloorsMet && (!floor || minor(base.amount,base.currency)! >= minor(floor.amount,floor.currency)!), publicPriceFloor:floor, breakfast:rooms.every(r=>r.breakfast), freeCancellationUntil:rooms.every(r=>r.cancellation.freeUntil) ? rooms.map(r=>r.cancellation.freeUntil).sort()[0] as string : null, expiresAt:new Date(now + RATE_TTL).toISOString()};
}
// Opaque, owner-bound, authenticated quote handoff. Never an authority to charge.
async function quoteKey() {
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"); requireValue(secret,"Rate quotes are unavailable.",503);
  const raw = await crypto.subtle.digest("SHA-256",new TextEncoder().encode("seur-hotel-quote-v1:" + secret));
  return crypto.subtle.importKey("raw",raw,"AES-GCM",false,["encrypt","decrypt"]);
}
const encode = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"");
async function seal(value: unknown) {
  const iv = crypto.getRandomValues(new Uint8Array(12)), cipher = new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},await quoteKey(),new TextEncoder().encode(JSON.stringify(value))));
  return "hq1." + encode(iv) + "." + encode(cipher);
}
export async function openQuote(token: unknown, owner: string, now = Date.now()) {
  try {
    requireValue(typeof token === "string" && token.length < 100000,"Invalid rate quote.",400);
    const [version,iv,cipher,...extra] = (token as string).split("."); requireValue(version === "hq1" && !extra.length,"Invalid rate quote.",400);
    const decode = (s: string) => Uint8Array.from(atob(s.replace(/-/g,"+").replace(/_/g,"/")),c=>c.charCodeAt(0));
    const plain = await crypto.subtle.decrypt({name:"AES-GCM",iv:decode(iv)},await quoteKey(),decode(cipher));
    const value = JSON.parse(new TextDecoder().decode(plain));
    requireValue(value.owner === owner && value.environment === "sandbox","This rate quote is unavailable.",404);
    requireValue(Date.parse(value.offer.expiresAt) > now,"This rate has expired. Refresh room options.",410);
    return value;
  } catch (e) { if (e instanceof Problem) throw e; throw new Problem("Invalid rate quote.",400); }
}
export async function searchHotelRates(request: ReturnType<typeof rateRequest>, owner: string) {
  requireValue(hotelsConfigured(),"Hotel rates are not configured yet.",503);
  const {criteria,hotelIds,detail} = request;
  let data: any;
  try {
    const response = await fetch("https://api.liteapi.travel/v3.0/hotels/rates",{method:"POST",headers:{"X-API-Key":Deno.env.get("LITEAPI_SANDBOX_KEY")!,"Content-Type":"application/json",Accept:"application/json"},body:JSON.stringify({...criteria,hotelIds:hotelIds.map(hotelID),maxRatesPerHotel:detail ? 40 : 20,timeout:8,roomMapping:true}),signal:AbortSignal.timeout(18000),redirect:"error"});
    if (response.status === 429) throw new Problem("Rate search is busy. Try again shortly.",429);
    if (response.status === 204) data = {data:[]};
    else {
      requireValue(response.ok,"Prices are temporarily unavailable. Try again.",502);
      data = await response.json();
      requireValue(data && data.sandbox === true && !data.error && !data.errors && Array.isArray(data.data),"Prices are temporarily unavailable. Try again.",502);
    }
  } catch (e) { if (e instanceof Problem) throw e; throw new Problem("Prices are temporarily unavailable. Try again.",502); }
  const now = Date.now(), hotels: any[] = [];
  for (const hotelId of hotelIds) {
    const raw = data.data.filter((h:any)=>h?.hotelId === hotelID(hotelId)).flatMap((h:any)=>array(h.roomTypes));
    const normalized = raw.flatMap((o:any)=>{const n = normalizeOffer(o,hotelId,criteria,now);return n ? [{offer:n,rawID:o.offerId}] : [];});
    normalized.sort((a:any,b:any)=>{
      if (!!a.offer.total !== !!b.offer.total) return a.offer.total ? -1 : 1;
      const av=minor((a.offer.total ?? a.offer.base).amount,criteria.currency)!,bv=minor((b.offer.total ?? b.offer.base).amount,criteria.currency)!;
      return av === bv ? a.rawID.localeCompare(b.rawID) : av < bv ? -1 : 1;
    });
    const seen = new Set<string>(), offers: any[] = [];
    for (const item of normalized) {
      const key = JSON.stringify([item.offer.rooms,item.offer.base,item.offer.total,item.offer.fees,item.offer.publicPriceEligible]);
      if (seen.has(key)) continue; seen.add(key);
      const id = crypto.randomUUID();
      const quote = await seal({owner,environment:"sandbox",pricingPolicy:"account-default-sandbox-v1",criteria,supplierOfferId:item.rawID,offer:{id,...item.offer}});
      offers.push({id,...item.offer,quote});
      if (!detail || offers.length >= 40) break;
    }
    hotels.push({hotelId,offers,status:offers.length ? "available" : raw.length ? "noEligibleOffers" : "unavailable"});
  }
  return {hotels,criteria,environment:"sandbox",expiresAt:new Date(now + RATE_TTL).toISOString(),checkoutEnabled:false};
}
