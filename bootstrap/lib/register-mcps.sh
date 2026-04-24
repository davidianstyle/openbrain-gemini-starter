#!/usr/bin/env bash
# Register every configured MCP server with Gemini CLI.
#
# Reads ~/.config/openbrain/.env and ~/.config/openbrain/tokens/ to discover
# which Google slugs, Slack workspaces, Asana workspaces, and Fathom keys are
# configured, then ensures ~/.gemini/settings.json has matching mcpServers entries.
#
# Writes launcher scripts to ~/.config/openbrain/lib/ as a side effect so the
# MCP entries point at stable per-machine paths (not the vault repo path).
#
# Idempotent: re-running updates existing entries in place and removes stale
# openbrain-managed entries no longer in the current config.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$HERE/common.sh"

ensure_python3
load_env

GEMINI_SETTINGS="$HOME/.gemini/settings.json"
mkdir -p "$HOME/.gemini"
if [[ ! -f "$GEMINI_SETTINGS" ]]; then
  echo '{}' > "$GEMINI_SETTINGS"
fi

# -----------------------------------------------------------------------------
# 1. Install launcher scripts to ~/.config/openbrain/lib/
# -----------------------------------------------------------------------------
mkdir -p "$LIB_DIR"
chmod 755 "$LIB_DIR"
for f in "$REPO_ROOT/.openbrain/lib/"*.sh; do
  dest="$LIB_DIR/$(basename "$f")"
  if ! cmp -s "$f" "$dest" 2>/dev/null; then
    cp "$f" "$dest"
    chmod 755 "$dest"
  fi
done
ok "launcher scripts installed at $LIB_DIR"

# -----------------------------------------------------------------------------
# 2. Discover configured accounts and write to a JSON plan file
# -----------------------------------------------------------------------------
PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT

GOOGLE_SLUGS_JSON='[]'
if compgen -G "$TOKEN_DIR/google-*-credentials.json" > /dev/null; then
  GOOGLE_SLUGS_JSON="$(
    for f in "$TOKEN_DIR"/google-*-credentials.json; do
      base="${f##*/}"; slug="${base#google-}"; slug="${slug%-credentials.json}"
      printf '%s\n' "$slug"
    done | "$PYTHON_BIN" -c 'import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
  )"
fi

SLACK_SLUGS_JSON='[]'
if grep -qE '^SLACK_TOKEN_[A-Z0-9_]+=.+' "$ENV_FILE"; then
  SLACK_SLUGS_JSON="$(
    grep -E '^SLACK_TOKEN_[A-Z0-9_]+=.+' "$ENV_FILE" \
      | sed -E 's/^SLACK_TOKEN_([A-Z0-9_]+)=.*/\1/' \
      | "$PYTHON_BIN" -c '
import sys, json
slugs = []
for line in sys.stdin:
    upper = line.strip()
    if not upper:
        continue
    slugs.append(upper.lower().replace("_", "-"))
print(json.dumps(slugs))
'
  )"
fi

HAS_ASANA_PERSONAL=false; [[ -n "${ASANA_PAT_PERSONAL:-}" ]] && HAS_ASANA_PERSONAL=true
HAS_ASANA_WORK=false;     [[ -n "${ASANA_PAT_WORK:-}" ]]     && HAS_ASANA_WORK=true
HAS_FATHOM=false;         [[ -n "${FATHOM_API_KEY:-}" ]]     && HAS_FATHOM=true

cat >"$PLAN" <<EOF
{
  "lib_dir": "$LIB_DIR",
  "google_slugs": $GOOGLE_SLUGS_JSON,
  "slack_slugs": $SLACK_SLUGS_JSON,
  "has_asana_personal": $HAS_ASANA_PERSONAL,
  "has_asana_work": $HAS_ASANA_WORK,
  "has_fathom": $HAS_FATHOM
}
EOF

step "Discovered MCP config"
"$PYTHON_BIN" - "$PLAN" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
print(f"  Google accounts: {len(plan['google_slugs'])}")
for s in plan['google_slugs']: print(f"    • {s}")
print(f"  Slack workspaces: {len(plan['slack_slugs'])}")
for s in plan['slack_slugs']: print(f"    • {s}")
print(f"  Asana personal: {plan['has_asana_personal']}")
print(f"  Asana work:     {plan['has_asana_work']}")
print(f"  Fathom:         {plan['has_fathom']}")
PY

# -----------------------------------------------------------------------------
# 3. Merge plan into ~/.gemini/settings.json
# -----------------------------------------------------------------------------
"$PYTHON_BIN" - "$GEMINI_SETTINGS" "$PLAN" <<'PY'
import json, shutil, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
plan = json.load(open(sys.argv[2]))
lib_dir = plan["lib_dir"]

# Backup
backup = settings_path.with_suffix(".json.openbrain-backup")
shutil.copy2(settings_path, backup)

data = json.loads(settings_path.read_text())
servers = data.setdefault("mcpServers", {})

def stdio(name, script, *args, include_tools=None):
    """Register a stdio MCP server in Gemini CLI format."""
    entry = {
        "command": f"{lib_dir}/{script}",
        "args": list(args),
    }
    if include_tools:
        entry["includeTools"] = include_tools
    servers[name] = entry

# --- Tool allowlists (Gemini API limit: 512 function declarations) ---
# Only expose tools the Chief of Staff skills actually use.

GOOGLE_TOOLS = [
    # Calendar
    "calendar_list_events", "calendar_search_events", "calendar_get_event",
    "calendar_create_event", "calendar_get_current_time", "calendar_list_calendars",
    # Gmail
    "gmail_search_emails", "gmail_read_email", "gmail_draft_email",
    # Meet
    "meet_list_meetings",
    # Drive (read-only for research)
    "drive_search_files", "drive_list_files",
    # Docs (read-only)
    "docs_read_document", "docs_get_info",
]

SLACK_TOOLS = [
    "slack_conversations_history", "slack_conversations_replies",
    "slack_conversations_add_message", "slack_conversations_search_messages",
    "slack_conversations_unreads", "slack_conversations_open",
    "slack_users_search", "slack_channels_list",
    "slack_schedule_message",
]

ASANA_TOOLS = [
    "asana_get_my_tasks", "asana_search_tasks", "asana_get_task",
    "asana_update_task", "asana_create_task", "asana_create_task_story",
    "asana_get_subtasks", "asana_get_tags_for_task",
    "asana_get_project", "asana_get_tasks_for_project",
]

# Fathom has few tools — no filtering needed.

# Remove any openbrain-managed entries before re-writing
managed_prefixes = ("asana-", "google-", "slack-")
for k in list(servers.keys()):
    v = servers[k]
    cmd = v.get("command", "") if isinstance(v, dict) else ""
    if k == "fathom" or any(k.startswith(p) for p in managed_prefixes):
        if "openbrain" in cmd:
            del servers[k]

if plan["has_asana_personal"]:
    stdio("asana-personal", "asana-mcp.sh", "personal", include_tools=ASANA_TOOLS)
if plan["has_asana_work"]:
    stdio("asana-work", "asana-mcp.sh", "work", include_tools=ASANA_TOOLS)

# Gemini CLI namespaces tools as mcp_<serverName>_<toolName>
# Use dashes in server names (avoid underscores to prevent tool name collisions)
for slug in plan["google_slugs"]:
    stdio(f"google-{slug}", "google-mcp.sh", slug, include_tools=GOOGLE_TOOLS)

for slug in plan["slack_slugs"]:
    stdio(f"slack-{slug}", "slack-mcp.sh", slug, include_tools=SLACK_TOOLS)

if plan["has_fathom"]:
    stdio("fathom", "fathom-mcp.sh")

settings_path.write_text(json.dumps(data, indent=2))

print(f"[register-mcps] backup: {backup}")
print(f"[register-mcps] wrote {len(servers)} total MCP servers to {settings_path}")
for name in sorted(servers.keys()):
    print(f"  • {name}")
PY

step "Done registering MCPs"
info "Restart Gemini CLI so it picks up the new mcpServers entries"
info "Verify with: gemini (then /tools to list available tools)"
