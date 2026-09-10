import { cityLandmark, cityPhotoQuery } from './city-photos.ts';
import { upstream } from './providers.ts';
import { requireValue } from './validation.ts';

export function googlePhotoURL(value: unknown, image = false): string | undefined {
  if (typeof value !== 'string') return;
  try {
    const u = new URL(value);
    const allowed = image ? /^lh[3-6]\.googleusercontent\.com$/.test(u.hostname)
      : ['maps.google.com', 'www.google.com', 'google.com', 'maps.app.goo.gl'].includes(u.hostname);
    if (u.protocol === 'https:' && !u.username && !u.password && !u.port && allowed) return u.href;
  } catch { /* Reject unexpected provider URLs. */ }
}

// On-demand only: one landmark search and at most one photo-media lookup.
// Neither photo names nor Google content are written to the provider cache/storage.
export async function googleCityPhoto(value: string) {
  const city = cityPhotoQuery(value);
  const key = Deno.env.get('GOOGLE_PLACES_API_KEY');
  requireValue(key, 'Destination photos are unavailable.', 503);
  const landmark = cityLandmark(city);
  const result = await upstream('https://places.googleapis.com/v1/places:searchText', {
    'X-Goog-Api-Key': key!,
    'X-Goog-FieldMask': 'places.id,places.displayName,places.googleMapsUri,places.photos',
  }, { textQuery: landmark ? `${landmark.subject}, ${landmark.city}, ${landmark.countries[0]}` : `${city} landmark`,
    languageCode: 'en', pageSize: 1 }, 8000);
  const place = result.places?.[0];
  if (!place) return { photo: null };
  const title = String(place.displayName?.text ?? '');
  // A similarly named business is not an acceptable cover for a catalog landmark.
  if (landmark && !landmark.terms.some(term => title.toLowerCase().includes(term))) return { photo: null };
  // Preserve Google's relevance order. Landscape-only filtering can select a view
  // FROM a landmark instead of the landmark itself. Cards crop the leading image.
  const photo = place.photos?.find((p: any) => p.widthPx >= 800 && p.heightPx > 0 &&
    typeof p.name === 'string' && /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/.test(p.name) &&
    p.name.split('/')[1] === place.id);
  if (!photo) return { photo: null };
  const media = await upstream(`https://places.googleapis.com/v1/${photo.name}/media?maxWidthPx=1000&skipHttpRedirect=true`,
    { 'X-Goog-Api-Key': key! }, undefined, 8000);
  const imageURL = googlePhotoURL(media.photoUri, true);
  if (!imageURL) return { photo: null };
  return { photo: { provider: 'google', imageURL,
    sourceURL: googlePhotoURL(photo.googleMapsUri) ?? googlePhotoURL(place.googleMapsUri),
    authors: (photo.authorAttributions ?? []).map((a: any) => ({ name: String(a.displayName ?? ''),
      url: googlePhotoURL(a.uri), avatarURL: googlePhotoURL(a.photoUri, true) })),
    title, attribution: 'Google Maps', license: 'Google Maps terms', licenseURL: 'https://www.google.com/help/terms_maps/',
  } };
}
