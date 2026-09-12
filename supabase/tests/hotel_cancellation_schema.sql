-- Run inside a transaction with the new migration; all synthetic records roll back.
do $$
#variable_conflict use_variable
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); id uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); c public.travel_hotel_checkouts; claim jsonb;
begin
 insert into auth.users(id,email) values(a,'cancel-'||a||'@example.test'),(b,'cancel-'||b||'@example.test');
 insert into public.travel_hotel_checkouts(id,owner,quote_id,request_hash,state,review,client_reference,expires_at,booking,accepted_at)
 values(id,a,gen_random_uuid(),'test','confirmed','{}','cancel-schema-'||id,now()+interval '5 minutes','{"id":"test"}',now()) returning * into c;
 c:=public.travel_hotel_cancel_prepare(a,id,c.updated_at,jsonb_build_object('version',v,'state','review','expiresAt',now()+interval '2 minutes'));
 begin perform public.travel_hotel_cancel_accept(b,id,v);raise exception 'Cross-owner cancellation accepted'; exception when sqlstate 'PT404' then null;end;
 begin perform public.travel_hotel_cancel_accept(a,id,gen_random_uuid());raise exception 'Stale terms accepted'; exception when sqlstate 'PT409' then null;end;
 c:=public.travel_hotel_cancel_accept(a,id,v);assert c.cancellation->>'state'='queued';
 c:=public.travel_hotel_cancel_accept(a,id,v);assert c.cancellation->>'state'='queued';
 claim:=public.travel_hotel_cancel_claim();assert claim->>'operation'='cancel';assert claim->'checkout'->>'id'=id::text;
 assert public.travel_hotel_cancel_claim() is null;
 update public.travel_hotel_checkouts set lease_until=now()-interval '1 second',next_check=now()-interval '1 second' where travel_hotel_checkouts.id=id;
 claim:=public.travel_hotel_cancel_claim();assert claim->>'operation'='lookup';
 delete from auth.users where auth.users.id=a;
 assert (select owner is null and cancellation->>'state'='pending' from public.travel_hotel_checkouts where travel_hotel_checkouts.id=id);
 assert not has_function_privilege('authenticated','public.travel_hotel_cancel_accept(uuid,uuid,uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.travel_hotel_cancel_claim()','EXECUTE');
end $$;
