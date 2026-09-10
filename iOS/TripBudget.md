# Trip budget and companion splits

Budgeting is optional. Open a trip's **••• → Add budget**, choose a home currency and optional target, then save. Cancel leaves the trip unchanged; adding prices alone never shows the card. Existing configured budgets remain available. The compact **Trip budget** summary starts collapsed in Plan (including Today) and Recap. Expand it for a quick progress check, then tap **Open budget tracker** for the dedicated dashboard. The budget widget opens this dashboard directly. You can also use **••• → Edit budget & companions**. Edit the home currency and target, and add companions by name, from accepted friends, or from a conversation's members. Adding companions does not send messages or grant access to the trip. Up to 40 companions are supported.

## Dashboard and quick expenses

The dashboard uses a restrained charcoal and gold overview, a budget progress ring, category bars, an itinerary-day spending chart, companion balances and searchable expense history. All / Spent / Planned filters use the same completion rules as the trip. Budget settings remain available in the top-right toolbar. Missing currency rates never turn an unknown total into zero; history always shows original amounts.

The compact floating **Add expense** button stays at the bottom-right, with a native glass press response, a plus-icon bounce and light impact feedback on opening. It maintains a minimum 44-point tap target, uses high-contrast text in dark mode and suppresses the icon animation with Reduce Motion.

**Add expense** collects a name, category, trip day, amount and currency, with optional equal companion splits. It creates a custom itinerary event on that day, avoiding a second expense ledger or duplicate totals. “Include in spent” marks the event done. Selecting a history row edits its amount, currency, split and completion/payment status in the original event or booking. Names and booking details remain editable through their existing itinerary editors. Changes are saved to the latest local journey, preserving unrelated edits.

The daily chart shows up to 14 days with recorded spending, grouped by itinerary dates (activity date, hotel check-in or flight departure), not unknown payment timestamps. The separate spent-per-day metric uses all elapsed trip days. No new API calls or migrations are introduced by the dashboard.

## Spending

The target applies to the whole trip. Planned totals include all priced events, hotels and flights. **Spent so far** includes events explicitly marked **Done** and hotel/flight costs explicitly marked **Paid**. Change a cost to the amount actually paid; this version does not keep separate quoted and final prices. Unpriced items do not count. Done is available in Today actions, the event editor and the agenda context menu, and completed events no longer appear as Up next.

Per-day spending is spent divided by elapsed calendar days, including today, capped at the trip's end. It uses the trip's current destination time zone. It is unavailable before departure or for flexible-date trips. Empty days count; bookings marked paid before departure still count toward spending.

## Equal splits and settlement

A cost can specify **Who paid** and **Split between**. The payer may cover other companions without sharing the expense themselves. Only done events and paid bookings enter the settlement. Rounding uses each currency's minor unit and allocates remainders deterministically; payments and shares always balance. Expenses in the same currency net against one another. Original currencies remain separate, so exchange-rate changes do not change obligations.

The dashboard’s **Settle up** disclosure is available during and after the trip, including through the recap’s budget summary. It shows who owes whom; it does not transfer money or record settlement payments. Costs without a payer and a split are excluded. A companion referenced by a cost cannot be removed until their splits are updated.

Companions, completion, targets and splits persist in the local journey and JSON exports/imports, and in explicit cloud saves. Shared native previews display the budget and settlement read-only under the existing trip access rules. Sharing a trip also shares these fields; the settings explain this. Public link JSON and the PDF's attached journey JSON retain them. The PDF's printed cost section continues to show planned totals. Templates discard targets, companion identities, completion and payment history, retaining only optional price estimates.

## Daily conversion

The app calls authenticated `GET /v1/exchange-rates` on travel-api. The Edge Function fetches [Frankfurter v2 daily reference rates](https://frankfurter.dev/) with USD as the pivot and stores them in the existing server-only provider cache. Cache hits avoid provider calls for the rest of the UTC day. Concurrent misses within an instance coalesce. The response includes each rate's publication date and fetch time; these are reference estimates, not bank or card transaction rates.

Provider failures can use up to seven days of cached data, explicitly marked stale. iOS also retains the last rate response locally and labels saved rates requiring refresh. Missing conversions make the combined total unavailable rather than silently omitting expenses; original currency totals remain visible offline. The supported home currencies match the existing price picker. The provider requires no secret or paid API subscription.

No schema migration is needed: optional ledger fields live in existing journey JSON, and FX uses `travel_provider_cache` with its current RLS and server-only access. The function must include `exchange-rates.ts` when deployed.
