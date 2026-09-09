import assert from 'node:assert/strict';
Deno.env.set('SUPABASE_URL','https://auth.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','test-server-key');
const {accountAuth,authOptions,emailAddress,passwordValue,verifiedUser}=await import('../functions/travel-api/account-auth.ts');
const user={id:'00000000-0000-4000-8000-000000000001',email:'qa@example.com',email_confirmed_at:'2026-09-08T00:00:00Z',user_metadata:{name:'QA',handle:'travel_qa'}};
async function mock(overrides:Record<string,any>,run:(calls:{path:string,body:any}[])=>Promise<void>) {
 const original=globalThis.fetch,calls:{path:string,body:any}[]=[];let profile:any=null;
 globalThis.fetch=async(input:any,init?:RequestInit)=>{
  const url=new URL(typeof input==='string'?input:input.url),path=url.pathname+url.search,body=init?.body?JSON.parse(String(init.body)):undefined;calls.push({path,body});
  if (path in overrides) { const result=typeof overrides[path]==='function'?overrides[path](body):overrides[path];return result instanceof Response?result:Response.json(result); }
  if(path==='/auth/v1/settings')return Response.json({external:{email:true,apple:true,google:true},mailer_autoconfirm:false});
  if(path==='/rest/v1/rpc/travel_user')return Response.json(profile);
  if(path==='/rest/v1/travel_profiles'){profile={id:body.id,name:body.name,handle:body.handle};return Response.json(profile);}
  if(path==='/rest/v1/travel_sessions')return Response.json({});
  if(path==='/auth/v1/logout?scope=local')return Response.json({});
  throw new Error('Unexpected endpoint: '+path);
 };
 try{await run(calls);}finally{globalThis.fetch=original;}
}
Deno.test('eight-character password and real email validation',()=>{
 assert.equal(passwordValue('eight888'),'eight888');assert.throws(()=>passwordValue('short77'));
 assert.equal(emailAddress(' QA@Example.COM '),'qa@example.com');assert.throws(()=>emailAddress('qa@accounts.seur.invalid'));
 assert.throws(()=>emailAddress('missing@domain'));assert.throws(()=>passwordValue('a'.repeat(257)));
});
Deno.test('signup stays pending and never creates an authenticated Seur session',async()=>{
 await mock({'/auth/v1/signup':{user}},async calls=>{
  assert.deepEqual(await accountAuth('email/signup',{email:'qa@example.com',name:'QA',handle:'travel_qa',password:'eight888'}),{pending:true,email:'qa@example.com'});
  assert.equal(calls.filter(x=>x.path==='/rest/v1/travel_sessions').length,0);
  const body=calls.find(x=>x.path==='/auth/v1/signup')!.body;assert.equal(body.email,'qa@example.com');assert.equal(body.email_confirm,undefined);
 });
});
Deno.test('signup fails closed when email confirmations are disabled',async()=>{
 await mock({'/auth/v1/settings':{external:{email:true},mailer_autoconfirm:true}},async calls=>{
  await assert.rejects(()=>accountAuth('email/signup',{email:'qa@example.com',name:'QA',handle:'travel_qa',password:'eight888'}));
  assert.equal(calls.some(x=>x.path==='/auth/v1/signup'),false);
 });
});
Deno.test('unverified auth user cannot receive a Seur session even with forged metadata',async()=>{
 const unverified={...user,email_confirmed_at:null,user_metadata:{email_verified:true}};
 assert.equal(verifiedUser(unverified),false);
 await mock({'/auth/v1/token?grant_type=password':{access_token:'auth-jwt',user:unverified}},async calls=>{
  await assert.rejects(()=>accountAuth('email/login',{email:user.email,password:'eight888'}));
  assert.equal(calls.some(x=>x.path==='/rest/v1/travel_sessions'),false);
 });
});
Deno.test('verified email OTP creates profile and opaque revocable session only',async()=>{
 await mock({'/auth/v1/verify':{access_token:'auth-jwt',refresh_token:'must-not-leave',user}},async calls=>{
  const reply=await accountAuth('email/verify',{email:user.email,code:'12345678'});
  assert.ok('token' in reply && 'user' in reply); assert.match(reply.token!,/^[a-f0-9]{80}$/);assert.equal(reply.user.id,user.id);assert.equal('refresh_token' in reply,false);
  assert.equal(calls.find(x=>x.path==='/auth/v1/verify')!.body.type,'signup');
  assert.equal(calls.find(x=>x.path==='/rest/v1/travel_sessions')!.body.token_hash.length,64);
  assert.ok(calls.some(x=>x.path==='/auth/v1/logout?scope=local'));
 });
});
Deno.test('bad verification codes and rejected provider tokens never mint a session',async()=>{
 await mock({'/auth/v1/verify':Response.json({error_code:'otp_expired'},{status:403}),'/auth/v1/token?grant_type=id_token':Response.json({error:'invalid token'},{status:400})},async calls=>{
  await assert.rejects(()=>accountAuth('email/verify',{email:user.email,code:'12345678'}));
  await assert.rejects(()=>accountAuth('apple',{idToken:'x'.repeat(150),nonce:'n'.repeat(43)}));
  assert.equal(calls.some(x=>x.path==='/rest/v1/travel_sessions'),false);
 });
});
Deno.test('Apple token and raw nonce are verified by Auth before creating profile',async()=>{
 await mock({'/auth/v1/token?grant_type=id_token':{access_token:'auth-jwt',user}},async calls=>{
  const reply=await accountAuth('apple',{idToken:'x'.repeat(150),nonce:'n'.repeat(43),name:'Apple Name',id:'forged-user'});
  assert.ok('user' in reply);
  const request=calls.find(x=>x.path==='/auth/v1/token?grant_type=id_token')!.body;
  assert.equal(request.provider,'apple');assert.equal(request.nonce,'n'.repeat(43));assert.equal(reply.user.id,user.id);assert.equal(reply.user.name,'Apple Name');
 });
});
Deno.test('Google uses a fixed callback and S256 PKCE; exchange requires verifier',async()=>{
 await mock({'/auth/v1/token?grant_type=pkce':{access_token:'auth-jwt',user}},async calls=>{
  const response=await accountAuth('google/start',{challenge:'c'.repeat(43),redirect:'https://evil.example'}); assert.ok('url' in response); const url=new URL(response.url!);
  assert.equal(url.searchParams.get('redirect_to'),'seur://auth/callback');assert.equal(url.searchParams.get('code_challenge_method'),'s256');
  await assert.rejects(()=>accountAuth('google/exchange',{code:'valid-auth-code',verifier:'short'}));
  await accountAuth('google/exchange',{code:'valid-auth-code',verifier:'v'.repeat(43)});
  assert.equal(calls.find(x=>x.path==='/auth/v1/token?grant_type=pkce')!.body.code_verifier,'v'.repeat(43));
 });
});
Deno.test('provider availability returns no secrets',async()=>{
 await mock({},async()=>{assert.deepEqual(await authOptions(),{apple:true,google:true,email:true,minimumPasswordLength:8});});
});
