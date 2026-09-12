import assert from 'node:assert/strict';
Deno.env.set('SUPABASE_URL','https://cancel.test');Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','test-only');Deno.env.set('LITEAPI_SANDBOX_KEY','sand_test');
const {cancellationSnapshot,acceptHotelCancellation,runHotelCancellation,prepareHotelCancellation}=await import('../functions/travel-api/hotel-cancellations.ts');
const {normalizeOffer}=await import('../functions/travel-api/hotel-rates.ts');
const owner='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const criteria={checkin:'2026-10-10',checkout:'2026-10-13',currency:'USD',guestNationality:'US',occupancies:[{adults:2,children:[]}]};
const rate={occupancyNumber:1,name:'King',adultCount:2,childCount:0,childrenAges:[],boardName:'Room only',boardType:'RO',paymentTypes:['NUITEE_PAY'],retailRate:{total:[{amount:100,currency:'USD'}],taxesAndFees:[]},cancellationPolicies:{refundableTag:'NRFN',cancelPolicyInfos:[],hotelRemarks:[]}};
function row():any{return {id,owner,state:'confirmed',environment:'sandbox',accepted_at:new Date().toISOString(),updated_at:new Date().toISOString(),lease_token:crypto.randomUUID(),booking:{id:'test-booking'},prebook_id:'test-prebook',client_reference:'test-reference',cancellation_attempts:1,review:{criteria,offer:normalizeOffer({offerId:'test',rateType:'standard',rates:[rate]},'liteapi:lp123',criteria)}};}
function data(r:any,status='CONFIRMED'){return {sandbox:1,bookingId:r.booking.id,clientReference:r.client_reference,prebookId:r.prebook_id,status,hotel:{hotelId:'lp123',name:'Example'},checkin:criteria.checkin,checkout:criteria.checkout,currency:'USD',price:100,bookedRooms:[{roomType:{name:'King'},adults:2,children:0,childrenAges:[],boardName:'Room only',rate}]};}
Deno.test('Cancellation review expires at the next policy deadline and blocks imminent boundaries',async()=>{
 const r=row(),now=Date.now();r.review.offer.rooms[0].cancellation.penalties=[{from:new Date(now+60000).toISOString()}];
 assert.equal(Date.parse((await cancellationSnapshot(r,now)).expiresAt),now+60000);
 r.review.offer.rooms[0].cancellation.penalties[0].from=new Date(now+5000).toISOString();await assert.rejects(()=>cancellationSnapshot(r,now));
 await assert.rejects(()=>acceptHotelCancellation(owner,id,{version:crypto.randomUUID(),acceptTestCancellation:false}));
});
Deno.test('Cancellation worker submits once, verifies GET result, and only looks up after uncertainty',async()=>{
 const saved=globalThis.fetch;const r=row();r.cancellation=await cancellationSnapshot(r);let mode='success',put=0,gets=0,patch:any;
 globalThis.fetch=async(input,init)=>{
  const url=new URL(String(input));
  if(url.hostname==='book.liteapi.travel'){
   assert(url.pathname.endsWith('/bookings/test-booking'));
   if(init?.method==='PUT'){put++;if(mode==='timeout')throw Error('timeout');return new Response(null,{status:204});}
   assert.equal(init?.method,'GET');gets++;
   const payload=data(r,(put>0&&mode==='success')||mode==='charged'?'CANCELLED_WITH_CHARGES':'CONFIRMED');if(mode==='changed')payload.bookedRooms[0].adults=1;
   if(mode==='wrong')payload.bookingId='other';return Response.json({data:payload});
  }
  if(url.pathname.endsWith('/travel_limit'))return Response.json(true);
  if(init?.method==='PATCH'){patch=JSON.parse(String(init.body));assert.equal(url.searchParams.get('lease_token'),'eq.'+r.lease_token);return Response.json([{...r,...patch}]);}
  if(url.pathname.endsWith('/travel_hotel_checkouts'))return Response.json([r]);
  throw Error('Unexpected call');
 };
 try {
  await runHotelCancellation({checkout:r,operation:'cancel'});assert.equal(put,1);assert.equal(gets,2);assert.equal(patch.state,'cancelled');assert.equal(patch.cancellation.state,'cancelled');
  mode='timeout';put=0;await runHotelCancellation({checkout:r,operation:'cancel'});assert.equal(put,1);assert.equal(patch.cancellation.state,'pending');
  await runHotelCancellation({checkout:r,operation:'lookup'});assert.equal(put,1);assert.equal(patch.cancellation.state,'pending');
  mode='changed';put=0;await runHotelCancellation({checkout:r,operation:'cancel'});assert.equal(put,0);assert.equal(patch.cancellation.state,'changed');
  mode='charged';await runHotelCancellation({checkout:r,operation:'lookup'});assert.equal(patch.state,'cancelled');assert.equal(patch.review.providerStatus,'CANCELLED_WITH_CHARGES');
  mode='wrong';r.cancellation_attempts=10;await runHotelCancellation({checkout:r,operation:'lookup'});assert.equal(patch.cancellation.state,'needs_support');
  r.cancellation.state='pending';const count=gets;assert.equal((await prepareHotelCancellation(owner,id)).cancellation?.state,'pending');assert.equal(gets,count);
 } finally {globalThis.fetch=saved;}
});
