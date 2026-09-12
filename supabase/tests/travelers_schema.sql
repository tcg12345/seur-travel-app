-- Administrative acceptance only: all test users and rows are rolled back.
begin;
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); q uuid:=gen_random_uuid(); v integer;
begin
 insert into auth.users(id,email) values(a,'traveler-'||a||'@example.test'),(b,'traveler-'||b||'@example.test');
 perform public.travel_traveler_save(a,p,0,repeat('x',30),false);
 assert (select is_default and version=1 from public.travel_traveler_profiles where owner=a and id=p);
 perform public.travel_traveler_save(a,q,0,repeat('y',30),true);
 assert (select not is_default and version=2 from public.travel_traveler_profiles where owner=a and id=p);
 assert (select is_default from public.travel_traveler_profiles where owner=a and id=q);
 begin
  perform public.travel_traveler_save(a,p,1,repeat('z',30),true);
  raise exception 'Stale save accepted';
 exception when sqlstate 'PT409' then null; end;
 begin
  perform public.travel_traveler_delete(a,p,1);
  raise exception 'Stale delete accepted';
 exception when sqlstate 'PT409' then null; end;
 perform public.travel_traveler_delete(b,p,2);
 assert (select count(*)=2 from public.travel_traveler_profiles where owner=a);
 perform public.travel_traveler_delete(a,q,1);
 assert (select is_default and version=3 from public.travel_traveler_profiles where owner=a and id=p);
 perform public.travel_traveler_save(b,p,0,repeat('b',30),false);
 assert (select count(*)=1 from public.travel_traveler_profiles where owner=b);
 for v in 1..19 loop perform public.travel_traveler_save(a,gen_random_uuid(),0,repeat('x',30),false); end loop;
 begin
  perform public.travel_traveler_save(a,gen_random_uuid(),0,repeat('x',30),false);
  raise exception 'Profile limit bypassed';
 exception when sqlstate 'PT400' then null; end;
 assert (select count(*)=1 from public.travel_traveler_profiles where owner=a and is_default);
 delete from auth.users where id=a;
 assert not exists(select 1 from public.travel_traveler_profiles where owner=a);
 assert (select count(*)=1 from public.travel_traveler_profiles where owner=b);
 assert not has_table_privilege('anon','public.travel_traveler_profiles','SELECT');
 assert not has_table_privilege('authenticated','public.travel_traveler_profiles','SELECT,INSERT,UPDATE,DELETE');
 assert not has_function_privilege('authenticated','public.travel_traveler_save(uuid,uuid,integer,text,boolean)','EXECUTE');
 assert not has_function_privilege('anon','public.travel_traveler_delete(uuid,uuid,integer)','EXECUTE');
 assert (select relrowsecurity from pg_class where oid='public.travel_traveler_profiles'::regclass);
end $$;
rollback;
