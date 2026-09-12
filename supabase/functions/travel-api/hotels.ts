import { Problem, requireValue, safeURL } from "./validation.ts";

// Content-only adapter. No rates, payments, Places/AI search or booking endpoints.
export const hotelsConfigured = () => !!Deno.env.get("LITEAPI_SANDBOX_KEY");
const list = (v: unknown): any[] => Array.isArray(v) ? v : [];
export function hotelText(v: unknown, max = 15000): string {
  if (typeof v !== "string") return "";
  return v.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, "").replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<\/?(?:p|div|br|li|h[1-6])\b[^>]*>/gi, "\n").replace(/<[^>]*>/g, "")
    .replace(/&(?:amp|lt|gt|quot|apos|nbsp);/g, x => ({"&amp;":"&", "&lt;":"<", "&gt;":">", "&quot;":'"', "&apos;":"'", "&nbsp;":" "}[x]!))
    .replace(/&#(x[0-9a-f]+|\d+);/gi, (_, n) => { const v = n[0].toLowerCase() === "x" ? parseInt(n.slice(1),16) : Number(n); return v > 0 && v <= 0x10ffff ? String.fromCodePoint(v) : ""; })
    .trim().slice(0,max);
}
const number = (v: unknown, min: number, max: number): number | null => {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() ? Number(v) : NaN;
  return Number.isFinite(n) && n >= min && n <= max ? n : null;
};
const photoURL = (v: unknown) => safeURL(v) && String(v).startsWith("https://") ? String(v) : null;
export function hotelID(id: string): string {
  requireValue(/^liteapi:lp[a-z0-9]{1,60}$/i.test(id), "Invalid hotel identifier.");
  return id.slice(8);
}
function offset(q: URLSearchParams): number {
  const v = q.get("offset") ?? "0";
  requireValue(/^\d{1,5}$/.test(v) && Number(v) <= 10000, "Invalid page.");
  return Number(v);
}
export function hotelSearchParams(q: URLSearchParams): Record<string,string> {
  const latitude = number(q.get("latitude"), -90,90), longitude = number(q.get("longitude"), -180,180);
  requireValue(latitude !== null && longitude !== null, "Choose a destination first.");
  const name = (q.get("name") ?? "").trim();
  requireValue(name.length <= 100, "Hotel name is too long.");
  const stars = q.get("stars") ?? "", score = q.get("score") ?? "";
  requireValue(["", "4", "5"].includes(stars) && ["", "8", "9"].includes(score), "Invalid hotel filters.");
  return { latitude: String(latitude), longitude: String(longitude), radius: "15000", limit: "20", offset: String(offset(q)),
    ...(name ? {hotelName: name} : {}), ...(stars ? {starRating: stars === "4" ? "4.0,4.5,5.0" : "5.0"} : {}), ...(score ? {minRating: score} : {}) };
}
async function get(route: string, params: Record<string,string>) {
  const key = Deno.env.get("LITEAPI_SANDBOX_KEY");
  requireValue(key, "Hotel discovery is not configured yet.", 503);
  const url = new URL("https://api.liteapi.travel/v3.0/data/" + route);
  url.search = new URLSearchParams({...params, timeout:"10"}).toString();
  try {
    const response = await fetch(url, {headers: {"X-API-Key": key!, Accept:"application/json"}, signal: AbortSignal.timeout(15000), redirect:"error"});
    if (response.status === 429) throw new Problem("Hotel search is busy. Please try again shortly.",429);
    if (!response.ok) throw new Problem("Hotel information is temporarily unavailable. Please try again.",502);
    const data = await response.json();
    if (!data || data.error || data.errors || data.data == null) throw new Problem("Hotel information is temporarily unavailable. Please try again.",502);
    return data;
  } catch (e) { if (e instanceof Problem) throw e; throw new Problem("Hotel information is temporarily unavailable. Please try again.",502); }
}
export function hotelSummary(h: any) {
  if (!h || !/^lp[a-z0-9]{1,60}$/i.test(h.id) || !hotelText(h.name,300)) return null;
  return { id:"liteapi:"+h.id, name:hotelText(h.name,300), city:hotelText(h.city,150), country:hotelText(h.country,100), address:hotelText(h.address,500),
    latitude:number(h.latitude ?? h.location?.latitude,-90,90), longitude:number(h.longitude ?? h.location?.longitude,-180,180),
    stars:number(h.starRating ?? h.stars,0,5), rating:number(h.rating,0,10), reviewCount:number(h.reviewCount,0,1e9),
    photo:photoURL(h.main_photo ?? h.thumbnail), source:"LiteAPI / Nuitée" };
}
function photos(values: unknown) {
  const seen = new Set<string>();
  return list(values).flatMap(p => { const url = photoURL(typeof p === "string" ? p : p?.urlHd ?? p?.url); return url && !seen.has(url) ? (seen.add(url), [{url, caption:hotelText(p?.caption,300)}]) : []; }).slice(0,400);
}
function nextPage(data: any, skip: number, length: number) {
  const total = number(data.total,0,1e9);
  return length >= 20 && skip + length <= 10000 && (total === null || skip + length < total) ? skip + length : null;
}
export async function searchHotels(q: URLSearchParams) {
  const params = hotelSearchParams(q), data = await get("hotels",params);
  requireValue(Array.isArray(data.data), "Invalid hotel response.",502);
  const seen = new Set<string>();
  const hotels = data.data.map(hotelSummary).filter((h: any) => h && !seen.has(h.id) && seen.add(h.id));
  return {hotels, nextOffset:nextPage(data,Number(params.offset),data.data.length), environment:"sandbox"};
}
export async function hotelDetails(id: string) {
  const data = await get("hotel",{hotelId:hotelID(id)}), h = data.data, hotel = hotelSummary(h);
  requireValue(hotel && hotel.id === id, "Hotel details could not be found.",502);
  return { hotel, description:hotelText(h.hotelDescription), importantInformation:hotelText(h.hotelImportantInformation),
    photos:photos(h.hotelImages), facilities: list(h.hotelFacilities).map(x=>hotelText(typeof x === "string" ? x : x?.name,200)).filter(Boolean).slice(0,150),
    rooms:list(h.rooms).slice(0,100).map((r,i)=>({id:String(r.id ?? i),name:hotelText(r.roomName,300),description:hotelText(r.description),photos:photos(r.photos),maxOccupancy:number(r.maxOccupancy,1,100),size:number(r.roomSizeSquare,0,1e5),sizeUnit:hotelText(r.roomSizeUnit,40)})),
    environment:"sandbox" };
}
export async function hotelReviews(id: string, q: URLSearchParams) {
  const skip = offset(q), data = await get("reviews",{hotelId:hotelID(id),offset:String(skip),limit:"20"});
  requireValue(Array.isArray(data.data), "Invalid review response.",502);
  return { reviews:data.data.flatMap((r:any,i:number)=>{
    const headline=hotelText(r.headline,1000), pros=hotelText(r.pros,12000), cons=hotelText(r.cons,12000);
    if (!headline && !pros && !cons) return [];
    return [{id:id+":"+(skip+i),name:hotelText(r.name,150),date:hotelText(r.date,50),rating:number(r.averageScore,0,10),headline,pros,cons,source:hotelText(r.source,150)||"Nuitée",travelerType:hotelText(r.type,100)}];
  }), nextOffset:nextPage(data,skip,data.data.length), totalRecords:number(data.total,0,1e9) };
}
