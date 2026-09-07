import { PDFDocument, PDFName, PDFString, rgb, StandardFonts } from 'npm:pdf-lib@1.17.1';
import { eventKinds, safeURL } from './validation.ts';
export function sharedLines(d: any, owner: string) {
  const lines: { text: string; kind?: string; url?: string; photo?: string }[] = [];
  const add = (text: string, kind = 'body', url?: string) => {
    if (text) lines.push({ text, kind, url });
  };
  const cost = (v: any) => v ? `${v.currency} ${v.amount.toFixed(2)}` : '';
  const place = (p: any) => {
    add(p.address);
    if (p.latitude != null) {
      add(
        'Open in Apple Maps',
        'link',
        'https://maps.apple.com/?' +
          new URLSearchParams({ q: p.name, ll: `${p.latitude},${p.longitude}` }),
      );
    }
    if (safeURL(p.website)) add('Website', 'link', p.website);
    if (safeURL(p.sourceURL)) add(p.source || 'Source', 'link', p.sourceURL);
  };
  add(d.title, 'title');
  add(`Shared by ${owner}`, 'muted');
  add(d.stops.map((s: any) => s.name).join(' → ') || d.destination, 'heading');
  add(d.description);
  for (const s of d.stops) {
    add(`${s.name} · ${s.nights} nights`, 'heading');
    for (let day = 0; day <= s.nights; day++) {
      const events = d.events.filter((e: any) => e.stopID === s.id && e.day === day).sort((
        a: any,
        b: any,
      ) => (a.allDay ? -1 : a.minute) - (b.allDay ? -1 : b.minute));
      const date = d.dateMode === 'dates'
        ? new Date(Date.parse(s.arrival) + day * 86400000).toISOString().slice(0, 10)
        : `Day ${day + 1}`;
      add(date, 'subheading');
      if (!events.length) add('A little room for discovery.', 'muted');
      for (const e of events) {
        const kind = e.kind || 'place';
        let time = e.allDay
          ? 'All day'
          : `${Math.floor(e.minute / 60).toString().padStart(2, '0')}:${
            (e.minute % 60).toString().padStart(2, '0')
          }`;
        if (!e.allDay && e.durationMinutes) time += ` · ${e.durationMinutes} min`;
        add(`${time} · ${kind === 'place' ? e.place.category : eventKinds[kind]}`, 'muted');
        add(kind === 'place' ? e.place.name : e.title, 'subheading');
        if (kind !== 'place') add(e.place.name);
        add(e.attendees);
        add(e.description);
        place(e.place);
        add(cost(e.cost));
        for (const u of e.links) add('Details', 'link', u);
      }
    }
  }
  if (d.hotels.length) add('Your stays', 'heading');
  for (const h of d.hotels) {
    add(h.place.name, 'subheading');
    add(`${h.checkIn} – ${h.checkOut} · ${h.guests} guests · ${h.rooms} rooms`);
    add(h.roomType);
    add(h.overview);
    place(h.place);
    add(cost(h.cost));
  }
  if (d.flights.length) add('Your flights', 'heading');
  for (const f of d.flights) {
    add(`${f.departureAirport} → ${f.arrivalAirport}`, 'subheading');
    add(`${f.airline} ${f.flightNumber || ''}`);
    add(
      `${f.departureDay} ${f.departureTime} ${
        f.departureZone || ''
      } → ${f.arrivalDay} ${f.arrivalTime} ${f.arrivalZone || ''}`,
    );
    add('Airport-local times', 'muted');
    add(cost(f.cost));
    if (safeURL(f.bookingLink)) add('Flight details', 'link', f.bookingLink);
  }
  const totals: Record<string, number> = {};
  for (const v of [...d.events, ...d.hotels, ...d.flights]) {
    if (v.cost) totals[v.cost.currency] = (totals[v.cost.currency] || 0) + v.cost.amount;
  }
  if (Object.keys(totals).length) {
    add('Planned cost', 'heading');
    for (const [c, v] of Object.entries(totals)) add(`${c} ${v.toFixed(2)}`);
    add(
      'Currencies stay separate. Unpriced items are excluded. Planning records do not confirm a reservation.',
      'muted',
    );
  }
  if (d.places.length) add('Your travel journal', 'heading');
  for (const p of d.places) {
    add(p.place.name, 'subheading');
    add(`${p.place.category} · ${p.overall ? p.overall.toFixed(1) + '/10' : 'To rate'}`);
    add([p.visitedOn, p.priceRange].filter(Boolean).join(' · '));
    add(p.notes);
    place(p.place);
    for (const [k, v] of Object.entries(p.scores)) add(`${k}: ${v}/10`);
    if (p.michelinStars != null) {
      add(
        `Michelin stars recorded by traveler: ${p.michelinStars}. Not a verified current award.`,
        'muted',
      );
    }
    for (const photo of p.photos) lines.push({ text: p.place.name, photo: photo.jpeg });
  }
  return lines;
}
export async function sharePDF(d: any, owner: string) {
  const pdf = await PDFDocument.create(),
    regular = await pdf.embedFont(StandardFonts.Helvetica),
    bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink = rgb(.13, .18, .16), bronze = rgb(.53, .39, .23), muted = rgb(.44, .48, .46);
  let page: any, y = 0;
  const clean = (s: string) =>
    String(s).replace(/[→↗]/g, ' > ').replace(/[–—]/g, '-').replace(/[‘’]/g, "'").replace(
      /[“”]/g,
      '"',
    ).replace(/[^\x20-\x7e\xa0-\xff\n]/g, '?');
  const next = () => {
    page = pdf.addPage([595, 842]);
    page.drawRectangle({ x: 0, y: 0, width: 595, height: 842, color: rgb(.975, .969, .95) });
    page.drawText('S E U R  /  A SHARED JOURNEY', {
      x: 42,
      y: 805,
      size: 9,
      font: bold,
      color: bronze,
    });
    page.drawLine({
      start: { x: 42, y: 790 },
      end: { x: 553, y: 790 },
      color: rgb(.85, .85, .82),
      thickness: .5,
    });
    page.drawText('Read-only · Booking references and private booking notes are hidden', {
      x: 42,
      y: 25,
      size: 8,
      font: regular,
      color: muted,
    });
    page.drawText(String(pdf.getPageCount()), {
      x: 540,
      y: 25,
      size: 8,
      font: regular,
      color: muted,
    });
    y = 763;
  };
  next();
  for (const line of sharedLines(d, owner)) {
    if (line.photo) {
      try {
        const image = await pdf.embedJpg(Uint8Array.from(atob(line.photo), (c) => c.charCodeAt(0)));
        const size = image.scale(Math.min(511 / image.width, 235 / image.height));
        if (y - size.height < 55) next();
        page.drawImage(image, {
          x: 42,
          y: y - size.height,
          width: size.width,
          height: size.height,
        });
        y -= size.height + 18;
      } catch { /* A validated JPEG may be undecodable; preserve original in attached JSON. */ }
      continue;
    }
    const heading = ['title', 'heading', 'subheading'].includes(line.kind || ''),
      font = heading ? bold : regular,
      size = line.kind === 'title'
        ? 28
        : line.kind === 'heading'
        ? 19
        : line.kind === 'subheading'
        ? 13
        : 10.5,
      color = line.kind === 'muted' ? muted : line.kind === 'link' ? bronze : ink;
    if (heading) y -= 10;
    const paragraphs = clean(line.text).split('\n');
    for (const paragraph of paragraphs) {
      let row = '';
      const rows: string[] = [];
      for (const word of paragraph.split(/\s+/)) {
        let candidate = row ? row + ' ' + word : word;
        if (font.widthOfTextAtSize(candidate, size) > 511 && row) {
          rows.push(row);
          row = word;
        } else row = candidate;
        while (font.widthOfTextAtSize(row, size) > 511) {
          let cut = row.length;
          while (font.widthOfTextAtSize(row.slice(0, cut), size) > 511) cut--;
          rows.push(row.slice(0, cut));
          row = row.slice(cut);
        }
      }
      rows.push(row);
      for (const text of rows) {
        if (y < size + 55) next();
        page.drawText(text, { x: 42, y, size, font, color });
        if (line.url && safeURL(line.url)) {
          const link = pdf.context.obj({
            Type: 'Annot',
            Subtype: 'Link',
            Rect: [42, y - 2, Math.min(553, 42 + font.widthOfTextAtSize(text, size)), y + size],
            Border: [0, 0, 0],
            A: { Type: 'Action', S: 'URI', URI: PDFString.of(line.url) },
          });
          page.node.addAnnot(pdf.context.register(link));
        }
        y -= size * 1.45;
      }
    }
    y -= 5;
  }
  // Full UTF-8 source preserves every name and photograph, including scripts absent
  // from the portable PDF font. Also available directly through ?format=json or txt.
  await pdf.attach(new TextEncoder().encode(JSON.stringify(d, null, 2)), 'journey.json', {
    mimeType: 'application/json',
    description: 'Complete shared journey data',
  });
  pdf.setTitle(d.title);
  pdf.setAuthor(owner);
  return await pdf.save();
}
