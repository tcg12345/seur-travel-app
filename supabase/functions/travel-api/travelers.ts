import { Problem, requireValue, uuid } from "./validation.ts";
import { platform, rpc } from "./platform.ts";
import {
  checkoutGuest,
  openCheckout,
  sealCheckout,
} from "./hotel-checkouts.ts";
import { countries } from "./hotel-rates.ts";
export function travelerDetails(body: any) {
  const guest = checkoutGuest(body);
  requireValue(
    countries.has(body.nationality),
    "Choose the traveler’s nationality.",
  );
  return { ...guest, nationality: body.nationality };
}
export async function travelerResponse(owner: string, rows: any[]) {
  requireValue(
    Array.isArray(rows) && rows.length <= 20,
    "Traveler profiles are unavailable.",
    502,
  );
  const profiles = await Promise.all(rows.map(async (row) => {
    requireValue(
      row.owner === owner && uuid(row.id),
      "Traveler profiles are unavailable.",
      502,
    );
    let details;
    try {
      details = travelerDetails(
        await openCheckout(
          row.private_payload,
          "traveler-v1:" + owner + ":" + row.id,
        ),
      );
    } catch {
      throw new Problem(
        "A saved traveler could not be opened. Contact support.",
        502,
      );
    }
    return {
      id: row.id,
      version: row.version,
      isDefault: row.is_default,
      ...details,
    };
  }));
  return { profiles };
}
export async function listTravelers(owner: string) {
  return travelerResponse(
    owner,
    await platform(
      "/rest/v1/travel_traveler_profiles?owner=eq." + owner +
        "&order=is_default.desc,created_at,id&limit=21",
    ),
  );
}
export async function saveTraveler(owner: string, id: string, body: any) {
  requireValue(
    uuid(id) && Number.isInteger(body.expectedVersion) &&
      body.expectedVersion >= 0 && typeof body.isDefault === "boolean",
    "Invalid traveler profile.",
  );
  const details = travelerDetails(body);
  const payload = await sealCheckout(
    details,
    "traveler-v1:" + owner + ":" + id.toLowerCase(),
  );
  return travelerResponse(
    owner,
    await rpc("travel_traveler_save", {
      actor: owner,
      target: id.toLowerCase(),
      expected_version: body.expectedVersion,
      payload,
      make_default: body.isDefault,
    }),
  );
}
export async function deleteTraveler(owner: string, id: string, body: any) {
  requireValue(
    uuid(id) && Number.isInteger(body.expectedVersion) &&
      body.expectedVersion > 0,
    "Invalid traveler profile.",
  );
  return travelerResponse(
    owner,
    await rpc("travel_traveler_delete", {
      actor: owner,
      target: id.toLowerCase(),
      expected_version: body.expectedVersion,
    }),
  );
}
