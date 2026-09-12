-- Run as an administrative validation transaction; no test rows are committed.
begin;
do $$
declare actor uuid:=gen_random_uuid(); other_actor uuid:=gen_random_uuid(); target uuid:=gen_random_uuid(); quote uuid:=gen_random_uuid(); c jsonb; again jsonb; claim jsonb; v uuid;
begin
  insert into auth.users(id,email) values(actor,'checkout-'||actor||'@example.test'),(other_actor,'checkout-'||other_actor||'@example.test');
  c:=public.travel_hotel_checkout_create(actor,target,quote,'fingerprint','{}','encrypted');
  assert (c->>'created')::boolean;
  again:=public.travel_hotel_checkout_create(actor,gen_random_uuid(),quote,'fingerprint','{}','encrypted');
  assert not (again->>'created')::boolean;
  assert again->'checkout'->>'id'=target::text;
  begin
    perform public.travel_hotel_checkout_create(actor,target,quote,'different','{}','encrypted');
    raise exception 'Changed payload was accepted';
  exception when sqlstate 'PT409' then null; end;
  v:=(c->'checkout'->>'quote_version')::uuid;
  update public.travel_hotel_checkouts set state='review',lease_until=null,lease_token=null where id=target;
  begin
    perform public.travel_hotel_checkout_accept(other_actor,target,v);
    raise exception 'Cross-owner acceptance was allowed';
  exception when sqlstate 'PT404' then null; end;
  begin
    perform public.travel_hotel_checkout_accept(actor,target,gen_random_uuid());
    raise exception 'Stale quote was accepted';
  exception when sqlstate 'PT409' then null; end;
  assert public.travel_hotel_checkout_claim(target) is null;
  perform public.travel_hotel_checkout_accept(actor,target,v);
  perform public.travel_hotel_checkout_accept(actor,target,v);
  claim:=public.travel_hotel_checkout_claim(target);
  assert claim->>'operation'='book';
  assert public.travel_hotel_checkout_claim(target) is null;
  update public.travel_hotel_checkouts set lease_until=now()-interval '1 second',next_check=now()-interval '1 second' where id=target;
  claim:=public.travel_hotel_checkout_claim(target);
  assert claim->>'operation'='lookup';
  -- Deleting the owner retains an already accepted, unresolved attempt.
  delete from auth.users where id=actor;
  assert (select owner is null and private_payload='encrypted' from public.travel_hotel_checkouts where id=target);
  update public.travel_hotel_checkouts set state='confirmed' where id=target;
  assert (select private_payload is null from public.travel_hotel_checkouts where id=target);
  assert not has_table_privilege('anon','public.travel_hotel_checkouts','SELECT');
  assert not has_table_privilege('authenticated','public.travel_hotel_checkouts','SELECT');
  assert (select relrowsecurity from pg_class where oid='public.travel_hotel_checkouts'::regclass);
end;
$$;
rollback;
