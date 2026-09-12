import {requireValue, uuid} from './validation.ts';
import {digest, limit, rpc} from './platform.ts';
import {hotelSupplier, ownedCheckout, safeCheckout, finishCheckout, verifiedBooking, synchronizedBooking} from './hotel-checkouts.ts';

const pendingStates=['queued','submitting','pending','cancelled','needs_support'];
export async function cancellationSnapshot(row:any, now=Date.now()) {
 const policy=row.review.offer.rooms.map((r:any)=>r.cancellation);
 const boundaries=policy.flatMap((p:any)=>p.penalties.map((v:any)=>Date.parse(v.from))).filter((t:number)=>Number.isFinite(t)&&t>now);
 const expiry=Math.min(now+300000,...boundaries);
 requireValue(expiry-now>=10000,'A cancellation deadline is approaching. Wait and check the updated terms.',409);
 return {state:'review',version:crypto.randomUUID(),checkedAt:new Date(now).toISOString(),expiresAt:new Date(expiry).toISOString(),termsHash:await digest(JSON.stringify(policy))};
}
export async function prepareHotelCancellation(owner:string,id:string) {
 const row=await ownedCheckout(owner,id);
 if(pendingStates.includes(row.cancellation?.state))return safeCheckout(row);
 requireValue(row.state==='confirmed' && row.booking?.id && row.environment==='sandbox','Only a verified test booking can be cancelled here.',409);
 await limit('hotel-cancellation:'+id,1,15);
 const data=await hotelSupplier('bookings/'+encodeURIComponent(row.booking.id));
 requireValue(verifiedBooking(data,row) && data.bookingId===row.booking.id && data.prebookId===row.prebook_id,'Booking terms have changed or could not be verified. Refresh the booking and contact support.',409);
 return safeCheckout(await rpc('travel_hotel_cancel_prepare',{actor:owner,target:id,expected_updated:row.updated_at,snapshot:await cancellationSnapshot(row)}));
}
export async function acceptHotelCancellation(owner:string,id:string,body:any) {
 requireValue(uuid(id)&&uuid(body.version)&&body.acceptTestCancellation===true,'Review and explicitly confirm test cancellation.');
 return safeCheckout(await rpc('travel_hotel_cancel_accept',{actor:owner,target:id,version:body.version}));
}
export async function runHotelCancellation(claim:any) {
 const row=claim.checkout;
 try {
  let data=await hotelSupplier('bookings/'+encodeURIComponent(row.booking.id));
  if(claim.operation==='cancel' && !['CANCELLED','CANCELLED_WITH_CHARGES'].includes(data?.status)) {
   const same=verifiedBooking(data,row) && data.bookingId===row.booking.id && data.prebookId===row.prebook_id;
   const policy=row.review.offer.rooms.map((r:any)=>r.cancellation);
   if(!same || await digest(JSON.stringify(policy))!==row.cancellation.termsHash || Date.parse(row.cancellation.expiresAt)<=Date.now()) {
    await finishCheckout(row,{cancellation:{...row.cancellation,state:'changed',message:'The booking or cancellation terms changed. Refresh and review again.'}});return;
   }
   // Claim is persisted before PUT. A timeout/crash leads only to GET lookup.
   await hotelSupplier('bookings/'+encodeURIComponent(row.booking.id),undefined,'PUT');
   data=await hotelSupplier('bookings/'+encodeURIComponent(row.booking.id));
  }
  if(['CANCELLED','CANCELLED_WITH_CHARGES'].includes(data?.status)) {
   const values=synchronizedBooking(data,row,row.booking.id);
   await finishCheckout(row,{...values,cancellation:{...row.cancellation,state:'cancelled',checkedAt:values.review.providerCheckedAt}});
  } else {
   await finishCheckout(row,{cancellation:{...row.cancellation,state:row.cancellation_attempts>=10?'needs_support':'pending'},next_check:new Date(Date.now()+60000).toISOString()});
  }
 } catch {
  await finishCheckout(row,{cancellation:{...row.cancellation,state:row.cancellation_attempts>=10?'needs_support':'pending'},next_check:new Date(Date.now()+60000).toISOString()});
 }
}
