create policy flight_watches_server_only on public.travel_flight_watches for all to anon, authenticated using (false) with check (false);
create policy push_jobs_server_only on public.travel_push_jobs for all to anon, authenticated using (false) with check (false);
