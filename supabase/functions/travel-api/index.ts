import { accountAuth, authOptions } from "./account-auth.ts";
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
import { recapSnapshot } from "./recaps.ts";
import { sanitizedTemplate, templateSummary } from "./templates.ts";
import { concierge } from "./concierge.ts";
import { notificationWorker, pushConfigured, watches } from "./notifications.ts";
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
      await limit((q.has("asset") ? "recap-media:" : "share:") + network, q.has("asset") ? 180 : 30);
      const recapHash = await digest(value);
      const recaps = await platform("/rest/v1/travel_recaps?select=body&token_hash=eq." + recapHash);
      // A recap capability never falls through to the full-document/PDF endpoint,
      // regardless of format/view parameters. Unselected photos have no media row.
      if (recaps.length) {
        if (q.has("asset")) {
          const id = q.get("asset")!;
          requireValue(id === "map" || uuid(id), "Image unavailable.", 404);
          const rows = await platform("/rest/v1/travel_recap_media?select=jpeg&token_hash=eq." + recapHash + "&image_id=eq." + id.toLowerCase());
          requireValue(rows[0], "Image unavailable.", 404);
          return new Response(new Uint8Array(decodePhoto(rows[0].jpeg)), { headers: {...headers,"Content-Type":"image/jpeg"} });
        }
        if (q.get("format") === "json") return json(recaps[0].body);
        const host = Deno.env.get("RECAP_WEB_URL");
        requireValue(host && /^https:\/\//.test(host), "Recap web sharing is being configured. Please try again shortly.", 503);
        return new Response(null, {status:302,headers:{...headers,Location:host + "#" + value}});
      }
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
    const templateMatch = path.match(/^\/v1\/templates(?:\/([a-fA-F0-9-]{36}))?$/);
    if (templateMatch && method === "GET") {
      await limit("template-read:" + network, 90);
      const city = q.get("city") ?? "", tags = (q.get("tags") ?? "").split(",").map(t => t.trim().toLowerCase()).filter(Boolean);
      requireValue(city.length <= 100 && tags.length <= 8 && tags.every(t => /^[a-z0-9 -]{1,30}$/.test(t)), "Invalid template filters.");
      const values = await rpc("travel_templates", { city, tags, target: templateMatch[1] ?? null });
      if (templateMatch[1]) { requireValue(values.length > 0, "This template is no longer public.", 404); return json(values[0]); }
      return json(values.map(templateSummary));
    }
    if (path === "/v1/status" && method === "GET") {
      return json({
        backend: "supabase",
        flightTracking: configured("FLIGHTAWARE_API_KEY"),
        flightHistory: historyEnabled(),
        googlePlaces: configured("GOOGLE_PLACES_API_KEY"),
        tripadvisor: configured("TRIPADVISOR_API_KEY"),
        ai: configured("OPENAI_API_KEY"),
        flightNotifications: pushConfigured(),
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
    if (path === "/v1/auth/options" && method === "GET") return json(await authOptions());
    const modernAuth = path.match(/^\/v1\/auth\/(email\/(signup|login|verify|resend)|apple|google\/(start|exchange))$/);
    if (modernAuth && method === "POST") {
      await limit("auth:" + network, 20, 300);
      if (body.email) await limit("auth-email:" + await digest(String(body.email).trim().toLowerCase()), 10, 300);
      if (["email/signup", "email/resend"].includes(modernAuth[1])) {
        await limit("auth-mail:" + await digest(String(body.email).trim().toLowerCase()), 1, 60);
      }
      return json(await accountAuth(modernAuth[1], body));
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
    if (path === "/internal/flight-notifications" && method === "POST") return json(await notificationWorker(body.ticket));
    if (path === "/v1/auth/logout" && method === "POST") {
      const bearer = req.headers.get("Authorization")?.match(/^Bearer ([a-f0-9]{80})$/)?.[1];
      requireValue(bearer, "Invalid session.", 401);
      // Possession permits revoking this session even after expiration. Linked
      // flight watches are removed by the foreign key in the same transaction.
      await platform("/rest/v1/travel_sessions?token_hash=eq." + await digest(bearer), "DELETE");
      return json({ ok: true });
    }
    const uid = await account(req);
    if (path === "/v1/me" && method === "PUT") {
      requireValue(typeof body.name === "string" && body.name.trim().length > 0 && body.name.length <= 100, "Enter your name.");
      requireValue(typeof body.handle === "string" && /^[a-z0-9_]{3,32}$/.test(body.handle), "Choose a username with 3–32 letters, numbers or underscores.");
      await platform("/rest/v1/travel_profiles?id=eq." + uid, "PATCH", {name:body.name.trim(),handle:body.handle});
      return json(await rpc("travel_user", {x:uid}));
    }
    if (path === "/v1/recaps" && method === "POST") {
      await limit("recap-publish:" + uid, 10);
      requireValue(Deno.env.get("RECAP_WEB_URL"), "Recap web sharing is being configured. Please try again shortly.", 503);
      const {snapshot,images,documentID,visibility} = recapSnapshot(body), value = token();
      await rpc("travel_save_recap", {actor:uid,hash:await digest(value),doc:documentID,audience:visibility,snapshot,images});
      return json({url:apiURL + "/s/" + value + "?view=recap"});
    }
    const recapDelete = path.match(/^\/v1\/recaps\/([a-fA-F0-9-]{36})$/);
    if (recapDelete && method === "DELETE") {
      await platform("/rest/v1/travel_recaps?owner_id=eq." + uid + "&document_id=eq." + recapDelete[1], "DELETE");
      return json({ok:true});
    }

    if (path === "/v1/flight-notifications" && ["GET", "POST", "PUT", "DELETE"].includes(method)) {
      await limit("push-settings:" + uid, 30);
      return json(await watches(uid, method, method === "GET" ? { installationID: q.get("installationID") } : body, await digest(req.headers.get("Authorization")!.slice(7))));
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
    if (path === "/v1/ai/concierge" && method === "POST") {
      await limit("concierge:" + uid, 40, 3600);
      await limit("concierge-global", 1000, 3600);
      return json(await concierge(body));
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
    const templateUse = path.match(/^\/v1\/templates\/([a-fA-F0-9-]{36})\/uses$/);
    if (templateUse && method === "POST") {
      requireValue(uuid(body.cloneID), "Invalid new trip identifier.");
      await limit("template-clone:" + uid, 30, 3600);
      return json(await rpc("travel_template_used", { actor: uid, template: templateUse[1], clone: body.cloneID }));
    }
    const match = path.match(
      /^\/v1\/documents\/([a-fA-F0-9-]{36})(?:\/(link|revoke))?$/,
    );
    if (match) {
      requireValue(uuid(match[1]), "Invalid journey identifier.");
      if (method === "PUT" && !match[2]) {
        validateDocument(body);
        if (body.isTemplate === true) { const owner = await rpc("travel_user", { x: uid }); body = sanitizedTemplate(body, owner.handle); }
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
        await platform("/rest/v1/travel_recaps?owner_id=eq." + uid + "&document_id=eq." + match[1], "DELETE");
        await removePhotos(paths(old.document)).catch(() => {});
        return json(r);
      }
      if (method === "POST" && match[2] === "link") {
        const value = token();
        await dispatch(uid, method, path, { token_hash: await digest(value) });
        return json({ url: apiURL + "/s/" + value });
      }
    }
    const messagePath = path.match(/^\/v1\/conversations\/([a-fA-F0-9-]{36})\/messages$/);
    if (method === "POST" && messagePath) {
      return json(await rpc("travel_send_message", { actor: uid, cid: messagePath[1], body }));
    }
    const value = path === "/v1/feed" && method === "GET" ? await rpc("travel_social_feed", { actor: uid }) : await dispatch(uid, method, path, body);
    if (method === "POST" && match?.[2] === "revoke") { await platform("/rest/v1/travel_recaps?owner_id=eq." + uid + "&document_id=eq." + match[1], "DELETE"); }
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
