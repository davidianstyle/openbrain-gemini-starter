---
name: log-organization
description: Create a new organization note at + Atlas/Organizations/<name>.md from the Organization template.
---

# /log-organization

## Inputs

- `$1`: organization name. Becomes the filename and note title.
- `$2` (optional): type — `company | church | nonprofit | group | other`.

## Procedure

1. **Check for existing note.** If `+ Atlas/Organizations/<name>.md` already exists, stop and tell the user — offer to open it instead.
2. **Scaffold from template.** Copy `+ Extras/Templates/Organization.md` to `+ Atlas/Organizations/<name>.md`. Set `title:`, `created:` to today, and `type:` if provided.
3. **Collect details interactively.** Prompt the user for:
   - Type (if not provided)
   - URL (optional)
   - Context (what this org is, your relationship to it)
   - Key people (search `+ Atlas/People/` for matches)
   - Places (search `+ Atlas/Places/` for matches)
   Skip sections they leave blank.
4. **Web fallback for missing `url:` and HQ address.** If the user left `url:` blank, do a bounded internet lookup:
   - One `WebSearch` for `"<org name>" official site` (add a geographic hint if the name is ambiguous — e.g. `"Acme Group" <city>`).
   - Pick the top result that's clearly the org's own domain (not a directory listing). Populate `url:` and append `<!-- url sourced from web lookup, verify -->` inline.
   - While there, scan the homepage / footer / contact page (one `WebFetch`) for an HQ street address. If unambiguous, capture it in `## Context` as `_HQ: <address> (from <URL>, verify)._`. Don't put a non-vault address in frontmatter — orgs don't have an `address:` field (Places do).
   - **Hard cap: 1 WebSearch + 1 WebFetch.** If multiple candidate sites disagree, leave `url:` blank and list the candidates inline for the user.
5. **Link people and places.** Add `[[wikilinks]]` for confirmed matches.
6. **Report.** Show the path and populated content.

## Output

- Path to new organization note
- Linked people and places
