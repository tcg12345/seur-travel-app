import { Problem, requireValue, uuid } from "./validation.ts";
import { digest, limit, platform, rpc } from "./platform.ts";
import { hotelID, hotelText } from "./hotels.ts";
import {
  cancellation,
  minor,
  normalizeOffer,
  openQuote,
} from "./hotel-rates.ts";

// This module deliberately cannot select live keys, wallets, account credit or
// card payments. ACC_CREDIT_CARD is LiteAPI's documented no-charge sandbox test.
export function hotelCheckoutConfigured() {
  return /^sand_[a-zA-Z0-9_-]+$/.test(
    Deno.env.get("LITEAPI_SANDBOX_KEY") ?? "",
  );
}
export function checkoutGuest(body: any) {
  const name = (v: unknown) =>
    typeof v === "string" && v.trim().length >= 1 && v.trim().length <= 80 &&
    !/[\u0000-\u001f<>]/.test(v);
  requireValue(
    body && name(body.firstName) && name(body.lastName),
    "Enter the lead guest's first and last name.",
  );
  requireValue(
    typeof body.email === "string" && body.email.length <= 254 &&
      /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(body.email.trim()),
    "Enter a valid contact email.",
  );
  requireValue(
    typeof body.phone === "string" &&
      /^\+[1-9][0-9]{6,14}$/.test(body.phone.trim()),
    "Enter a phone number with country code, such as +12125550123.",
  );
  return {
    firstName: body.firstName.trim(),
    lastName: body.lastName.trim(),
    email: body.email.trim(),
    phone: body.phone.trim(),
  };
}
async function payloadKey() {
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  requireValue(secret, "Checkout is unavailable.", 503);
  return crypto.subtle.importKey(
    "raw",
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode("seur-hotel-checkout-v1:" + secret),
    ),
    "AES-GCM",
    false,
    ["encrypt", "decrypt"],
  );
}
export async function sealCheckout(value: unknown, id: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: new TextEncoder().encode(id) },
      await payloadKey(),
      new TextEncoder().encode(JSON.stringify(value)),
    ),
  );
  return btoa(String.fromCharCode(...iv)) + "." +
    btoa(String.fromCharCode(...cipher));
}
export async function openCheckout(value: string, id: string) {
  const [a, b] = value.split("."),
    decode = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  return JSON.parse(
    new TextDecoder().decode(
      await crypto.subtle.decrypt(
        {
          name: "AES-GCM",
          iv: decode(a),
          additionalData: new TextEncoder().encode(id),
        },
        await payloadKey(),
        decode(b),
      ),
    ),
  );
}
async function supplier(path: string, body?: unknown, explicitMethod?: "PUT") {
  requireValue(
    hotelCheckoutConfigured(),
    "Sandbox checkout is unavailable.",
    503,
  );
  await limit("hotel-checkouts-global", 2, 1);
  const response = await fetch("https://book.liteapi.travel/v3.0/" + path, {
    method: explicitMethod ?? (body === undefined ? "GET" : "POST"),
    headers: {
      "X-API-Key": Deno.env.get("LITEAPI_SANDBOX_KEY")!,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(35000),
    redirect: "error",
  });
  if (explicitMethod === "PUT" && [204,304].includes(response.status)) return null;
  const result = await response.json();
  // Booking lookup uses a nested numeric sandbox flag; the list endpoint omits
  // it. Lists can discover IDs only, never establish confirmation themselves.
  const listLookup = body === undefined && path.startsWith("bookings?");
  const sandbox = result?.sandbox === true ||
    (body === undefined &&
      (result?.data?.sandbox === 1 || result?.data?.sandbox === true));
  requireValue(
    response.ok && result?.sandbox !== false && result?.data?.sandbox !== false && result?.data?.sandbox !== 0 && (sandbox || listLookup) &&
      !result.error && !result.errors,
    "The test reservation is awaiting verification.",
    502,
  );
  return result.data;
}
const table = "/rest/v1/travel_hotel_checkouts";
async function owned(owner: string, id: string) {
  requireValue(uuid(id), "Invalid checkout.");
  const rows = await platform(
    table + "?id=eq." + id + "&owner=eq." + owner + "&limit=1",
  );
  requireValue(rows?.length === 1, "Checkout unavailable.", 404);
  return rows[0];
}
export function safeCheckout(row: any) {
  const expired = row.state === "review" &&
    Date.parse(row.expires_at) <= Date.now();
  return {
    id: row.id,
    state: expired ? "expired" : row.state,
    environment: "sandbox",
    paymentState: "test_no_charge",
    quoteVersion: row.quote_version,
    review: row.review,
    expiresAt: row.expires_at,
    booking: row.booking ?? null,
    createdAt: row.created_at,
    cancellation: row.cancellation ? {state:row.cancellation.state,version:row.cancellation.version,expiresAt:row.cancellation.expiresAt,checkedAt:row.cancellation.checkedAt,message:row.cancellation.message ?? null} : null,
  };
}
async function finish(row: any, values: any) {
  // Fencing prevents a slow response from overwriting a later recovery result.
  const rows = await platform(
    table + "?id=eq." + row.id + "&lease_token=eq." + row.lease_token,
    "PATCH",
    {
      ...values,
      updated_at: new Date().toISOString(),
      lease_until: null,
      lease_token: null,
    },
    { Prefer: "return=representation" },
  );
  return rows?.[0];
}
function termsFingerprint(offer: any) {
  return JSON.stringify({
    base: offer.base,
    total: offer.total,
    fees: offer.fees,
    rooms: offer.rooms.map((r: any) => ({
      number: r.number,
      name: r.name,
      adults: r.adults,
      children: r.children,
      board: r.board,
      paymentTypes: r.paymentTypes,
      cancellation: r.cancellation,
      remarks: r.remarks,
      perks: r.perks,
    })),
  });
}
export function prebookReview(data: any, original: any, now = Date.now()) {
  const c = original.criteria;
  requireValue(
    data && typeof data.prebookId === "string" &&
      /^[a-zA-Z0-9_-]{1,200}$/.test(data.prebookId) &&
      data.hotelId === hotelID(original.offer.hotelId) &&
      data.checkin === c.checkin && data.checkout === c.checkout &&
      data.currency === c.currency && data.isPackageRate !== true,
    "This room option could not be verified. Choose another option.",
    502,
  );
  requireValue(
    Array.isArray(data.roomTypes) && data.roomTypes.length === 1 &&
      (!data.roomTypes[0].rateType ||
        data.roomTypes[0].rateType === "standard"),
    "This room option could not be verified.",
    502,
  );
  // Live sandbox prebook returns SSP as a scalar in the response currency,
  // while the reference also permits the amount/currency object.
  const floor = typeof data.suggestedSellingPrice === "number" ||
      typeof data.suggestedSellingPrice === "string"
    ? { amount: data.suggestedSellingPrice, currency: data.currency }
    : data.suggestedSellingPrice;
  const offer = normalizeOffer(
    {
      ...data.roomTypes[0],
      offerId: data.offerId || "prebook",
      rateType: "standard",
      offerRetailRate: { amount: data.price, currency: data.currency },
      suggestedSellingPrice: floor,
      paymentTypes: data.paymentTypes,
    },
    original.offer.hotelId,
    c,
    now,
  );
  requireValue(
    offer && offer.total && offer.rooms.length === 1 &&
      offer.rooms.every((r) => r.paymentTypes.includes("NUITEE_PAY")),
    "This room option is not supported for test booking.",
    422,
  );
  requireValue(
    data.termsAndConditions == null ||
      (typeof data.termsAndConditions === "string" &&
        data.termsAndConditions.length <= 30000),
    "Booking terms could not be verified.",
    502,
  );
  return {
    offer: { id: original.offer.id, ...offer },
    criteria: c,
    environment: "sandbox",
    pricingPolicy: original.pricingPolicy,
    checkoutEnabled: true,
    terms: hotelText(data.termsAndConditions, 30000),
    changed: data.priceDifferencePercent !== 0 ||
      data.cancellationChanged !== false || data.boardChanged !== false ||
      termsFingerprint(original.offer) !== termsFingerprint(offer),
  };
}
export async function createHotelCheckout(owner: string, body: any) {
  requireValue(
    hotelCheckoutConfigured(),
    "Sandbox checkout is unavailable.",
    503,
  );
  requireValue(uuid(body.id), "Invalid checkout request.");
  body = { ...body, id: body.id.toLowerCase() };
  const guest = checkoutGuest(body.guest);
  requireValue(
    typeof body.quote === "string" && body.quote.length < 100000,
    "Invalid room option.",
  );
  const fingerprint = await digest(JSON.stringify([body.quote, guest]));
  // A retry must still recover after the original search quote has expired.
  const existing = await platform(
    table + "?id=eq." + body.id + "&owner=eq." + owner + "&limit=1",
  );
  if (existing.length) {
    requireValue(
      existing[0].request_hash === fingerprint,
      "This checkout has different guest details.",
      409,
    );
    return safeCheckout(existing[0]);
  }
  const quote = await openQuote(body.quote, owner);
  requireValue(
    quote.pricingPolicy === "account-default-sandbox-v1",
    "Refresh room options for the current pricing policy.",
    409,
  );
  requireValue(
    quote.criteria.occupancies.length === 1 && quote.offer.total &&
      quote.offer.rooms.every((r: any) =>
        r.paymentTypes.includes("NUITEE_PAY")
      ),
    "Test booking currently supports one room with a complete price and online payment.",
    422,
  );
  const snapshot = {
    offer: quote.offer,
    criteria: quote.criteria,
    environment: "sandbox",
    pricingPolicy: quote.pricingPolicy,
    checkoutEnabled: true,
    terms: "",
    changed: false,
    hotelName: hotelText(body.hotelName, 300),
  };
  const result = await rpc("travel_hotel_checkout_create", {
    actor: owner,
    target: body.id,
    quote: quote.offer.id,
    fingerprint,
    snapshot,
    payload: await sealCheckout({
      guest,
      supplierOfferId: quote.supplierOfferId,
    }, body.id),
  });
  let row = result.checkout;
  if (result.created) {
    try {
      const data = await supplier("rates/prebook", {
        offerId: quote.supplierOfferId,
        usePaymentSdk: false,
      });
      const review = prebookReview(data, quote);
      row = await finish(row, {
        state: "review",
        review: { ...review, hotelName: snapshot.hotelName },
        prebook_id: data.prebookId,
        expires_at: review.offer.expiresAt,
      }) ?? row;
    } catch {
      // No payment or booking has occurred. Never retry an ambiguous prebook.
      row = await finish(row, {
        state: "prebook_unknown",
        private_payload: null,
      }) ?? row;
    }
  }
  return safeCheckout(row);
}
export async function getHotelCheckout(owner: string, id: string) {
  return safeCheckout(await owned(owner, id));
}
// A user-requested status refresh only reads the provider. It never calls prebook,
// book or cancel, and only terminal records can be changed outside the worker lease.
export function synchronizedBooking(data: any, row: any, providerID: string) {
  const c = row.review.criteria;
  requireValue(data?.bookingId === providerID && data.clientReference === row.client_reference &&
    data.prebookId === row.prebook_id && data.hotel?.hotelId === hotelID(row.review.offer.hotelId) &&
    data.checkin === c.checkin && data.checkout === c.checkout,
    "The provider record could not be matched to this stay. Contact support.", 502);
  requireValue(["CONFIRMED", "CANCELLED", "CANCELLED_WITH_CHARGES"].includes(data.status),
    "The provider has not returned a final booking status. Try again later.", 502);
  const review = {...row.review, providerStatus: data.status, providerCheckedAt: new Date().toISOString()};
  if (["CANCELLED", "CANCELLED_WITH_CHARGES"].includes(data.status)) {
    return {state: "cancelled", review: {...review, issue: "The provider reports this test booking as cancelled. This status does not establish a refund."}, private_payload: null};
  }
  const booking = verifiedBooking(data, row);
  if (!booking) return {state: "needs_support", review: {...review, supportReference: providerID,
    issue: "The provider returned room or cancellation details that differ from your accepted quote."}, private_payload: null};
  return {state: "confirmed", booking: {...booking, confirmedAt: row.booking?.confirmedAt ?? booking.confirmedAt},
    review: {...review, issue: null}, private_payload: null};
}
export async function syncHotelCheckout(owner: string, id: string) {
  const row = await owned(owner, id);
  if (["queued","submitting","pending"].includes(row.cancellation?.state)) return safeCheckout(row);
  if (row.state === "cancelled") return safeCheckout(row); // A late result must never resurrect a cancelled stay.
  if (!["confirmed", "needs_support"].includes(row.state)) return safeCheckout(row);
  requireValue(row.accepted_at, "No booking was submitted for this checkout.", 409);
  const providerID = row.booking?.id ?? row.review.supportReference;
  requireValue(typeof providerID === "string" && /^[a-zA-Z0-9_-]{1,200}$/.test(providerID),
    "The provider has not supplied a booking reference. Contact support.", 409);
  await limit("hotel-sync:" + row.id, 1, 15);
  const data = await supplier("bookings/" + encodeURIComponent(providerID));
  const values: any = synchronizedBooking(data, row, providerID);
  if (values.state === "cancelled" && row.cancellation) values.cancellation = {...row.cancellation,state:"cancelled",checkedAt:values.review.providerCheckedAt};
  const params = new URLSearchParams({id: "eq."+row.id, owner: "eq."+owner,
    updated_at: "eq."+row.updated_at, state: "eq."+row.state});
  const rows = await platform(table + "?" + params, "PATCH", {...values, updated_at: new Date().toISOString()}, {Prefer: "return=representation"});
  // Account removal, worker updates, and overlapping refreshes invalidate this write.
  return safeCheckout(rows?.[0] ?? await owned(owner, id));
}
// Preserve Postgres microseconds: truncating a cursor to milliseconds can skip rows.
function historyPosition(value: any) {
  return value && uuid(value.id) && typeof value.createdAt === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value.createdAt) &&
    Number.isFinite(Date.parse(value.createdAt));
}
export async function listHotelCheckouts(owner: string, cursor: string | null = null) {
  requireValue(uuid(owner), "Invalid account.", 401);
  const params = new URLSearchParams({
    owner: "eq." + owner,
    select: "id,state,quote_version,review,expires_at,booking,created_at,cancellation",
    order: "created_at.desc,id.desc",
    limit: "31",
  });
  if (cursor !== null) {
    let position;
    try {
      requireValue(typeof cursor === "string" && cursor.length > 0 && cursor.length <= 2048, "Invalid cursor.");
      position = await openCheckout(cursor, "hotel-history-v1:" + owner);
      requireValue(position?.version === 1 && historyPosition(position), "Invalid cursor.");
    } catch { throw new Problem("Booking history expired or changed. Refresh to continue.", 400); }
    params.set("or", `(created_at.lt.${position.createdAt},and(created_at.eq.${position.createdAt},id.lt.${position.id}))`);
  }
  const rows = await platform(table + "?" + params.toString());
  requireValue(Array.isArray(rows), "Booking history is unavailable.", 502);
  const page = rows.slice(0, 30), last = page.at(-1);
  let nextCursor: string | null = null;
  if (rows.length > 30 && last) {
    const position = {version: 1, createdAt: last.created_at, id: last.id};
    requireValue(historyPosition(position), "Booking history is unavailable.", 502);
    nextCursor = await sealCheckout(position, "hotel-history-v1:" + owner);
  }
  return { checkouts: page.map(safeCheckout), nextCursor };
}
export async function confirmHotelCheckout(
  owner: string,
  id: string,
  body: any,
) {
  requireValue(
    uuid(id) && uuid(body.quoteVersion) && body.acceptTestBooking === true,
    "Review and explicitly confirm the test booking.",
  );
  return safeCheckout(
    await rpc("travel_hotel_checkout_accept", {
      actor: owner,
      target: id,
      version: body.quoteVersion,
    }),
  );
}
export function verifiedBooking(data: any, row: any) {
  const c = row.review.criteria, o = row.review.offer;
  if (
    !data || data.clientReference !== row.client_reference ||
    data.status !== "CONFIRMED" || typeof data.bookingId !== "string" ||
    !data.bookingId.length || data.bookingId.length > 200 ||
    data.hotel?.hotelId !== hotelID(o.hotelId) || data.checkin !== c.checkin ||
    data.checkout !== c.checkout || data.currency !== c.currency ||
    minor(data.price, c.currency) !== minor(o.base.amount, c.currency) ||
    data.prebookId && data.prebookId !== row.prebook_id
  ) return null;
  // Confirm only the accepted occupancy, never a partial room response.
  if (
    !Array.isArray(data.bookedRooms) || data.bookedRooms.length !== 1 ||
    data.bookedRooms[0].adults !== c.occupancies[0].adults ||
    data.bookedRooms[0].children !== c.occupancies[0].children.length
  ) return null;
  const room = data.bookedRooms[0], expected = o.rooms[0];
  const mappedMatch = expected.mappedRoomId &&
    String(room.mappedRoomId ?? "") === expected.mappedRoomId;
  if (
    !mappedMatch &&
    hotelText(room.roomType?.name, 300).toLowerCase() !==
      expected.name.toLowerCase()
  ) return null;
  const fees = room.rate?.retailRate?.taxesAndFees;
  if (!Array.isArray(fees) || fees.length !== o.fees.length) return null;
  const feeKey = (f: any) =>
    JSON.stringify([
      hotelText(f.description, 200) || "Hotel charge",
      f.included,
      f.currency,
      String(minor(f.amount, f.currency)),
    ]);
  const expectedFees = o.fees.map((f: any) =>
    feeKey({ ...f.charge, description: f.description, included: f.included })
  ).sort();
  if (
    JSON.stringify(fees.map(feeKey).sort()) !== JSON.stringify(expectedFees)
  ) return null;
  if (
    JSON.stringify([...(room.childrenAges ?? [])].sort()) !==
      JSON.stringify([...expected.children].sort()) ||
    hotelText(room.boardName ?? room.board, 100) !== expected.board
  ) return null;
  if (!room.rate?.cancellationPolicies) return null;
  const policy = cancellation(room.rate.cancellationPolicies, Date.now());
  if (
    JSON.stringify([policy.nonrefundable, policy.penalties, policy.remarks]) !==
      JSON.stringify([
        expected.cancellation.nonrefundable,
        expected.cancellation.penalties,
        expected.cancellation.remarks,
      ])
  ) return null;
  return {
    id: data.bookingId,
    confirmationCode: hotelText(data.hotelConfirmationCode, 200) || null,
    hotelName: hotelText(data.hotel?.name, 300),
    confirmedAt: new Date().toISOString(),
  };
}
export async function hotelCheckoutWorker(ticket: unknown) {
  requireValue(
    uuid(ticket) && await rpc("travel_hotel_claim_job", { ticket }),
    "Invalid worker ticket.",
    401,
  );
  const cancellationClaim = await rpc("travel_hotel_cancel_claim", {});
  if (cancellationClaim) {
    const {runHotelCancellation} = await import("./hotel-cancellations.ts");
    await runHotelCancellation(cancellationClaim); return {processed:1};
  }
  const claim = await rpc("travel_hotel_checkout_claim", { target: null });
  if (!claim) return { processed: 0 };
  const row = claim.checkout;
  try {
    let data;
    if (claim.operation === "book") {
      const payload = await openCheckout(row.private_payload, row.id),
        guest = payload.guest;
      data = await supplier("rates/book", {
        prebookId: row.prebook_id,
        clientReference: row.client_reference,
        holder: guest,
        guests: [{ ...guest, occupancyNumber: 1 }],
        payment: { method: "ACC_CREDIT_CARD" },
      });
    } else {
      const result = await supplier(
        "bookings?clientReference=" + encodeURIComponent(row.client_reference),
      );
      const matches = Array.isArray(result)
        ? result.filter((x) => x?.clientReference === row.client_reference)
        : [];
      const candidate = matches.length === 1 ? matches[0] : null;
      data = candidate && typeof candidate.bookingId === "string" &&
          /^[a-zA-Z0-9_-]{1,200}$/.test(candidate.bookingId)
        ? await supplier(
          "bookings/" + encodeURIComponent(candidate.bookingId),
        )
        : null;
    }
    const booking = verifiedBooking(data, row);
    const mismatch = data?.clientReference === row.client_reference &&
      data?.status === "CONFIRMED" && !booking;
    await finish(
      row,
      booking
        ? { state: "confirmed", booking, private_payload: null }
        : mismatch
        ? {
          state: "needs_support",
          private_payload: null,
          review: {
            ...row.review,
            issue:
              "The provider returned room or cancellation details that differ from your accepted quote.",
            supportReference: hotelText(data.bookingId, 200),
          },
        }
        : {
          state: row.attempts >= 10 ? "needs_support" : "pending_confirmation",
          private_payload: null,
          next_check: new Date(Date.now() + 60000).toISOString(),
        },
    );
  } catch {
    // Includes duplicate reference (4005), upstream/network uncertainty and DB
    // disagreement. Lookup the same reference; never resubmit /rates/book.
    await finish(row, {
      state: row.attempts >= 10 ? "needs_support" : "pending_confirmation",
      private_payload: null,
      next_check: new Date(Date.now() + 60000).toISOString(),
    });
  }
  return { processed: 1 };
}

export {supplier as hotelSupplier, owned as ownedCheckout, finish as finishCheckout};
