import assert from "node:assert/strict";
import {hotelSearchParams, hotelSummary, hotelText, hotelID, searchHotels, hotelDetails, hotelReviews} from "../functions/travel-api/hotels.ts";
import {Problem} from "../functions/travel-api/validation.ts";
Deno.test("Hotel destination and filters reject unbounded or paid search inputs",()=>{
 for(const q of ["", "latitude=NaN&longitude=1", "latitude=91&longitude=2", "latitude=1&longitude=2&offset=-1", "latitude=1&longitude=2&stars=7"]) assert.throws(()=>hotelSearchParams(new URLSearchParams(q)),Problem);
 const q=hotelSearchParams(new URLSearchParams("latitude=1&longitude=2&stars=4&aiSearch=expensive&limit=5000"));
 assert.equal(q.limit,"20"); assert.equal(q.starRating,"4.0,4.5,5.0"); assert(!("aiSearch" in q));
 assert.throws(()=>hotelID("liteapi:../../bookings"));
});
Deno.test("Hotel content strips HTML, private fields and unsafe photos",()=>{
 assert.equal(hotelText('<script>secret()</script><p>Pool &amp; spa</p>'),"Pool & spa");
 const h=hotelSummary({id:"lp123",name:"Test",main_photo:"https://key:secret@example.com/a",rating:99,latitude:100,privateNote:"secret"})!;
 assert.equal(h.photo,null); assert.equal(h.rating,null); assert.equal(h.latitude,null); assert(!("privateNote" in h));
});
async function stub(body:unknown, run:()=>Promise<void>, status=200) {
 const old=fetch, key=Deno.env.get("LITEAPI_SANDBOX_KEY"); Deno.env.set("LITEAPI_SANDBOX_KEY","test-key");
 globalThis.fetch=((url,init)=>{assert(String(url).startsWith("https://api.liteapi.travel/v3.0/data/"));assert.equal(new Headers(init?.headers).get("X-API-Key"),"test-key"); return Promise.resolve(Response.json(body,{status}));}) as typeof fetch;
 try {await run();} finally {globalThis.fetch=old; if(key===undefined) Deno.env.delete("LITEAPI_SANDBOX_KEY"); else Deno.env.set("LITEAPI_SANDBOX_KEY",key);}
}
Deno.test("Hotel pagination advances over duplicates and invalid rows",async()=>{
 await stub({data:Array.from({length:20},()=>({id:"lp123",name:"Hotel"})),total:50},async()=>{
 const r=await searchHotels(new URLSearchParams("latitude=1&longitude=2")); assert.equal(r.hotels.length,1);assert.equal(r.nextOffset,20);assert(!JSON.stringify(r).includes("test-key"));
 });
});
Deno.test("Rating-only reviews do not pretend to be written reviews or stop pagination",async()=>{
 await stub({data:Array.from({length:20},(_,i)=>({name:"Guest",averageScore:9,pros:i===3?"Good stay":""})),total:41},async()=>{
 const r=await hotelReviews("liteapi:lp123",new URLSearchParams()); assert.equal(r.reviews.length,1);assert.equal(r.nextOffset,20);assert.equal(r.totalRecords,41);
 });
});
Deno.test("Provider errors, throttling and mismatched details fail without leaking bodies",async()=>{
 await stub({error:{message:"secret"}},async()=>{await assert.rejects(()=>searchHotels(new URLSearchParams("latitude=1&longitude=2")),(e:unknown)=>e instanceof Problem&&e.status===502&&!e.message.includes("secret"));});
 await stub({},async()=>{await assert.rejects(()=>hotelDetails("liteapi:lp123"),(e:unknown)=>e instanceof Problem&&e.status===429);},429);
 await stub({data:{id:"lp456",name:"Wrong hotel"}},async()=>{await assert.rejects(()=>hotelDetails("liteapi:lp123"),Problem);});
});
