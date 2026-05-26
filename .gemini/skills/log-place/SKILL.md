---
name: log-place
description: Create a new place note at + Atlas/Places/<name>.md from the Place template. Auto-seeds address + cross-links from recent calendar activity unless run in quick mode.
---

# /log-place

## Inputs

- `$1`: place name. Becomes the filename and note title.
- `$2` (optional): type — `church | office | restaurant | venue | home | other`.
- `$3` (optional): `quick` to skip the cross-account context seed, `deep` (default) to search calendar locations and email signatures for prior mentions.

## Procedure

1. **Check for existing note.** If `+ Atlas/Places/<name>.md` already exists, stop and tell the user — offer to open it instead.

2. **Scaffold from template.** Copy `+ Extras/Templates/Place.md` to `+ Atlas/Places/<name>.md`. Set `title:` and `created:` to today, plus `type:` if provided.

3. **Context seed (unless `quick`).** Fan out across every `google_*` MCP in a single tool-use block — independent calendar searches, never serialized.
   - For each `google_*` MCP, `google_calendar_list_events` over the last 90 days. Post-filter to events whose `location` field contains the place name (substring match, case-insensitive).
   - For each `google_*` MCP, `google_gmail_search_emails` with the place name as a quoted query, capped at 5 hits. Used to surface mentions that imply an address from email signatures or invitations.
   - From the matched events, extract:
     - The full `location` string from any matching event → populate `address:` (parse out the postal portion after the first comma with a state code, per the same heuristic `/sync-places` uses)
     - All non-user attendees → candidate links for `## Related people`
     - Event creators/organizers' email domains → candidate links for `## Related organizations` (cross-reference against `+ Atlas/Organizations/*.md` by domain)

4. **Web fallback for `address:` (only if step 3 left it blank).** If the context seed produced no unambiguous calendar address (or `quick` mode was used and there's no other signal), do an internet lookup:
   - Issue a `WebSearch` for `"<place name>" address` plus any geographic disambiguator the user provided in `$1` (e.g. `"Acme Cafe" Newton MA address`). If `$1` already contains a city/state, include it; otherwise, derive a disambiguator from the most-frequently-occurring metro in the user's calendar history (the user's home region by default — read `+ Atlas/Places/*.md` for any `type: home` notes and use that city/state).
   - Pick the top result that's clearly the official business listing (Google Maps, Yelp, the business's own site). If the top results disagree on address or there are multiple matching locations, **stop and leave `address:` blank** — flag the candidates inline in `## Notes` for the user to disambiguate. Chain businesses without a city hint must not auto-populate.
   - If one result is unambiguous, populate `address:` from it and append `<!-- address sourced from web lookup, verify -->` inline so the user knows to confirm. Cite the source URL in `## Notes`: `_Address from web lookup: <URL>._`
   - Cap at one `WebSearch` + at most two `WebFetch` calls — don't crawl. If still uncertain, leave blank.

5. **Type inference** (if not provided in `$2`, best-effort from the place name):
   - Contains `Church`, `Chapel`, `Cathedral` → `church`
   - Contains `Restaurant`, `Cafe`, `Café`, `Coffee`, `Kitchen`, `Bistro`, `Bar`, `Grill`, `Diner` → `restaurant`
   - Contains `Workbar`, `WeWork`, `Coworking`, `Office`, `HQ`, `Studio` → `office`
   - Contains `Stadium`, `Arena`, `Theater`, `Center`, `Hall`, `Park`, `Gym`, `Dance Center`, `Gymnastics` → `venue`
   - Contains `Elementary`, `Middle School`, `High School`, `Academy`, `University`, `College` → `other`
   - Otherwise → `other` (leave as default; user can override)

6. **Link people and orgs.** Use the candidate lists from step 3:
   - For each non-user attendee, match against `+ Atlas/People/*.md` `emails:` array. If matched, add `- [[Person Name]] (attended <N> events here)` under `## Related people`. Do not stage new person candidates from this skill — that's `/sync-people`'s job.
   - For each organizer domain, match against `+ Atlas/Organizations/*.md` (by `url:` or domain inferred from `title`). If matched, add `- [[Org Name]]` under `## Related organizations`. If no match, just note the domain inline so the user can decide whether to run `/sync-organizations` or `/log-organization`.

7. **Facet cross-link suggestion.** If the place name matches an existing Org by title (per the "Places and Orgs are facets" convention — a single real-world entity can be both a Place and an Org), add a Notes line:
   `_This place is the physical facet of [[<Org>]]. Open [[<Org>]] and add [[<this Place>]] to its ## Places section to complete the bi-directional link._`

8. **Report.** Show the populated frontmatter and the inferred context; ask the user to confirm or correct before saving.

## Output

- Path to new place note
- Populated frontmatter (title, type, address, created, tags)
- Linked people and organizations (count only, with the full list inlined into the note)
- Facet cross-link suggestion if applicable

## Notes

- **Only populate `address:` from unambiguous matches.** Applies to both calendar matches (step 3) and web lookups (step 4): if the place name appears in multiple distinct calendar locations OR the web search returns conflicting addresses, flag it and leave `address:` blank for the user to disambiguate. Chain businesses (Starbucks, etc.) require a city/state hint before web lookup proceeds.
- **Web-lookup addresses always carry the `<!-- address sourced from web lookup, verify -->` comment** so the user sees they were not derived from their own calendar/email and may need verification.
- **Do not stage new person candidates from this skill.** If a non-vault person attended an event at this place, leave them out of `## Related people`. `/sync-people` will surface them on its next run if they meet the Bucket C threshold elsewhere.
- **Do not stage new org candidates either.** Same reason — `/sync-organizations` owns that pass.
- **`type: home`** is the one type that should never be auto-inferred from the place name alone — homes don't have predictable name patterns. If the user passes `home` as `$2`, accept it; otherwise leave as `other` and let them correct.
- Per GEMINI.md, attached `~/.config/openbrain/.env` and shell escape rules apply when launching the MCP commands (no special handling required here).
