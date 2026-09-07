import {
  decodePhoto,
  object,
  Problem,
  requireValue,
  uuid,
  validateDocument,
  validateFlight,
} from "./validation.ts";
import {
  account,
  apiURL,
  auth,
  digest,
  encodeBase64,
  limit,
  platform,
  projectURL,
  rpc,
  storage,
  token,
} from "./platform.ts";
import {
  autocomplete,
  configured,
  overview,
  placeDetails,
  recommend,
  searchPlaces,
} from "./providers.ts";
import {
  flightAirport,
  flightFeed,
  flightPosition,
  flightRoute,
  historyEnabled,
  nearbyFlightAirport,
} from "./flights.ts";
import { sharedLines, sharePDF } from "./shared.ts";
const headers = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization,content-type,apikey",
  "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
};
const json = (v: unknown, status = 200) =>
  new Response(JSON.stringify(v), {
    status,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8" },
  });
async function dispatch(
  actor: string,
  method: string,
  path: string,
  body: unknown = {},
) {
  return await rpc("travel_dispatch", { actor, method, path, body });
}
async function hydrate(remote: any, summary = false) {
  if (!remote?.document) return remote;
  if (summary) {
    for (const p of remote.document.places) p.photos = [];
    remote.isSummary = true;
    return remote;
  }
  // Sequential loading bounds memory/connections for photo-heavy journeys.
  for (const p of remote.document.places) {
    for (const photo of p.photos) {
      if (photo.storagePath) {
        const r = await storage(photo.storagePath);
        photo.jpeg = encodeBase64(new Uint8Array(await r.arrayBuffer()));
        delete photo.storagePath;
      }
    }
  }
  return remote;
}
const paths = (d: any) =>
  (d?.places ?? []).flatMap((p: any) => p.photos ?? []).map((p: any) =>
    p.storagePath
  ).filter(
    Boolean,
  );
async function removePhotos(keys: string[]) {
  if (keys.length) {
    await platform("/storage/v1/object/journey-photos", "DELETE", {
      prefixes: keys,
    });
  }
}
async function savePhotos(d: any, uid: string) {
  const result = structuredClone(d), version = crypto.randomUUID();
  for (const p of result.places) {
    for (const photo of p.photos) {
      const raw = decodePhoto(photo.jpeg),
        path =
          `${uid}/${d.id.toLowerCase()}/${version}/${crypto.randomUUID()}.jpg`;
      await storage(path, "POST", raw);
      delete photo.jpeg;
      photo.storagePath = path;
    }
  }
  return result;
}
export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  try {
    const url = new URL(req.url),
      path = url.pathname.replace(/^.*\/travel-api(?=\/|$)/, "") || "/",
      method = req.method,
      q = url.searchParams;
    // Gateway-supplied network identity is hashed; global auth limits also bound
    // registration even when a caller rotates addresses.
    const network = await digest(
      (req.headers.get("x-forwarded-for") || "unknown").split(",").pop()!
        .trim(),
    );
    await limit("request:" + network, 240);
    if (path.startsWith("/s/") && method === "GET") {
      const value = path.slice(3);
      requireValue(
        /^[a-f0-9]{80}$/.test(value),
        "This link is unavailable.",
        404,
      );
      await limit("share:" + network, 30);
      const links = await platform(
        "/rest/v1/travel_links?select=document_id&token_hash=eq." +
          await digest(value),
      );
      requireValue(
        links[0],
        "This link was revoked or is no longer available.",
        404,
      );
      const docs = await platform(
        "/rest/v1/travel_documents?select=*&id=eq." + links[0].document_id,
      );
      requireValue(docs[0], "This link is unavailable.", 404);
      const remote = await hydrate(
        await rpc("travel_remote", { d: docs[0], actor: null }),
      );
      if (q.get("format") === "json") return json(remote);
      if (q.get("format") === "txt") {
        return new Response(
          sharedLines(remote.document, remote.owner.name).map((l) =>
            l.photo
              ? "[Photo included in the PDF and JSON]"
              : l.text + (l.url ? " " + l.url : "")
          ).join("\n\n"),
          {
            headers: {
              ...headers,
              "Content-Type": "text/plain; charset=utf-8",
            },
          },
        );
      }
      // Supabase's shared domain does not render HTML. A native browser PDF keeps
      // read-only public sharing fully hosted on Supabase, without another web host.
      const pdf = await sharePDF(remote.document, remote.owner.name);
      return new Response(new Uint8Array(pdf), {
        headers: {
          ...headers,
          "Content-Type": "application/pdf",
          "Content-Disposition": 'inline; filename="Seur-journey.pdf"',
        },
      });
    }
    if (path === "/v1/status" && method === "GET") {
      return json({
        backend: "supabase",
        flightTracking: configured("FLIGHTAWARE_API_KEY"),
        flightHistory: historyEnabled(),
        googlePlaces: configured("GOOGLE_PLACES_API_KEY"),
        tripadvisor: configured("TRIPADVISOR_API_KEY"),
        ai: configured("OPENAI_API_KEY"),
        publicSharing: true,
      });
    }
    let body: any = {};
    if (["POST", "PUT", "DELETE"].includes(method)) {
      const length = Number(req.headers.get("Content-Length") || 0);
      requireValue(length <= 40000000, "Request exceeds 40 MB.", 413);
      const reader = req.body?.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      if (reader) {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 40000000) {
            await reader.cancel();
            throw new Problem("Request exceeds 40 MB.", 413);
          }
          chunks.push(value);
        }
      }
      if (size) {
        requireValue(
          req.headers.get("Content-Type")?.split(";")[0] === "application/json",
          "Send application/json.",
          415,
        );
        const data = new Uint8Array(size);
        let offset = 0;
        for (const c of chunks) {
          data.set(c, offset);
          offset += c.length;
        }
        body = JSON.parse(new TextDecoder().decode(data));
        requireValue(object(body), "JSON body must be an object.");
      }
    }
    if (
      ["/v1/auth/register", "/v1/auth/login"].includes(path) &&
      method === "POST"
    ) {
      await limit("auth:" + network, 20, 300);
      await limit(
        "auth-handle:" + await digest(String(body.handle ?? "").toLowerCase()),
        15,
        300,
      );
      if (path.endsWith("/register")) {
        await limit("registration-global", 50, 3600);
      }
      await rpc("travel_maintenance", {});
      return json(await auth(body, path.endsWith("/register")));
    }
    const uid = await account(req);
    if (path === "/v1/auth/logout" && method === "POST") {
      await platform(
        "/rest/v1/travel_sessions?token_hash=eq." +
          await digest(req.headers.get("Authorization")!.slice(7)),
        "DELETE",
      );
      return json({ ok: true });
    }
    if (path === "/v1/account" && method === "DELETE") {
      const docs = await platform(
        "/rest/v1/travel_documents?select=body&owner_id=eq." + uid,
      );
      await platform("/auth/v1/admin/users/" + uid, "DELETE");
      await removePhotos(docs.flatMap((d: any) => paths(d.body)));
      return json({ ok: true });
    }
    if (path === "/v1/my-flights" && method === "GET") {
      const rows = await platform(
        "/rest/v1/travel_flights?select=body&owner_id=eq." + uid +
          "&order=updated_at.desc",
      );
      return json(rows.map((r: any) => r.body));
    }
    const ownFlight = path.match(/^\/v1\/my-flights\/([a-fA-F0-9-]{36})$/);
    if (ownFlight) {
      requireValue(uuid(ownFlight[1]), "Invalid flight identifier.");
      const id = ownFlight[1].toLowerCase();
      if (method === "PUT") {
        validateFlight(body);
        requireValue(
          body.id.toLowerCase() === id,
          "Flight ID does not match path.",
        );
        await platform(
          "/rest/v1/travel_flights?on_conflict=owner_id,id",
          "POST",
          { owner_id: uid, id, body, updated_at: new Date().toISOString() },
          { Prefer: "resolution=merge-duplicates" },
        );
        return json(body);
      }
      if (method === "DELETE") {
        await platform(
          "/rest/v1/travel_flights?owner_id=eq." + uid + "&id=eq." + id,
          "DELETE",
        );
        return json({ ok: true });
      }
    }
    if (
      method === "GET" &&
      [
        "/v1/flights/status",
        "/v1/flights/history",
        "/v1/flights/position",
        "/v1/flights/route",
        "/v1/flights/airport",
        "/v1/flights/airport-nearby",
      ].includes(path)
    ) {
      await limit("flights:" + uid, 20);
      await limit("flights-global", 600, 3600);
      if (path.endsWith("/airport-nearby")) {
        return json(
          await nearbyFlightAirport(
            q.get("latitude") ?? "",
            q.get("longitude") ?? "",
          ),
        );
      }
      if (path.endsWith("/route")) {
        return json(
          await flightRoute(
            q.get("origin") || "",
            q.get("destination") || "",
            q.get("date") || "",
          ),
        );
      }
      if (path.endsWith("/airport")) {
        return json(await flightAirport(q.get("code") || ""));
      }
      return json(
        path.endsWith("/position")
          ? await flightPosition(q.get("id") || "")
          : await flightFeed(
            q.get("q") || "",
            q.get("date") || "",
            path.endsWith("/history"),
          ),
      );
    }
    if (path === "/v1/locations/autocomplete" && method === "GET") {
      await limit("autocomplete:" + uid, 60);
      return json(await autocomplete(q.get("q") || ""));
    }
    if (path === "/v1/places/search" && method === "GET") {
      await limit("places:" + uid, 30);
      return json(
        await searchPlaces(
          q.get("q") || "",
          q.get("category") || "attractions",
        ),
      );
    }
    if (/^\/v1\/places\/\d+$/.test(path) && method === "GET") {
      await limit("places:" + uid, 30);
      return json(await placeDetails(path.split("/").pop()!));
    }
    if (
      ["/v1/ai/activities", "/v1/ai/hotel"].includes(path) && method === "POST"
    ) {
      await limit("ai:" + uid, 10, 3600);
      return json(
        path.endsWith("hotel")
          ? await overview(body)
          : await recommend(body.city, body.interests, body.candidates),
      );
    }
    const match = path.match(
      /^\/v1\/documents\/([a-fA-F0-9-]{36})(?:\/(link|revoke))?$/,
    );
    if (match) {
      requireValue(uuid(match[1]), "Invalid journey identifier.");
      if (method === "PUT" && !match[2]) {
        validateDocument(body);
        requireValue(
          body.id.toLowerCase() === match[1].toLowerCase(),
          "Document ID does not match path.",
        );
        const old = await platform(
          "/rest/v1/travel_documents?select=owner_id,body&id=eq." + match[1],
        );
        requireValue(
          !old[0] || old[0].owner_id === uid,
          "Only the owner can edit this journey.",
          403,
        );
        if (old[0]) {
          requireValue(
            body.updatedAt >= old[0].body.updatedAt,
            "A newer cloud copy exists. Download it before updating.",
            409,
          );
        }
        const saved = await savePhotos(body, uid),
          remote = await dispatch(uid, method, path, saved);
        // Cleanup uses exact immutable paths; it cannot delete a newer version's photos.
        await removePhotos(paths(old[0]?.body)).catch(() => {});
        await rpc("travel_orphan_photos", {}).then(removePhotos).catch(
          () => {},
        );
        remote.document = body;
        return json(remote);
      }
      if (method === "DELETE" && !match[2]) {
        const old = await dispatch(uid, "GET", path);
        const r = await dispatch(uid, method, path);
        await removePhotos(paths(old.document)).catch(() => {});
        return json(r);
      }
      if (method === "POST" && match[2] === "link") {
        const value = token();
        await dispatch(uid, method, path, { token_hash: await digest(value) });
        return json({ url: apiURL + "/s/" + value });
      }
    }
    const value = await dispatch(uid, method, path, body);
    if (Array.isArray(value) && ["/v1/documents", "/v1/feed"].includes(path)) {
      return json(await Promise.all(value.map((v) => hydrate(v, true))));
    }
    return json(value?.document ? await hydrate(value) : value);
  } catch (e) {
    if (e instanceof Problem) return json({ error: e.message }, e.status);
    if (e instanceof SyntaxError) {
      return json({ error: "Malformed JSON request." }, 400);
    }
    return json(
      {
        error:
          "The cloud service could not complete this request. Please try again.",
      },
      500,
    );
  }
}
if (import.meta.main) Deno.serve(handler);
