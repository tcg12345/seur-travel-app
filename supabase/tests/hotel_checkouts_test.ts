import assert from "node:assert/strict";
Deno.env.set("SUPABASE_URL", "https://checkout.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "checkout-secret");
const {
  checkoutGuest,
  hotelCheckoutConfigured,
  sealCheckout,
  openCheckout,
  prebookReview,
  safeCheckout,
  verifiedBooking,
  createHotelCheckout,
  hotelCheckoutWorker,
  confirmHotelCheckout,
  getHotelCheckout,
  listHotelCheckouts,
} = await import("../functions/travel-api/hotel-checkouts.ts");
const { normalizeOffer, searchHotelRates } = await import(
  "../functions/travel-api/hotel-rates.ts"
);
const owner = "11111111-1111-4111-8111-111111111111",
  id = "22222222-2222-4222-8222-222222222222",
  version = "33333333-3333-4333-8333-333333333333";
const criteria = {
  checkin: "2026-10-10",
  checkout: "2026-10-13",
  currency: "USD",
  guestNationality: "US",
  occupancies: [{ adults: 2, children: [] }],
};
const guest = {
  firstName: "Test",
  lastName: "Traveler",
  email: "test@example.test",
  phone: "+12125550123",
};
function raw(): any {
  return {
    offerId: "opaque",
    rateType: "standard",
    rates: [{
      occupancyNumber: 1,
      name: "King",
      adultCount: 2,
      childCount: 0,
      childrenAges: [],
      boardType: "RO",
      boardName: "Room only",
      retailRate: {
        total: [{ amount: 100, currency: "USD" }],
        taxesAndFees: [{
          included: false,
          amount: 10,
          currency: "USD",
          description: "City tax",
        }],
      },
      cancellationPolicies: {
        refundableTag: "NRFN",
        cancelPolicyInfos: [],
        hotelRemarks: [],
      },
      paymentTypes: ["NUITEE_PAY"],
    }],
  };
}
function original(): any {
  return {
    criteria,
    offer: {
      id: crypto.randomUUID(),
      ...normalizeOffer(raw(), "liteapi:lp123", criteria),
    },
    supplierOfferId: "opaque",
  };
}
function prebook(): any {
  return {
    prebookId: "prebook-123",
    hotelId: "lp123",
    checkin: criteria.checkin,
    checkout: criteria.checkout,
    currency: "USD",
    price: 100,
    roomTypes: [{ rates: raw().rates }],
    priceDifferencePercent: 0,
    cancellationChanged: false,
    boardChanged: false,
    isPackageRate: false,
  };
}
function row(): any {
  return {
    id,
    owner,
    quote_id: crypto.randomUUID(),
    state: "review",
    quote_version: version,
    review: { ...original(), hotelName: "Example Hotel" },
    expires_at: new Date(Date.now() + 300000).toISOString(),
    created_at: new Date().toISOString(),
    lease_token: crypto.randomUUID(),
    client_reference: "seur-test-" + id,
    prebook_id: "prebook-123",
    attempts: 1,
  };
}
function booking(r: any): any {
  return {
    bookingId: "test-booking",
    clientReference: r.client_reference,
    prebookId: r.prebook_id,
    status: "CONFIRMED",
    hotel: { hotelId: "lp123", name: "Example Hotel" },
    checkin: criteria.checkin,
    checkout: criteria.checkout,
    currency: "USD",
    price: 100,
    bookedRooms: [{
      roomType: { name: "King" },
      adults: 2,
      children: 0,
      childrenAges: [],
      boardName: "Room only",
      rate: {
        retailRate: raw().rates[0].retailRate,
        cancellationPolicies: raw().rates[0].cancellationPolicies,
      },
    }],
  };
}
Deno.test("Checkout validates names/contact and excludes card data", () => {
  assert.deepEqual(
    checkoutGuest({ ...guest, cardNumber: "must-not-pass" }),
    guest,
  );
  for (
    const change of [{ firstName: "" }, { lastName: "<script>" }, {
      email: "missing",
    }, { phone: "2125550123" }]
  ) assert.throws(() => checkoutGuest({ ...guest, ...change }));
  Deno.env.set("LITEAPI_SANDBOX_KEY", "production-key");
  assert.equal(hotelCheckoutConfigured(), false);
  Deno.env.set("LITEAPI_SANDBOX_KEY", "sand_test");
  assert.equal(hotelCheckoutConfigured(), true);
});
Deno.test("Stored guest data is encrypted and authenticated to its checkout", async () => {
  const sealed = await sealCheckout(guest, id);
  assert(!sealed.includes(guest.email));
  assert.deepEqual(await openCheckout(sealed, id), guest);
  await assert.rejects(() => openCheckout(sealed, owner));
  await assert.rejects(() => openCheckout(sealed.slice(0, -5) + "xxxxx", id));
});
Deno.test("Prebook repricing preserves final fees and flags price and cancellation changes", () => {
  const p = prebook(), o = original();
  let review = prebookReview(p, o);
  assert.equal(review.changed, false);
  assert.equal(review.offer.total!.amount, "110.00");
  p.price = 105;
  p.roomTypes[0].rates[0].retailRate.total[0].amount = 105;
  review = prebookReview(p, o);
  assert.equal(review.changed, true);
  assert.equal(review.offer.total!.amount, "115.00");
  p.cancellationChanged = true;
  assert.equal(prebookReview(p, o).changed, true);
});
Deno.test("Prebook cannot substitute dates, property, occupancy, currency or package rates", () => {
  for (
    const change of [
      { hotelId: "lp999" },
      { checkin: "2026-10-11" },
      { currency: "EUR" },
      { isPackageRate: true },
      { price: 1000 },
    ]
  ) assert.throws(() => prebookReview({ ...prebook(), ...change }, original()));
  const p = prebook();
  p.roomTypes[0].rates[0].adultCount = 1;
  assert.throws(() => prebookReview(p, original()));
  const q = prebook();
  delete q.roomTypes[0].rates[0].retailRate.taxesAndFees;
  assert.throws(() => prebookReview(q, original()));
});
Deno.test("Confirmation requires provider evidence matching accepted price, stay, occupancy and terms", () => {
  const r = row(), b = booking(r);
  assert.equal(verifiedBooking(b, r)?.id, "test-booking");
  for (
    const change of [
      { status: "PENDING" },
      { price: 101 },
      { clientReference: "other" },
      { prebookId: "other" },
      { hotel: { hotelId: "lp999" } },
      { bookedRooms: [] },
    ]
  ) assert.equal(verifiedBooking({ ...b, ...change }, r), null);
  b.bookedRooms[0].boardName = "Breakfast";
  assert.equal(verifiedBooking(b, r), null);
});
Deno.test("Public checkout never exposes provider offers, guest data, lease or prebook IDs", () => {
  const r = row();
  r.private_payload = "encrypted";
  r.state = "review";
  r.expires_at = new Date(0).toISOString();
  const safe = safeCheckout(r);
  assert.equal(safe.state, "expired");
  for (
    const k of [
      "private_payload",
      "prebook_id",
      "lease_token",
      "request_hash",
      "client_reference",
    ]
  ) assert(!(k in safe));
});
async function mock(run: (db: any) => Promise<void>) {
  const saved = globalThis.fetch;
  Deno.env.set("LITEAPI_SANDBOX_KEY", "sand_test");
  const db: any = {
    row: null,
    prebooks: 0,
    books: 0,
    lookups: 0,
    mode: "success",
    claim: "book",
    accepts: 0,
  };
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input)),
      body = init?.body ? JSON.parse(String(init.body)) : {};
    if (url.pathname.endsWith("/travel_hotel_cancel_claim")) return Response.json(null);
    if (url.hostname === "api.liteapi.travel") {
      return Response.json({
        sandbox: true,
        data: [{ hotelId: "lp123", roomTypes: [raw()] }],
      });
    }
    if (url.hostname === "book.liteapi.travel") {
      assert.equal(new Headers(init?.headers).get("X-API-Key"), "sand_test");
      if (url.pathname.endsWith("/prebook")) {
        db.prebooks++;
        assert.equal(body.usePaymentSdk, false);
        if (db.mode === "prebook-timeout") {
          throw new Error("provider timeout secret");
        }
        return Response.json({ sandbox: true, data: prebook() });
      }
      if (url.pathname.endsWith("/book")) {
        db.books++;
        assert.equal(body.clientReference, db.row.client_reference);
        assert.deepEqual(body.payment, { method: "ACC_CREDIT_CARD" });
        assert.equal(body.guests.length, 1);
        if (db.mode === "timeout") throw new Error("ambiguous");
        if (db.mode === "duplicate") {
          return Response.json({ error: { code: 4005 } }, { status: 400 });
        }
        return Response.json({
          sandbox: db.mode !== "production",
          data: booking(db.row),
        });
      }
      if (url.pathname.includes("/bookings/")) {
        const data = booking(db.row);
        data.sandbox = 1;
        if (db.mode === "mismatch") data.bookedRooms[0].adults = 1;
        return Response.json({ data });
      }
      db.lookups++;
      assert.equal(
        url.searchParams.get("clientReference"),
        db.row.client_reference,
      );
      return Response.json({
        data: [{
          bookingId: "test-booking",
          clientReference: db.row.client_reference,
        }],
      });
    }
    assert.equal(url.origin, "https://checkout.test");
    if (url.pathname.endsWith("travel_limit")) return Response.json(true);
    if (url.pathname.endsWith("travel_hotel_checkout_create")) {
      const created = !db.row;
      if (created) {
        db.row = {
          ...row(),
          id: body.target,
          owner: body.actor,
          quote_id: body.quote,
          request_hash: body.fingerprint,
          review: body.snapshot,
          private_payload: body.payload,
          state: "prebooking",
        };
      }
      return Response.json({ created, checkout: db.row });
    }
    if (url.pathname.endsWith("travel_hotel_checkout_accept")) {
      db.accepts++;
      db.row.state = "queued";
      return Response.json(db.row);
    }
    if (url.pathname.endsWith("travel_hotel_claim_job")) {
      return Response.json(body.ticket === version);
    }
    if (url.pathname.endsWith("travel_hotel_checkout_claim")) {
      return Response.json(
        db.row ? { checkout: db.row, operation: db.claim } : null,
      );
    }
    if (init?.method === "PATCH") {
      Object.assign(db.row, body);
      return Response.json([db.row]);
    }
    return Response.json(
      db.row && url.searchParams.get("owner") === "eq." + db.row.owner
        ? [db.row]
        : [],
    );
  };
  try {
    await run(db);
  } finally {
    globalThis.fetch = saved;
  }
}
async function create(db: any) {
  const rates = await searchHotelRates({
    hotelIds: ["liteapi:lp123"],
    criteria,
    detail: true,
  }, owner);
  const body = {
    id: id.toUpperCase(),
    quote: rates.hotels[0].offers[0].quote,
    guest,
    hotelName: "Example Hotel",
  };
  const result = await createHotelCheckout(owner, body);
  return { result, body };
}
Deno.test("Create is durable/idempotent and a retried request does not prebook twice", async () =>
  await mock(async (db) => {
    const { result, body } = await create(db);
    assert.equal(result.state, "review");
    assert.equal(db.prebooks, 1);
    await createHotelCheckout(owner, body);
    assert.equal(db.prebooks, 1);
    assert.deepEqual(
      (await openCheckout(db.row.private_payload, id)).guest,
      guest,
    );
    await assert.rejects(
      () =>
        createHotelCheckout(owner, {
          ...body,
          guest: { ...guest, firstName: "Changed" },
        }),
      (e: any) => e.status === 409,
    );
    await assert.rejects(
      () => getHotelCheckout(version, id),
      (e: any) => e.status === 404,
    );
  }));
Deno.test("Prebook uncertainty is saved without a payment or a second prebook", async () =>
  await mock(async (db) => {
    db.mode = "prebook-timeout";
    const { result, body } = await create(db);
    assert.equal(result.state, "prebook_unknown");
    assert.equal(db.books, 0);
    await createHotelCheckout(owner, body);
    assert.equal(db.prebooks, 1);
  }));
Deno.test("Only explicit final intent invokes acceptance; client payment flags have no authority", async () =>
  await mock(async (db) => {
    await create(db);
    await assert.rejects(() =>
      confirmHotelCheckout(owner, id, {
        quoteVersion: version,
        paymentSucceeded: true,
      })
    );
    assert.equal(db.accepts, 0);
    await confirmHotelCheckout(owner, id, {
      quoteVersion: version,
      acceptTestBooking: true,
    });
    assert.equal(db.accepts, 1);
    assert.equal(db.books, 0);
  }));
Deno.test("Worker confirms only a no-charge sandbox booking and rejects invalid worker tickets", async () =>
  await mock(async (db) => {
    await create(db);
    await assert.rejects(
      () => hotelCheckoutWorker(owner),
      (e: any) => e.status === 401,
    );
    assert.equal(db.books, 0);
    await hotelCheckoutWorker(version);
    assert.equal(db.books, 1);
    assert.equal(db.row.state, "confirmed");
    assert.equal(db.row.private_payload, null);
  }));
for (const mode of ["timeout", "duplicate", "production"]) {
  Deno.test(`Worker ${mode} outcome recovers by original reference without another booking`, async () =>
    await mock(async (db) => {
      await create(db);
      db.mode = mode;
      await hotelCheckoutWorker(version);
      assert.equal(db.row.state, "pending_confirmation");
      assert.equal(db.books, 1);
      db.claim = "lookup";
      db.mode = "success";
      await hotelCheckoutWorker(version);
      assert.equal(db.lookups, 1);
      assert.equal(db.books, 1);
      assert.equal(db.row.state, "confirmed");
    }));
}

Deno.test("Live prebook scalar selling-price floor retains response currency and public restriction", () => {
  const p = prebook();
  p.suggestedSellingPrice = 115.25;
  const review = prebookReview(p, original());
  assert.deepEqual(review.offer.publicPriceFloor, {
    amount: "115.25",
    currency: "USD",
  });
  assert.equal(review.offer.publicPriceEligible, false);
  p.suggestedSellingPrice = "bad-price";
  assert.throws(() => prebookReview(p, original()));
});

Deno.test("A confirmed supplier booking with different rooms goes to support, not success", async () =>
  await mock(async (db) => {
    await create(db);
    db.claim = "lookup";
    db.mode = "mismatch";
    await hotelCheckoutWorker(version);
    assert.equal(db.row.state, "needs_support");
    assert.equal(db.row.booking, undefined);
    assert.equal(db.row.review.supportReference, "test-booking");
    assert.equal(db.books, 0);
  }));
Deno.test("Explicit package-only remarks override an inconsistent standard rate flag", () => {
  const p = prebook();
  p.roomTypes[0].rates[0].remarks =
    "Package Rate - must only be sold as part of a package.";
  assert.throws(() => prebookReview(p, original()));
});

Deno.test("Provider room identity and hotel fees must also match the accepted quote", () => {
  const r = row(), a = booking(r);
  a.bookedRooms[0].roomType.name = "Different room";
  assert.equal(verifiedBooking(a, r), null);
  const b = booking(r);
  b.bookedRooms[0].rate.retailRate.taxesAndFees[0].amount = 11;
  assert.equal(verifiedBooking(b, r), null);
});

Deno.test("history cursors preserve timestamp ties, skip new inserts, and bind ownership", async () => {
  const saved = globalThis.fetch;
  let calls = 0;
  const records = Array.from({length:65}, (_, index) => ({...row(), id: `40000000-0000-4000-8000-${String(1000-index).padStart(12,"0")}`, created_at: "2026-09-11T10:00:00.123456+00:00", private_payload: "never-return"}));
  globalThis.fetch = async (input) => {
    calls++;
    const url = new URL(String(input));
    assert.equal(url.hostname, "checkout.test");
    assert.equal(url.searchParams.get("owner"), "eq."+owner);
    assert.equal(url.searchParams.get("order"), "created_at.desc,id.desc");
    assert.equal(url.searchParams.get("limit"), "31");
    assert(!url.searchParams.get("select")!.includes("private_payload"));
    let filtered = records.slice();
    const clause = url.searchParams.get("or");
    if (clause) {
      const match = clause.match(/^\(created_at\.lt\.(.+),and\(created_at\.eq\.(.+),id\.lt\.([a-f0-9-]+)\)\)$/)!;
      assert(match); assert.equal(match[1],match[2]); assert.equal(match[1],"2026-09-11T10:00:00.123456+00:00");
      filtered = filtered.filter(r => r.created_at < match[1] || r.created_at === match[1] && r.id < match[3]);
    }
    return Response.json(filtered.slice(0,31));
  };
  try {
    const first = await listHotelCheckouts(owner); assert.equal(first.checkouts.length,30); assert(first.nextCursor);
    assert(!JSON.stringify(first).includes("never-return"));
    const position = await openCheckout(first.nextCursor, "hotel-history-v1:"+owner);
    assert.equal(position.createdAt,"2026-09-11T10:00:00.123456+00:00");
    const before = calls;
    await assert.rejects(()=>listHotelCheckouts(id, first.nextCursor));
    await assert.rejects(()=>listHotelCheckouts(owner, first.nextCursor!.slice(0,-4)+"AAAA"));
    await assert.rejects(()=>listHotelCheckouts(owner, ""));
    await assert.rejects(()=>listHotelCheckouts(owner, "a".repeat(2049)));
    const invalid = await sealCheckout({version:1,id,createdAt:"2026-09-11),owner.neq.null"},"hotel-history-v1:"+owner);
    await assert.rejects(()=>listHotelCheckouts(owner, invalid));
    assert.equal(calls,before);
    records.unshift({...row(),id:"ffffffff-ffff-4fff-8fff-ffffffffffff",created_at:"2026-09-12T00:00:00+00:00",private_payload:"never-return"});
    const second = await listHotelCheckouts(owner, first.nextCursor); assert.equal(second.checkouts.length,30); assert(second.nextCursor);
    const third = await listHotelCheckouts(owner, second.nextCursor); assert.equal(third.checkouts.length,5); assert.equal(third.nextCursor,null);
    const ids = [...first.checkouts,...second.checkouts,...third.checkouts].map(r=>r.id);
    assert.equal(new Set(ids).size,65); assert(!ids.includes(records[0].id));
  } finally { globalThis.fetch = saved; }
});
Deno.test("history empty and exact-sized final pages do not invent another cursor", async () => {
  const saved = globalThis.fetch;
  try {
    for (const count of [0,30]) {
      globalThis.fetch = async ()=>Response.json(Array.from({length:count},()=>row()));
      const page = await listHotelCheckouts(owner); assert.equal(page.nextCursor,null); assert.equal(page.checkouts.length,count);
    }
  } finally { globalThis.fetch = saved; }
});

Deno.test('Provider refresh verifies identity and terms, records cancellation and retains confirmation time',async()=>{
 const {synchronizedBooking}=await import('../functions/travel-api/hotel-checkouts.ts');
 const r=row();r.state='confirmed';r.booking={id:'test-booking',confirmedAt:'2026-09-10T00:00:00Z'};
 const data=booking(r);
 const result=synchronizedBooking(data,r,'test-booking');assert.equal(result.state,'confirmed');assert.equal(result.booking?.confirmedAt,r.booking.confirmedAt);assert.equal(result.review.issue,null);
 const cancelled=synchronizedBooking({...data,status:'CANCELLED'},r,'test-booking');assert.equal(cancelled.state,'cancelled');assert.equal(cancelled.review.providerStatus,'CANCELLED');assert(cancelled.review.providerCheckedAt);assert(!('paymentState' in cancelled));
 const changed=structuredClone(data);changed.bookedRooms[0].adults=1;assert.equal(synchronizedBooking(changed,r,'test-booking').state,'needs_support');
 for(const delta of [{bookingId:'other'},{clientReference:'other'},{prebookId:'other'},{hotel:{hotelId:'lpother'}},{checkin:'2000-01-01'},{status:'PENDING'}]) assert.throws(()=>synchronizedBooking({...data,...delta},r,'test-booking'));
});
Deno.test('Provider refresh only reads the stored booking, fences writes and rejects cross-owner or production data',async()=>{
 const {syncHotelCheckout}=await import('../functions/travel-api/hotel-checkouts.ts');
 const originalFetch=globalThis.fetch;const r=row();r.state='needs_support';r.accepted_at=new Date().toISOString();r.updated_at=r.created_at;r.review.supportReference='test-booking';
 let mode='success',reads=0,writes=0;
 Deno.env.set('LITEAPI_SANDBOX_KEY','sand_test');
 globalThis.fetch=async(input,init)=>{
  const url=new URL(String(input));
  if(url.hostname==='book.liteapi.travel') {reads++;assert.equal(init?.method,'GET');assert(url.pathname.endsWith('/bookings/test-booking'));if(mode==='timeout')throw Error('upstream');return Response.json({data:{...booking(r),sandbox:mode==='production'?0:1}});}
  if(url.pathname.endsWith('/travel_limit')) return Response.json(true);
  assert(url.pathname.endsWith('/travel_hotel_checkouts'));
  assert.equal(url.searchParams.get('owner'),'eq.'+owner);
  if(init?.method==='PATCH'){writes++;assert.equal(url.searchParams.get('updated_at'),'eq.'+r.updated_at);assert.equal(url.searchParams.get('state'),'eq.needs_support');return Response.json(mode==='race'?[]:[{...r,...JSON.parse(String(init.body))}]);}
  return Response.json(mode==='unauthorized'?[]:[r]);
 };
 try {
  assert.equal((await syncHotelCheckout(owner,id)).state,'confirmed');assert.equal(reads,1);assert.equal(writes,1);
  mode='race';assert.equal((await syncHotelCheckout(owner,id)).state,'needs_support');
  for(const bad of ['production','timeout','unauthorized']){mode=bad;const before=writes;await assert.rejects(()=>syncHotelCheckout(owner,id));assert.equal(writes,before);}
  mode='success';r.state='cancelled';const before=reads;assert.equal((await syncHotelCheckout(owner,id)).state,'cancelled');assert.equal(reads,before);
 } finally {globalThis.fetch=originalFetch;}
});
