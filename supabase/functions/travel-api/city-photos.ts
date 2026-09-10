import { upstream } from './providers.ts';
import { requireValue } from './validation.ts';

export function cityPhotoQuery(value: string) {
  const city = value.trim();
  requireValue(city.length >= 2 && city.length <= 200 && !/[\x00-\x1f\x7f]/.test(city), 'Choose a city with 2–200 characters.');
  return city;
}
export function commonsURL(value: unknown, host: string): string | undefined {
  if (typeof value !== 'string') return;
  try {
    const u = new URL(value.startsWith('//') ? 'https:' + value : value);
    if (u.protocol === 'https:' && !u.username && !u.password && !u.port && u.hostname === host) return u.href;
  } catch { /* Untrusted provider URLs never reach the client. */ }
}
function plain(value: unknown): string {
  if (typeof value !== 'string') return '';
  const entities: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  return value.replace(/<[^>]*>/g, ' ').replace(/&(#x[\da-f]+|#\d+|\w+);/gi, (all, code) => {
    if (!code.startsWith('#')) return entities[code] ?? all;
    const n = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
    return n > 0 && n <= 0x10ffff ? String.fromCodePoint(n) : '';
  }).replace(/\s+/g, ' ').trim();
}

// Editorial choices keep city covers recognizable, rather than accepting a hotel or random street.
const cityLandmarks = [
  { city: 'Paris', countries: ['France', 'FR'], subject: 'Eiffel Tower', terms: ['eiffel'], file: 'File:Eiffel tower from trocadero.jpg' },
  { city: 'London', countries: ['United Kingdom', 'UK', 'GB', 'England'], subject: 'Big Ben', terms: ['big ben', 'elizabeth tower'], file: "File:London - Westminster Bridge Road - Jubilee Walkway - Panorama view on Palace of Westminster, Big Ben, Westminster Bridge & London Eye 04.jpg" },
  { city: 'Bangkok', countries: ['Thailand', 'TH'], subject: 'Wat Arun', terms: ['wat arun'], file: "File:Wat Arun across the river Sep 2023 morning.jpg" },
  { city: 'Tokyo', countries: ['Japan', 'JP'], subject: 'Tokyo Tower', terms: ['tokyo tower', 'tokyo-tower'], file: "File:Tokyo Tower, Minato City.jpg" },
  { city: 'New York', aliases: ['New York City', 'NYC'], countries: ['United States', 'United States of America', 'USA', 'US'], subject: 'Statue of Liberty', terms: ['statue of liberty', 'liberty statue'], file: "File:Statue of Liberty, NY.jpg" },
  { city: 'Singapore', countries: ['Singapore', 'SG'], subject: 'Marina Bay Sands', terms: ['marina bay sands'], file: "File:Skylines of the Central Business District, Singapore at sunset.jpg" },
  { city: 'Hong Kong', countries: ['Hong Kong', 'China', 'HK'], subject: 'Victoria Harbour', terms: ['victoria harbour', 'victoria harbor'], file: "File:Hong Kong Island Skyline 2009.jpg" },
  { city: 'Dubai', countries: ['United Arab Emirates', 'UAE', 'AE'], subject: 'Burj Khalifa', terms: ['burj khalifa'], file: "File:Dubai Skyline from Offshore La Mer.jpg" },
  { city: 'Shanghai', countries: ['China', 'CN'], subject: 'Oriental Pearl Tower', terms: ['oriental pearl'], file: "File:Shanghai Skyline from a tour boat (Pudong).jpg" },
  { city: 'Istanbul', countries: ['Türkiye', 'Turkey', 'TR'], subject: 'Hagia Sophia', terms: ['hagia sophia', 'ayasofya'], file: "File:Hagia Sophia Mars 2013.jpg" },
  { city: 'Macau', aliases: ['Macao'], countries: ['Macau', 'Macao', 'China', 'MO'], subject: "Ruins of Saint Paul's", terms: ['paul', 'paulo'], file: "File:Igreja de S\u00e3o Paulo I (7062651485).jpg" },
  { city: 'Kuala Lumpur', countries: ['Malaysia', 'MY'], subject: 'Petronas Towers', terms: ['petronas'], file: "File:Kuala Lumpur Malaysia Petronas-Twin-Towers-01.jpg" },
  { city: 'Athens', countries: ['Greece', 'GR'], subject: 'Acropolis', terms: ['acropolis', 'parthenon'], file: "File:20101024 Acropolis panoramic view from Areopagus hill Athens Greece.jpg" },
];
const normalized = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
export function cityLandmark(city: string) {
  const parts = city.split(',').map(normalized);
  const regions: Record<string, string[]> = { 'New York': ['ny','new york'], Paris: ['ile-de-france'], London: ['greater london'], Athens: ['attica'], 'Kuala Lumpur': ['federal territory of kuala lumpur'] };
  return cityLandmarks.find(l => [l.city, ...(l.aliases ?? [])].some(name => normalized(name) === parts[0]) &&
    (parts.length === 1 || l.countries.some(country => normalized(country) === parts.at(-1)) || (parts.length === 2 && regions[l.city]?.includes(parts[1]))));
}

// Exactly one external API lookup. Image bytes are downloaded once by the app,
// then kept with their credits. No Google API, pagination, fallback search or retry.
export async function cityPhoto(value: string) {
  const city = cityPhotoQuery(value);
  // Quote user words so destination names cannot inject Commons search operators.
  const words = city.replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
  if (!words.length) return { photo: null };
  const landmark = cityLandmark(city);
  const query = new URLSearchParams({ action: 'query', format: 'json', formatversion: '2',
    generator: 'search', gsrsearch: (landmark ? '"' + landmark.city + '" "' + landmark.subject + '"' : words.map(w => '"' + w + '"').join(' ') + ' landmark') + ' filetype:bitmap',
    gsrnamespace: '6', gsrlimit: '5', prop: 'imageinfo', iiprop: 'url|size|mime|extmetadata',
    iiurlwidth: '1000', iiextmetadatalanguage: 'en',
    iiextmetadatafilter: 'Artist|Credit|Attribution|Copyrighted|LicenseShortName|LicenseUrl|UsageTerms',
  });
  if (landmark?.file) {
    for (const key of ['generator', 'gsrsearch', 'gsrnamespace', 'gsrlimit']) query.delete(key);
    query.set('titles', landmark.file);
  }
  const result = await upstream('https://commons.wikimedia.org/w/api.php?' + query,
    { 'User-Agent': 'SeurTravel/1.0 (destination trip covers)', 'Api-User-Agent': 'SeurTravel/1.0' }, undefined, 8000);
  const pages = (result.query?.pages ?? []).sort((a: any, b: any) => (a.index ?? 0) - (b.index ?? 0));
  for (const page of pages) {
    const title = normalized(page.title ?? '').replace(/_/g, ' ');
    if (landmark?.file ? title !== normalized(landmark.file).replace(/_/g, ' ') : landmark && !landmark.terms.some(term => title.includes(term))) continue;
    if (/\b(lego|miniature|replica|souvenir|postcard|interior|detail|model|plaque|sign|logo|map|diagram)\b/.test(title)) continue;
    const info = page.imageinfo?.[0], meta = info?.extmetadata ?? {};
    const license = plain(meta.LicenseShortName?.value);
    const licenseURL = commonsURL(meta.LicenseUrl?.value, 'creativecommons.org');
    // Only licenses that explicitly permit saved copies; unknown terms fail closed.
    const isCC = licenseURL && /^https:\/\/creativecommons.org\/(licenses\/(by|by-sa)\/[\d.]+\/?|publicdomain\/(zero|mark)\/1\.0\/?)$/.test(licenseURL);
    if (!isCC || !license || !['image/jpeg', 'image/png'].includes(info?.mime) || info.width < info.height) continue;
    const imageURL = commonsURL(info.thumburl, 'thumb.wikimedia.org') ?? commonsURL(info.thumburl, 'upload.wikimedia.org');
    const sourceURL = commonsURL(info.descriptionurl, 'commons.wikimedia.org');
    const author = plain(meta.Artist?.value);
    if (!imageURL || !sourceURL || !author) continue;
    return { photo: { imageURL, sourceURL, license, licenseURL,
      title: plain(page.title).replace(/^File:/, ''),
      attribution: plain(meta.Attribution?.value) || plain(meta.Credit?.value),
      authors: [{ name: author }],
    } };
  }
  return { photo: null };
}
