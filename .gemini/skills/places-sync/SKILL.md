---
name: places-sync
description: Discovery pass across Google Calendar (and supporting email + Fathom signal) to find physical Places not yet captured in + Atlas/Places/. Stages candidates in + Inbox/place-candidates/ for review. Mirrors /people-sync and /orgs-sync, but for the place facet — and is facet-aware (per the "Places and Orgs are facets, not categories" convention, a single entity can be both Place and Org, so this skill detects when an existing Org should also get a Place note).
---

# /places-sync

Scan recent calendar activity across all `google_*` MCPs, propose new Place notes for physical addresses not yet captured in `+ Atlas/Places/`, and detect when an existing Organization should gain its Place facet. Never writes directly to `+ Atlas/Places/` — candidates stage in `+ Inbox/place-candidates/` for review.

## Inputs

- `$1` (optional): lookback window, e.g. `30d` (default), `7d`, `90d`. Calendar signal is dense — 30d is enough.
- `$2` (optional): `interactive` (default) or `scheduled`. In scheduled mode, candidate staging proceeds without confirmation (drafts only — no `+ Atlas/` writes).

## Procedure

1. **Resolve window.** Compute `since = today - lookback`.

2. **Collect calendar locations across all accounts.** Fan out `google_calendar_list_events` for every `google_*` MCP over the window in a single tool-use block. Extract for each event:
   - `summary` (event title)
   - `location` (the raw location string — the only signal that matters for this skill)
   - `attendees` (count + whether external)
   - `start.date` or `start.dateTime` (for recency)
   - `creator.email` / `organizer.email` (for downstream org cross-linking)

   Also fan out (lower-weight signal):
   - **Email signatures** — `google_gmail_search_emails` with `newer_than:<window>` on each `google_*` MCP; scan the bottom 20 lines of each thread's first message for `\d+ [A-Za-z ]+ (St|Ave|Blvd|Road|Rd|Way|Drive|Dr|Court|Ct|Lane|Ln)` patterns or `\b\d{5}(-\d{4})?\b` (ZIP code). Optional — skip in `scheduled` mode if Gmail volume is heavy.
   - **Fathom locations** — skipped by default since Fathom rarely records a `location` field; meetings are virtual.

3. **Existing inventory.** Build three sets of already-known place identifiers:
   - **Places already captured** — read `+ Atlas/Places/*.md`; capture `title` and `address`.
   - **Place facets implied by existing Orgs** — read `+ Atlas/Organizations/*.md`; for each Org, scan its `## Places` section for any `[[wikilink]]` references (those are facets that already cross-link). Also capture the Org's `title` so we can detect when a calendar location matches an Org by name.
   - **Pending candidates** — read `+ Inbox/place-candidates/*.md` if the folder exists, to avoid duplicate staging.

4. **Normalize locations into a touchpoint table.** One row per (canonicalized address, source event, date, attendee_count). Canonicalization rules:
   - Strip trailing `, USA`.
   - Lowercase the whole string for matching, but preserve original casing for the title.
   - Split a location like `"Acme School, 141 Grove St, Auburndale, MA 02466"` into `business_name="Acme School"` + `address="141 Grove St, Auburndale, MA 02466"`. Use the comma-with-state-abbreviation heuristic: the segment before the first comma with a US state code (`MA`, `NY`, `IL`, etc.) is usually the business name; the rest is the postal address.
   - If the string has no recognizable address (e.g. just a city, just a building name), keep it intact as `display_name` and skip splitting.
   - Roll up touchpoints per canonicalized address — multiple events at the same address are one row.

5. **Filter noise.** Drop touchpoints where:
   - `location` is empty or whitespace-only.
   - `location` is a virtual meeting URL — anything matching `https://meet.google.com/`, `zoom.us`, `teams.microsoft.com`, `webex.com`, `slack.com`, `tel.meet`, `tel:`, or a phone number.
   - `location` is `"Home"`, `"Out of office"`, `"Busy"`, or otherwise a Reclaim auto-block / OOO signal.
   - `location` is just an airport code (`"Boston BOS"`, `"Chicago ORD"`) without context — these are travel buffers from flight events, not places to track.
   - `location` matches the user's home address. Read `+ Atlas/Places/*.md` and skip any address that matches a note with `type: home`. (This generalizes: never re-stage a known-home address.)
   - The event was declined by the user (`responseStatus: declined` in the user's attendee record).
   - The event has no attendees other than the user (single-attendee blocks shouldn't surface — they're calendar holds, not visits-to-a-place).

6. **Classify each location into one of three buckets.**
   - **Bucket A — Address matches existing Place** (already in `+ Atlas/Places/`). Surface as "active places" for awareness; no staging.
   - **Bucket B — Business name matches existing Org, but Org has no Place facet yet** (Org exists, no `[[wikilink]]` in its `## Places` section). High-value gap — per the facet convention the entity should have both facets. Stage with explicit "promote-and-cross-link" guidance.
   - **Bucket C — Truly new location** (neither a Place nor an Org match). Apply threshold (step 7).

7. **Apply threshold for Bucket C (unknowns).** Require at least one of:
   - **≥2 distinct events at the same address** across the window (recurring usage signals a real place worth tracking), OR
   - **One calendar event at this location with ≥2 attendees** including the user (a meeting at a venue is high-signal even if it only happened once), OR
   - **The location appears in a Fathom-recorded meeting** that the user attended (cross-pollinated with `/orgs-sync` — same Bucket C bar as people-sync).

   Anything below threshold is logged but not staged.

8. **Suggest `type` classification** based on heuristics from name + address (best-effort, user finalizes at promotion):
   - Name contains `Church`, `Chapel`, `Cathedral`, `Mosque`, `Synagogue`, `Temple` → `church`
   - Name contains `Elementary`, `Middle School`, `High School`, `Academy`, `University`, `College` → `other` (educational)
   - Name contains `Restaurant`, `Cafe`, `Café`, `Coffee`, `Kitchen`, `Bistro`, `Bar`, `Grill`, `Diner`, `Pizzeria`, `Taqueria` → `restaurant`
   - Name contains `Workbar`, `WeWork`, `Coworking`, `Office`, `HQ`, `Studio` → `office`
   - Name contains `Stadium`, `Arena`, `Theater`, `Theatre`, `Center`, `Hall`, `Park`, `Gym`, `Dance Center`, `Gymnastics` → `venue`
   - Pure address with no business name AND the user is the *only* internal attendee → `home` (likely a friend or family residence)
   - Default → `other`

8b. **Web fallback for missing `address:` on staged candidates.** If a candidate has a `business_name` parsed but no `address:` from the calendar (the location string was just the name, e.g. `"Local Cafe"`), do a bounded internet lookup before staging:
   - Issue **one** `WebSearch` per address-less candidate: `"<business_name>" <city or region hint> address`. The city/region hint comes from the user's home anchor — read `+ Atlas/Places/*.md` for any `type: home` notes and use that city/state as the disambiguator. Without a hint, **do not search** — chain businesses will pollute the inbox.
   - Pick the top result that's clearly the official listing (Google Maps, Yelp, official site). If multiple plausible candidates remain (different streets, different cities), **leave `address:` blank** and add a `## Notes` line listing the candidate URLs for the user.
   - On unambiguous match, populate `address:` and append `<!-- address sourced from web lookup, verify -->` inline. Cite the URL in `## Notes` as `_Address from web lookup: <URL>._`.
   - **Hard cap: 1 WebSearch + up to 2 WebFetch calls per candidate.** Skip the lookup entirely in `scheduled` mode — sync runs should not burn web quota on uncertain matches.

9. **Place-facet check (Bucket B specifically).** For each candidate where the business name matches an existing Org by title (`+ Atlas/Organizations/<Org Name>.md`):
   - Cross-reference the Org's `## Places` section to confirm no Place wikilink exists for this address.
   - In the staging note, populate `## Related organizations` with the matched Org and add a Notes line: `_Cross-link plan: when promoting this Place, also edit [[<Org>]]'s ## Places section to add [[<Place>]]._`
   - This is the explicit mechanic that keeps facets in sync — the staging note tells the user exactly what to do at promotion time.

10. **Bucket B + C — stage candidates.** Write a stub at `+ Inbox/place-candidates/<Place Name>.md` using the Place template. The `Place Name` is the business name if one was parsed in step 4; otherwise the raw address (sanitized for filesystem-safe characters).

    ```markdown
    ---
    title: <Place Name>
    type: <suggested per step 8>
    address: <parsed address>
    created: <today>
    tags: [place, needs-review, stub]
    ---

    # <Place Name>

    ## Context
    <!-- Auto-staged by /places-sync on <today>. Review before promoting to + Atlas/Places/. -->
    <N> event(s) at this location in the last <window>. <Most-recent date>: "<most recent event title>".

    ## Related people
    <!-- [[wikilinks]] to + Atlas/People/* who attended events here -->
    - [[Person Name]] (attended <N> events here)

    ## Related organizations
    <!-- For Bucket B: matched Org. For Bucket C: blank for user to fill. -->
    - [[Org Name]] (this Place is a facet of this Org — see Notes below for cross-link plan)

    ## Notes
    <!-- For Bucket B candidates: -->
    _Cross-link plan: when promoting this Place, also edit [[<Org>]]'s ## Places section to add [[<this Place title>]]._

    ## Evidence
    - google_<slug> · <date> · "<event title>" (<attendee_count> attendees)
    - ...

    ## Related
    -
    ```

    If a stub already exists in `+ Inbox/place-candidates/` for this place, **append** new evidence bullets rather than overwriting. Update `last_seen` (if you add it) to the newest date.

11. **Report.** Output a four-section summary:
    - **Active places (Bucket A)** — count of known places with events in the window. List names only, no diffs.
    - **Place-facet gaps (Bucket B)** — list of staged stubs at `+ Inbox/place-candidates/` for entities that are already Orgs but lack a Place note. **Highest-value new captures** because they're the facet-rule fix path.
    - **New location candidates (Bucket C)** — list of staged stubs for truly-new locations meeting threshold.
    - **Below threshold (logged, not staged)** — one-line tally with count only. Note any single-touchpoint locations that almost-cleared.

## Promotion path

Candidates are promoted out of `+ Inbox/place-candidates/` manually or via `/process-inbox`:
- User reviews the stub, finalizes `type` (if the auto-suggestion was wrong), confirms `address`, fleshes out `## Context`.
- Move file to `+ Atlas/Places/<Place Name>.md` (strip `needs-review, stub` tags).
- For **Bucket B candidates only**: open the matched Org note and add the new Place wikilink to its `## Places` section. The staging note's "Cross-link plan" Notes line is the reminder. This is the only way the facet relationship gets properly bi-directional.

This skill never performs promotion itself.

## Output

- Bucket counts and lists as described in step 11.
- List of paths touched (staged stubs in `+ Inbox/place-candidates/`).

## Notes

- **Read-only toward Gmail/Calendar/Fathom** — never mark anything read, archive, or send.
- **Idempotent** — re-running on the same window should produce no new writes if nothing changed (only append new evidence to existing stubs when new visits are seen).
- **Never auto-promote** from `+ Inbox/place-candidates/` to `+ Atlas/Places/`.
- **Never write a Place note for the user's home or a known-home address** — generalize the skip list by reading `+ Atlas/Places/*.md` and excluding any note with `type: home` whose `address:` matches the calendar location.
- **Cross-skill coordination:**
  - When `/orgs-sync` stages an Org candidate whose calendar location appears multiple times, this skill's next run picks up the implied Place. Skills do not duplicate detection logic — `/places-sync` reads `+ Atlas/Organizations/*.md` as the source of truth for which calendar-location strings are already orgs (the Bucket B path).
  - When `/log-place` is run manually, it should also auto-link any orgs whose `title` matches the place's name (handled by `/log-place` step 4).
- **Facet awareness is the key value-add of this skill.** A naïve implementation that just stages every calendar location would flood the inbox with stuff that's actually already represented as Orgs. The Bucket B handling is what makes the skill useful — it surfaces the missing Place *facet* on existing Orgs as a separate, higher-priority signal.
- **Type auto-suggestion is a hint, not a verdict** — user finalizes at promotion. The `## Related people` section is the same — link discovered attendees, but don't infer the *nature* of the relationship beyond "this person attended events here."
