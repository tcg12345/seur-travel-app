import { categories, finite, object, requireValue, safeURL, text, uuid } from './validation.ts';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';
export const guideTags = ['Food & drink','Art & culture','Design','Outdoors','Hidden gems','Family','Weekend','Luxury'];
function jpeg(value: any, max: number) {
  if (value == null) return undefined;
  requireValue(typeof value==='string' && value.length<=max && /^[A-Za-z0-9+/]+={0,2}$/.test(value), 'Choose a smaller JPEG photo.');
  let bytes: string; try { bytes=atob(value); } catch { requireValue(false, 'Invalid photo.'); }
  requireValue(bytes.length>=4 && bytes.charCodeAt(0)===255 && bytes.charCodeAt(1)===216 && bytes.charCodeAt(bytes.length-2)===255 && bytes.charCodeAt(bytes.length-1)===217, 'Use a valid JPEG photo.');
  return value;
}
/** Public content uses an explicit allowlist. Booking data, attendees, costs and provider prose cannot leak through a trip import. */
export function sanitizedGuide(input: any) {
  requireValue(object(input) && uuid(input.id),'Invalid guide.');
  text(input.title,'guide title',100); text(input.destination,'destination',150); text(input.introduction,'introduction',5000);
  requireValue(Array.isArray(input.tags) && input.tags.length<=3 && new Set(input.tags).size===input.tags.length && input.tags.every((t: any)=>guideTags.includes(t)),'Choose up to three guide themes.');
  requireValue(Array.isArray(input.sections) && input.sections.length>=1 && input.sections.length<=20,'Use 1–20 sections.');
  const ids=new Set<string>(); let count=0;
  const sections=input.sections.map((s: any)=>{
    requireValue(object(s)&&uuid(s.id)&&!ids.has(s.id.toLowerCase()),'Invalid or duplicate section.');ids.add(s.id.toLowerCase());
    text(s.title,'section title',80);text(s.note,'section note',3000,true);
    requireValue(Array.isArray(s.places)&&s.places.length<=50,'Use at most 50 places per section.');
    requireValue(s.places.length || s.note.trim(),'Add a note or place to each section.');
    const places=s.places.map((item: any)=>{
      requireValue(object(item)&&uuid(item.id)&&!ids.has(item.id.toLowerCase())&&object(item.place),'Invalid guide place.');ids.add(item.id.toLowerCase());count++;
      text(item.note,'place note',3000,true);const p=item.place;
      text(p.name,'place name',200);text(p.city,'place city',150,true);text(p.address,'place address',500,true);
      requireValue(categories.has(p.category),'Choose a place category.');
      requireValue(!p.website || safeURL(p.website),'Use a valid website.');
      requireValue((p.latitude==null&&p.longitude==null)||(finite(p.latitude)&&finite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180),'Invalid map location.');
      return {id:item.id,note:item.note.trim(),photoJPEG:jpeg(item.photoJPEG,900000),place:{id:String(p.id ?? item.id).slice(0,200),name:p.name.trim(),category:p.category,city:p.city.trim(),address:p.address.trim(),website:p.website ?? '',phone:'',source:'Traveler guide',overview:'',...(p.latitude!=null?{latitude:p.latitude,longitude:p.longitude}:{})}};
    });
    return {id:s.id,title:s.title.trim(),note:s.note.trim(),places};
  });
  requireValue(count>=1&&count<=100,'Add 1–100 recommended places.');
  const result={id:input.id,title:input.title.trim(),destination:input.destination.trim(),introduction:input.introduction.trim(),tags:input.tags,sections,coverJPEG:jpeg(input.coverJPEG,1500000),thumbnailJPEG:jpeg(input.thumbnailJPEG,100000)};
  requireValue(new TextEncoder().encode(JSON.stringify(result)).length<=5000000,'This guide has too many photos. Remove a photo or use smaller images.');
  return result;
}
export async function guidePDF(remote: any) {
 const doc=await PDFDocument.create(), normal=await doc.embedFont(StandardFonts.Helvetica), bold=await doc.embedFont(StandardFonts.HelveticaBold);
 const g=remote.guide;let page:any,y=0;
 const clean=(s:string)=>String(s).replace(/[‘’]/g,"'").replace(/[“”]/g,'"').replace(/[–—]/g,'-').replace(/[^\x20-\x7e\xa0-\xff\n]/g,'?');
 const next=()=>{page=doc.addPage([595,842]);page.drawRectangle({x:0,y:0,width:595,height:842,color:rgb(.975,.969,.95)});page.drawText('S E U R / TRAVEL GUIDES',{x:44,y:803,size:10,font:bold,color:rgb(.53,.39,.23)});y=769;};next();
 const write=(value:string,size=11,heading=false)=>{const font=heading?bold:normal;for(const paragraph of clean(value).split('\n')){let line='';for(const word of paragraph.split(' ')){const candidate=line?line+' '+word:word;if(font.widthOfTextAtSize(candidate,size)>505&&line){if(y<55)next();page.drawText(line,{x:44,y,size,font});y-=size+6;line=word;}else line=candidate;}if(y<55)next();page.drawText(line.slice(0,250),{x:44,y,size,font});y-=size+8;}y-=5;};
 const image=async(value?:string)=>{if(!value)return;try{const img=await doc.embedJpg(value);const h=Math.min(240,505*img.height/img.width),w=h*img.width/img.height;if(y-h<55)next();page.drawImage(img,{x:44,y:y-h,width:w,height:h});y-=h+18;}catch{/* Invalid encoded pixels do not break the public reader. */}};
 write(g.title,24,true);write(g.destination,14);write('By '+remote.author.name+' (@'+remote.author.handle+')',10);await image(g.coverJPEG);write(g.introduction);
 for(const section of g.sections){write(section.title,17,true);write(section.note);for(const p of section.places){write(p.place.name,13,true);write([p.place.category,p.place.address].filter(Boolean).join(' / '),10);write(p.note);await image(p.photoJPEG);if(safeURL(p.place.website))write(p.place.website,9);}}
 return await doc.save();
}
