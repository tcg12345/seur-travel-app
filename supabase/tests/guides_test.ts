import assert from 'node:assert/strict';
import {sanitizedGuide,guidePDF} from '../functions/travel-api/guides.ts';
const id='00000000-0000-4000-8000-000000000010',owner='00000000-0000-4000-8000-000000000001';
function guide(){return {id,title:'A slower Paris',destination:'Paris',introduction:'A guide with personal recommendations.',tags:['Art & culture'],privateBooking:'secret',ownerID:'forged',sections:[{id:'00000000-0000-4000-8000-000000000011',title:'First morning',note:'Leave time to wander.',places:[{id:'00000000-0000-4000-8000-000000000012',note:'Come early.',cost:{amount:30},place:{id:'place',name:'Eiffel Tower',city:'Paris',category:'landmark',address:'Champ de Mars',phone:'PRIVATE',website:'https://www.toureiffel.paris/',latitude:48.85,longitude:2.29,overview:'Provider prose',rating:5}}]}]};}
Deno.test('guides publish only explicit author content and basic location facts',()=>{
 const clean=sanitizedGuide(guide()),s=JSON.stringify(clean);
 assert.equal(clean.sections[0].places[0].note,'Come early.');
 for(const secret of ['privateBooking','forged','PRIVATE','Provider prose','cost','rating'])assert.ok(!s.includes(secret));
 assert.equal(clean.sections[0].places[0].place.source,'Traveler guide');
});
Deno.test('guides reject empty chapters, duplicates, oversized content and unsafe links',()=>{
 for(const change of [(g:any)=>g.introduction='',(g:any)=>g.sections=[],(g:any)=>g.sections[0].places=[],(g:any)=>g.sections[0].places.push(g.sections[0].places[0]),(g:any)=>g.sections[0].places[0].place.website='javascript:alert(1)',(g:any)=>g.sections[0].places[0].place.latitude=NaN,(g:any)=>g.tags=['unknown'],(g:any)=>g.coverJPEG=btoa('<svg/>'),(g:any)=>g.title='a'.repeat(101)]){
  const g=guide();change(g);assert.throws(()=>sanitizedGuide(g));
 }
});
Deno.test('public guide PDF contains a real readable document',async()=>{
 const bytes=await guidePDF({guide:sanitizedGuide(guide()),author:{id:owner,name:'Alice',handle:'alice'}});
 assert.ok(new TextDecoder().decode(bytes.slice(0,5)).startsWith('%PDF-'));assert.ok(bytes.length>1000);
});
Deno.test('guide routes authenticate writes, bind the session owner, and preserve publication revisions',async()=>{
 Deno.env.set('SUPABASE_URL','https://guides.test');Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','guide-test-key');
 const {handler}=await import('../functions/travel-api/index.ts');const original=globalThis.fetch;let publication:any;let available=true;let publishes=0;
 globalThis.fetch=((url:any,init?:RequestInit)=>{
  const path=String(url);
  if(path.includes('/travel_sessions?'))return Promise.resolve(Response.json([{user_id:owner}]));
  const b=init?.body?JSON.parse(String(init.body)):{};
  if(path.endsWith('/travel_limit'))return Promise.resolve(Response.json(true));
  if(path.endsWith('/travel_guide_publish')){publishes++;assert.equal(b.actor,owner);assert.equal(b.expected,0);assert.equal(b.doc.ownerID,undefined);publication={guide:b.doc,author:{id:owner,handle:'alice',name:'Alice'},revision:1,isPublished:true,isSummary:false,updatedAt:1,placeCount:1};return Promise.resolve(Response.json(publication));}
  if(path.endsWith('/travel_guides_read'))return Promise.resolve(Response.json(available&&publication?[publication]:[]));
  if(path.endsWith('/travel_guide_unpublish')){assert.equal(b.actor,owner);assert.equal(b.expected,1);available=false;return Promise.resolve(Response.json({...publication,isPublished:false,revision:2}));}
  throw Error('Unexpected provider request '+path);
 }) as typeof fetch;
 const request=(path:string,method='GET',body?:any,signed=false)=>new Request('https://edge.test/travel-api'+path,{method,headers:{'Content-Type':'application/json',...(signed?{Authorization:'Bearer '+'a'.repeat(80)}:{})},body:body?JSON.stringify(body):undefined});
 try {
  assert.equal((await handler(request('/v1/guides/'+id,'PUT',{guide:guide(),expectedRevision:0}))).status,401);assert.equal(publishes,0);
  const saved=await handler(request('/v1/guides/'+id,'PUT',{guide:guide(),expectedRevision:0,ownerID:'forged'},true));assert.equal(saved.status,200);assert.equal((await saved.json()).revision,1);
  assert.equal((await handler(request('/v1/guides/'+id))).status,200);
  const pdf=await handler(request('/v1/guides/'+id+'/pdf'));assert.equal(pdf.headers.get('content-type'),'application/pdf');assert.equal(pdf.status,200);
  assert.equal((await handler(request('/v1/guides/'+id+'/unpublish','POST',{expectedRevision:1},true))).status,200);
  assert.equal((await handler(request('/v1/guides/'+id))).status,404);
  assert.equal((await handler(request('/v1/guides/'+id+'/pdf'))).status,404);
 } finally{globalThis.fetch=original;}
});
