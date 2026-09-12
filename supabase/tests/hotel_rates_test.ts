import assert from "node:assert/strict";
import {rateRequest, normalizeOffer, minor, searchHotelRates, openQuote, RATE_TTL} from "../functions/travel-api/hotel-rates.ts";
import {Problem} from "../functions/travel-api/validation.ts";
const now = Date.parse("2026-09-10T12:00:00Z"), owner = "owner-one";
const body = () => ({hotelIds:["liteapi:lp123"],checkin:"2026-10-01",checkout:"2026-10-04",currency:"USD",guestNationality:"US",occupancies:[{adults:2,children:[]}],detail:true});
const context = () => rateRequest(body(),now).criteria;
function raw(): any {return {offerId:"opaque-supplier-id",rateType:"standard",offerRetailRate:{amount:"100.10",currency:"USD"},suggestedSellingPrice:{amount:"100.00",currency:"USD"},rates:[{occupancyNumber:1,name:"King ocean view",mappedRoomId:123,adultCount:2,childCount:0,childrenAges:[],maxOccupancy:2,boardType:"BI",boardName:"Breakfast",paymentTypes:["NUITEE_PAY"],retailRate:{total:[{amount:"100.10",currency:"USD"}],taxesAndFees:[{included:true,amount:"10.00",currency:"USD",description:"Included tax"},{included:false,amount:"0.20",currency:"USD",description:"City tax"}]},cancellationPolicies:{refundableTag:"RFN",cancelPolicyInfos:[{cancelTime:"2026-09-30 12:00:00",timezone:"GMT",type:"amount",amount:"100.10",currency:"USD"}]}}]};}
Deno.test("Rate criteria require exact dates, rooms, nationality and bounded occupancy",()=>{
 for (const change of [{checkin:"2026-02-30"},{checkout:"2026-10-01"},{checkout:"2027-01-01"},{guestNationality:"ZZ"},{currency:"BTC"},{occupancies:[{adults:0,children:[]}]},{occupancies:[{adults:2,children:[-1]}]},{occupancies:Array(9).fill({adults:2,children:[]})},{hotelIds:Array(21).fill("liteapi:lp123")},{detail:true,hotelIds:["liteapi:lp123","liteapi:lp456"]}]) assert.throws(()=>rateRequest({...body(),...change},now),Problem);
 const request=rateRequest({...body(),margin:99,environment:"production",aiSearch:"expensive",supplierURL:"https://bad.test"},now);
 assert.equal(JSON.stringify(request).includes("margin"),false);assert.equal(request.criteria.occupancies[0].adults,2);
});
Deno.test("Money adds exact minor units without double counting included fees",()=>{
 const r=normalizeOffer(raw(),"liteapi:lp123",context(),now)!;assert.equal(r.base.amount,"100.10");assert.equal(r.total!.amount,"100.30");assert.equal(r.fees.length,2);assert.equal(r.freeCancellationUntil,"2026-09-30T12:00:00.000Z");
 assert.equal(minor("0.1","USD"),10n);assert.equal(minor("1.234","KWD"),1234n);assert.equal(minor("100","JPY"),100n);assert.equal(minor("1.23","JPY"),null);assert.equal(minor("NaN","USD"),null);
});
Deno.test("Foreign and unknown property fees prevent an unqualified total",()=>{
 const o=raw();o.rates[0].retailRate.taxesAndFees[1].currency="EUR";
 assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now)!.total,null);
 o.rates[0].retailRate.taxesAndFees[1].amount="pay locally";
 const n=normalizeOffer(o,"liteapi:lp123",context(),now)!;assert.equal(n.total,null);assert.equal(n.fees[1].charge,null);
});
Deno.test("Offer eligibility preserves public floor and excludes package-only or mismatched rooms",()=>{
 const o=raw();o.suggestedSellingPrice.amount="120.00";assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now)!.publicPriceEligible,false);
 o.rateType="package";assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now),null);
 o.rateType="standard";o.rates[0].adultCount=1;assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now),null);
 o.rates[0].adultCount=2;o.rates[0].childCount=1;o.rates[0].childrenAges=[5];assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now),null);
});
Deno.test("Multi-room totals count every room and reject inconsistent aggregate or duplicate occupancy",()=>{
 const o=raw(),c=context();c.occupancies.push({adults:1,children:[7]});const second=structuredClone(o.rates[0]);second.occupancyNumber=2;second.adultCount=1;second.childCount=1;second.childrenAges=[7];o.rates.push(second);o.offerRetailRate.amount="200.20";
 const n=normalizeOffer(o,"liteapi:lp123",c,now)!;assert.equal(n.rooms.length,2);assert.equal(n.total!.amount,"200.60");
 o.offerRetailRate.amount="100.10";assert.equal(normalizeOffer(o,"liteapi:lp123",c,now),null);
 o.offerRetailRate.amount="200.20";second.occupancyNumber=1;assert.equal(normalizeOffer(o,"liteapi:lp123",c,now),null);
});
Deno.test("Unknown time zones and elapsed penalties never promise free cancellation",()=>{
 const o=raw();delete o.rates[0].cancellationPolicies.cancelPolicyInfos[0].timezone;
 assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now)!.freeCancellationUntil,null);
 o.rates[0].cancellationPolicies.cancelPolicyInfos[0].timezone="GMT";o.rates[0].cancellationPolicies.cancelPolicyInfos[0].cancelTime="2026-09-09 12:00:00";
 assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now)!.freeCancellationUntil,null);
});
async function stub(value:any,run:()=>Promise<void>,status=200){const saved=fetch,key=Deno.env.get("LITEAPI_SANDBOX_KEY"),secret=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");Deno.env.set("LITEAPI_SANDBOX_KEY","sandbox-test");Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","test-seal-key");globalThis.fetch=async (url,init)=>{assert.equal(String(url),"https://api.liteapi.travel/v3.0/hotels/rates");const sent=JSON.parse(String(init?.body));assert(!("margin"in sent));assert.equal(sent.roomMapping,true);return status===204?new Response(null,{status}):Response.json(value,{status});};try{await run();}finally{globalThis.fetch=saved;key===undefined?Deno.env.delete("LITEAPI_SANDBOX_KEY"):Deno.env.set("LITEAPI_SANDBOX_KEY",key);secret===undefined?Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY"):Deno.env.set("SUPABASE_SERVICE_ROLE_KEY",secret);}}
Deno.test("Quotes are opaque, owner bound, tamper resistant and expire on the server",async()=>{
 await stub({sandbox:true,data:[{hotelId:"lp123",roomTypes:[raw()]}]},async()=>{
  const page=await searchHotelRates(rateRequest(body(),now),owner);const q=page.hotels[0].offers[0].quote;assert(!q.includes("opaque-supplier-id"));
  assert.equal((await openQuote(q,owner)).supplierOfferId,"opaque-supplier-id");
  await assert.rejects(()=>openQuote(q,"another-owner"),(e:any)=>e.status===404);
  await assert.rejects(()=>openQuote(q.slice(0,30)+"!"+q.slice(31),owner),Problem);
  await assert.rejects(()=>openQuote(q,owner,Date.now()+RATE_TTL+1000),(e:any)=>e.status===410);
 });
});
Deno.test("Rate failures are distinct from successful empty availability and sanitize provider bodies",async()=>{
 await stub(null,async()=>{const p=await searchHotelRates(rateRequest(body(),now),owner);assert.equal(p.hotels[0].status,"unavailable");},204);
 await stub({error:{message:"key=secret"}},async()=>{await assert.rejects(()=>searchHotelRates(rateRequest(body(),now),owner),(e:any)=>e.status===502&&!e.message.includes("secret"));});
 await stub({},async()=>{await assert.rejects(()=>searchHotelRates(rateRequest(body(),now),owner),(e:any)=>e.status===429);},429);
});
Deno.test("Summary chooses the lowest complete customer total, not the cheapest room subtotal",async()=>{
 const a=raw(),b=raw();a.offerId="a";b.offerId="b";a.rates[0].retailRate.taxesAndFees[1].amount="50.00";b.rates[0].retailRate.total[0].amount="110.10";b.offerRetailRate.amount="110.10";
 await stub({sandbox:true,data:[{hotelId:"lp123",roomTypes:[a,b]}]},async()=>{const p=await searchHotelRates(rateRequest({...body(),detail:false},now),owner);assert.equal(p.hotels[0].offers.length,1);assert.equal(p.hotels[0].offers[0].total.amount,"110.30");});
});
Deno.test("Sandbox adapter refuses a production response and missing total details never become zero",async()=>{
 await stub({sandbox:false,data:[{hotelId:"lp123",roomTypes:[raw()]}]},async()=>{await assert.rejects(()=>searchHotelRates(rateRequest(body(),now),owner),Problem);});
 const o=raw();delete o.rates[0].retailRate.total;assert.equal(normalizeOffer(o,"liteapi:lp123",context(),now),null);
});
Deno.test("Unknown fee timing stays unknown and room packages require a common payment method",()=>{
 const o=raw();delete o.rates[0].retailRate.taxesAndFees[1].included;
 const n=normalizeOffer(o,"liteapi:lp123",context(),now)!;assert.equal(n.total,null);assert.equal(n.fees[1].included,null);
 const c=context();c.occupancies.push({adults:2,children:[]});o.rates.push(structuredClone(o.rates[0]));o.rates[1].occupancyNumber=2;o.offerRetailRate.amount="200.20";o.rates[1].paymentTypes=["PROPERTY_PAY"];
 assert.equal(normalizeOffer(o,"liteapi:lp123",c,now),null);
});
