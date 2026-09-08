import assert from "node:assert/strict";
import { recapSnapshot } from "../functions/travel-api/recaps.ts";
const seed = JSON.parse(await Deno.readTextFile(new URL("../../iOS/Aurum/Resources/TripTemplates.json", import.meta.url)))[0];
function payload() {
 const document=structuredClone(seed);document.isTemplate=false;delete document.templateMeta;
 const a=crypto.randomUUID(),b=crypto.randomUUID();
 document.description='PRIVATE';document.hotels[0].confirmation='PRIVATE';document.hotels[0].notes='PRIVATE';document.hotels[0].roomType='PRIVATE';
 document.events[0].attendees='PRIVATE';document.events[0].description='PRIVATE';
 document.places=[{id:crypto.randomUUID(),place:{id:'place',name:'A table',category:'restaurant',city:'Monaco',phone:'PRIVATE',address:'PRIVATE',website:'PRIVATE',source:'Manual entry',overview:'PRIVATE'},overall:9,scores:{},notes:'PRIVATE',priceRange:'',michelinStars:3,photos:[{id:a,jpeg:'/9j/AA=='},{id:b,jpeg:'/9j/Ag=='}]}];
 return {document,selectedPhotoIDs:[a],mapJPEG:'/9j/BA=='};
}
Deno.test('recap projection strips private and unknown fields, excludes deselected media',()=>{
 const p=payload();p.document.unknown='PRIVATE';const result=recapSnapshot(p);
 assert(!JSON.stringify(result).includes('PRIVATE'));
 assert.equal(result.images.length,2);assert.equal(result.images[0].id,p.selectedPhotoIDs[0]);
 assert(!JSON.stringify(result).includes(p.document.places[0].photos[1].id));
 assert.equal(result.snapshot.stats.rated,1);assert.equal(result.snapshot.stats.stars,3);assert.equal(result.snapshot.stats.average,9);
 assert.equal(result.visibility,p.document.visibility);assert.equal(p.document.places[0].photos.length,2);
});
Deno.test('empty selection has no photos; forged and duplicate IDs rejected',()=>{
 const p=payload();p.selectedPhotoIDs=[];assert.equal(recapSnapshot(p).images.length,1);
 p.selectedPhotoIDs=[crypto.randomUUID()];assert.throws(()=>recapSnapshot(p));
 p.selectedPhotoIDs=[p.document.places[0].photos[0].id,p.document.places[0].photos[0].id];assert.throws(()=>recapSnapshot(p));
});
Deno.test('hotel stars and unscored journal records do not inflate headline ratings',()=>{
 const p=payload();p.document.places[0].place.category='hotel';p.document.places[0].overall=0;
 const r=recapSnapshot(p);assert.equal(r.snapshot.stats.stars,0);assert.equal(r.snapshot.stats.rated,0);assert.equal(r.snapshot.stats.average,null);
});
