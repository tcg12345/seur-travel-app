import { decodePhoto, object, requireValue, uuid, validateDocument } from "./validation.ts";

const place = (p: any) => ({ id: p.id, name: p.name, city: p.city ?? "", category: p.category });
const distance = (a: number, b: number, c: number, d: number) => {
  const r = Math.PI / 180, h = Math.sin((c-a)*r/2)**2 + Math.cos(a*r)*Math.cos(c*r)*Math.sin((d-b)*r/2)**2;
  return 3958.7613 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0,h))));
};
const validCoordinate = (a: any, b: any) => Number.isFinite(a) && Number.isFinite(b) && Math.abs(a)<=90 && Math.abs(b)<=180;
export function recapSnapshot(input: any) {
  requireValue(object(input), "Invalid recap.");
  const d = input.document;
  validateDocument(d);
  requireValue(Array.isArray(input.selectedPhotoIDs) && input.selectedPhotoIDs.length<=60 && input.selectedPhotoIDs.every(uuid), "Choose up to 60 photos.");
  const selected = new Set<string>(input.selectedPhotoIDs.map((v: string)=>v.toLowerCase()));
  requireValue(selected.size===input.selectedPhotoIDs.length, "Duplicate photo selection.");
  const images: {id:string,jpeg:string}[] = [], found = new Set<string>();
  const places = d.places.map((p: any)=>({
    id:p.id, place:place(p.place), visitedOn:p.visitedOn ?? null, overall:p.overall,
    michelinStars:p.place.category==='restaurant' ? p.michelinStars ?? 0 : 0,
    photos:p.photos.filter((photo: any)=>selected.has(photo.id.toLowerCase())).map((photo: any)=>{
      const id = photo.id.toLowerCase();
      requireValue(!found.has(id), "Duplicate photo identifiers across journal entries.");
      requireValue(decodePhoto(photo.jpeg).length<=600000, "Resize photos before sharing a recap.");
      found.add(id); images.push({id,jpeg:photo.jpeg}); return {id};
    })
  }));
  requireValue(found.size===selected.size, "A selected photo is no longer in this trip.");
  if (input.mapJPEG != null) { decodePhoto(input.mapJPEG); images.push({id:'map',jpeg:input.mapJPEG}); }
  const ratings = places.map((p:any)=>p.overall).filter((n:number)=>n>0);
  const snapshot = {
    title:d.title, destination:d.destination, startDate:d.startDate ?? null, endDate:d.endDate ?? null, dateMode:d.dateMode,
    stops:d.stops.map((s:any)=>({id:s.id,name:s.name,arrival:s.arrival,nights:s.nights})),
    places,
    hotels:d.hotels.map((h:any)=>({id:h.id,place:place(h.place),checkIn:h.checkIn,checkOut:h.checkOut,
      rating:d.places.find((p:any)=>p.place.category==='hotel' && p.overall>0 &&
        ((p.place.id===h.place.id && p.place.source===h.place.source) || (p.place.name.toLowerCase()===h.place.name.toLowerCase() && (p.place.city??"").toLowerCase()===(h.place.city??"").toLowerCase())) &&
        (!p.visitedOn || (p.visitedOn>=h.checkIn && p.visitedOn<=h.checkOut)))?.overall ?? null})),
    stats:{nights:d.stops.reduce((n:number,s:any)=>n+s.nights,0),cities:d.stops.length,
      flightMiles:Math.floor(d.flights.filter((f:any)=>validCoordinate(f.departureLatitude,f.departureLongitude)&&validCoordinate(f.arrivalLatitude,f.arrivalLongitude)).reduce((n:number,f:any)=>n+distance(f.departureLatitude,f.departureLongitude,f.arrivalLatitude,f.arrivalLongitude),0)),
      rated:ratings.length,stars:places.reduce((n:number,p:any)=>n+p.michelinStars,0),average:ratings.length?ratings.reduce((a:number,b:number)=>a+b,0)/ratings.length:null},
    hasMap:input.mapJPEG!=null,
  };
  return {snapshot,images,documentID:d.id.toLowerCase(),visibility:d.visibility};
}
