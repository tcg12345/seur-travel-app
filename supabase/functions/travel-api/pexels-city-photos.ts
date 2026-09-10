import { cityLandmark, cityPhotoQuery } from './city-photos.ts';
import { digest, limit, platform } from './platform.ts';
import { upstream } from './providers.ts';
import { requireValue } from './validation.ts';

const normalized = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
const includes = (text: string, term: string) => (' ' + normalized(text) + ' ').includes(' ' + normalized(term) + ' ');
// Explicit landmarks avoid accepting a similarly named business as the city's identity.
const extraLandmarks = [
  ['Rome', 'Italy|IT', 'Colosseum', 'colosseum|coliseum'],
  ['Barcelona', 'Spain|ES', 'Sagrada Familia', 'sagrada familia'],
  ['Sydney', 'Australia|AU', 'Sydney Opera House', 'opera house'],
  ['San Francisco', 'United States|US|USA', 'Golden Gate Bridge', 'golden gate'],
  ['Rio de Janeiro', 'Brazil|BR', 'Christ the Redeemer', 'christ the redeemer|corcovado'],
  ['Cairo', 'Egypt|EG', 'Giza pyramids', 'pyramid|pyramids|sphinx'],
  ['Venice', 'Italy|IT', 'Grand Canal', 'grand canal|rialto'],
  ['Amsterdam', 'Netherlands|NL', 'Amsterdam canals', 'amsterdam'],
  ['Prague', 'Czechia|Czech Republic|CZ', 'Charles Bridge', 'charles bridge'],
  ['Budapest', 'Hungary|HU', 'Hungarian Parliament', 'parliament'],
  ['Florence', 'Italy|IT', 'Florence Duomo', 'florence|firenze'],
  ['Lisbon', 'Portugal|PT', 'Lisbon cityscape', 'lisbon|lisboa'],
  ['Edinburgh', 'United Kingdom|UK|GB|Scotland', 'Edinburgh Castle', 'edinburgh'],
  ['Santorini', 'Greece|GR', 'Santorini blue domes', 'santorini|oia'],
  ['Seoul', 'South Korea|Korea|KR', 'Seoul skyline', 'seoul'],
  ['Cape Town', 'South Africa|ZA', 'Table Mountain', 'table mountain|cape town'],
  ['Toronto', 'Canada|CA', 'CN Tower skyline', 'cn tower|toronto'],
  ['Vancouver', 'Canada|CA', 'Vancouver skyline', 'vancouver'],
  ['Chicago', 'United States|US|USA', 'Chicago skyline', 'chicago'],
];
export function pexelsDestination(value: string) {
  const city = cityPhotoQuery(value), parts = city.split(',').map(s => s.trim());
  const known = cityLandmark(city);
  if (known) return { query: `${known.city} ${known.countries[0]} ${known.subject} daytime`, terms: known.terms };
  const extra = extraLandmarks.find(([name, countries]) => normalized(name) === normalized(parts[0]) &&
    (parts.length === 1 || countries.split('|').some(c => normalized(c) === normalized(parts.at(-1)!))));
  return extra ? { query: `${extra[0]} ${extra[1].split('|')[0]} ${extra[2]} daytime`, terms: extra[3].split('|') }
    : { query: `${city} skyline landscape daytime`, terms: [parts[0]] };
}
export function pexelsURL(value: unknown, image = false): string | undefined {
  if (typeof value !== 'string') return;
  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && !url.username && !url.password && !url.port &&
      url.hostname === (image ? 'images.pexels.com' : 'www.pexels.com')) return url.href;
  } catch { /* Reject unexpected provider URLs. */ }
}
// Require affirmative daylight metadata, rather than merely the absence of “night”.
export function isDaytimePexelsPhoto(photo: any): boolean {
  const text = normalized(String(photo?.alt ?? '') + ' ' + String(photo?.url ?? ''));
  if (/\b(night|nighttime|nightscape|nocturnal|evening|dusk|twilight|sunset|sunrise|dawn|after dark|golden hour|blue hour|moon|moonlit|fireworks|neon|illuminated|light trails)\b/.test(text)) return false;
  return /\b(day|daytime|daylight|sunny|sunlit|sunlight|morning|afternoon|blue sky|blue skies|clear sky|clear skies|bright sky)\b/.test(text);
}
export function selectPexelsPhoto(photos: any[], city: string) {
  const { terms } = pexelsDestination(city);
  const ranked = photos.flatMap((p, index) => {
    const description = String(p?.alt ?? ''), text = normalized(description);
    const ratio = p?.width / p?.height;
    if (!isDaytimePexelsPhoto(p) || !Number.isFinite(ratio) || p.width < 1200 || p.height < 675 || ratio < 1.4 || ratio > 2.4 ||
      !terms.some(t => includes(text, t)) ||
      /\b(plaque|sign|signage|logo|souvenir|replica|miniature|lego|model|portrait|selfie|silhouette|interior|indoors|food|meal|close up)\b/.test(text)) return [];
    const imageURL = pexelsURL(p.src?.original, true), sourceURL = pexelsURL(p.url), authorURL = pexelsURL(p.photographer_url);
    if (!imageURL || !sourceURL || !authorURL || !String(p.photographer ?? '').trim()) return [];
    // Reward clear city vistas, preserve relevance order, and minimize 16:9 cropping.
    const scenic = /\b(skyline|panorama|panoramic|cityscape|aerial|river|waterfront)\b/.test(text) ? 15 : 0;
    const score = scenic - Math.abs(Math.log(ratio / (16 / 9))) * 40 - index * 0.5;
    const url = new URL(imageURL);
    url.search = new URLSearchParams({ auto: 'compress', cs: 'tinysrgb', fit: 'crop', w: '1200', h: '675' }).toString();
    return [{ score, photo: { provider: 'pexels', imageURL: url.href, sourceURL,
      authors: [{ name: p.photographer, url: authorURL }], title: description,
      attribution: `Photo by ${p.photographer} on Pexels`, license: 'Pexels License',
      licenseURL: 'https://www.pexels.com/license/' } }];
  }).sort((a, b) => b.score - a.score);
  return ranked[0]?.photo ?? null;
}
const pending = new Map<string, Promise<{ photo: ReturnType<typeof selectPexelsPhoto> }>>();
export async function pexelsCityPhoto(value: string, now = Date.now()) {
  const city = cityPhotoQuery(value), key = Deno.env.get('PEXELS_API_KEY');
  requireValue(key, 'Destination photos are not connected yet.', 503);
  const destination = pexelsDestination(city);
  const cacheKey = 'pexels-city-daytime-v1-' + await digest(normalized(destination.query));
  if (pending.has(cacheKey)) return await pending.get(cacheKey)!;
  const task = (async () => {
    const rows = await platform('/rest/v1/travel_provider_cache?select=value&key=eq.' + cacheKey + '&expires=gt.' + encodeURIComponent(new Date(now).toISOString()));
    if (rows?.[0]?.value && 'photo' in rows[0].value) return { photo: rows[0].value.photo };
    // Only cache misses consume provider quota. No pagination or fallback queries.
    await limit('pexels-photo-hour', 180, 3600);
    await limit('pexels-photo-day', 500, 86400);
    const params = new URLSearchParams({ query: destination.query, orientation: 'landscape', size: 'large', per_page: '30', locale: 'en-US' });
    const result = await upstream('https://api.pexels.com/v1/search?' + params, { Authorization: key! }, undefined, 8000);
    const candidates = Array.isArray(result.photos) ? result.photos.slice(0, 30) : [];
    const response = { photo: selectPexelsPhoto(candidates, city) };
    await platform('/rest/v1/travel_provider_cache', 'POST', { key: cacheKey, value: { ...response, candidates }, expires: new Date(now + 86400000).toISOString() }, { Prefer: 'resolution=merge-duplicates' });
    return response;
  })();
  pending.set(cacheKey, task);
  try { return await task; } finally { pending.delete(cacheKey); }
}
