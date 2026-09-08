-- Auth deletes accounts using its restricted database role. Cascading FKs already
-- remove recap snapshots/media; a document DELETE trigger must not perform extra
-- service-only queries in that context. Explicit document deletion is cleaned up
-- by the authenticated Edge endpoint after its ownership check.
drop trigger travel_recap_source_cleanup on public.travel_documents;
create or replace function public.travel_recap_source_cleanup() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if new.visibility='private' and old.visibility<>'private' then
   delete from public.travel_recaps where owner_id=old.owner_id and document_id=old.id;
 end if;
 return null;
end $$;
create trigger travel_recap_source_cleanup after update of visibility on public.travel_documents for each row execute function public.travel_recap_source_cleanup();
