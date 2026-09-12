-- Record cancellations retrieved from LiteAPI; this does not submit cancellation.
alter table public.travel_hotel_checkouts drop constraint travel_hotel_checkouts_state_check;
alter table public.travel_hotel_checkouts add constraint travel_hotel_checkouts_state_check check (state in ('prebooking','review','prebook_unknown','expired','queued','submitting','pending_confirmation','confirmed','needs_support','cancelled'));
