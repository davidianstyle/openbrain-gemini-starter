#!/usr/bin/env bash
# OpenBrain (Gemini CLI edition) setup wizard — run this ONCE after `git clone`.
#
# What it does:
#   1. Checks prereqs (python3, node, git)
#   2. Asks for your name and writing-voice blurb
#   3. Substitutes those into GEMINI.md and generates Home.md
#   4. Copies .openbrain/lib/*.sh → ~/.config/openbrain/lib/ (install-time paths)
#   5. Creates ~/.config/openbrain/.env from .openbrain/env.example
#   6. Loops through each supported service and asks "add an account? [y/N]"
#   7. Runs register-mcps.sh to wire ~/.gemini/settings.json
#   8. Runs validate.sh to sanity-check the install
#
# Re-runnable: the script is defensive. Re-running won't clobber existing
# secrets — you'll get prompts only for missing or explicitly re-entered values.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

banner() {
  printf '\n%s%s════════════════════════════════════════════════════════════%s\n' "$_C_BOLD" "$_C_BLUE" "$_C_RESET"
  printf '%s%s  %s%s\n' "$_C_BOLD" "$_C_BLUE" "$*" "$_C_RESET"
  printf '%s%s════════════════════════════════════════════════════════════%s\n\n' "$_C_BOLD" "$_C_BLUE" "$_C_RESET"
}

banner "OpenBrain (Gemini CLI) — personal AI Chief of Staff setup"

cat <<EOF
This wizard will:
  • Customize GEMINI.md with your name + writing voice
  • Create ~/.config/openbrain/ and install launcher scripts
  • Walk you through OAuth for every service you want to wire up
  • Register MCP servers with Gemini CLI

It assumes this repo is already cloned to the directory you want to use as
your vault. Current repo path: $_C_BOLD$REPO_ROOT$_C_RESET

EOF

if ! yes_no "Continue?" y; then
  exit 0
fi

# -----------------------------------------------------------------------------
# Step 1: prereqs (auto-installs missing dependencies)
# -----------------------------------------------------------------------------
step "1/8 · Checking & installing prerequisites"
ensure_git
ok "git: $(command -v git)"
ensure_python3
ok "python3: $PYTHON_BIN"
ensure_node
ok "node: $(command -v node) ($(node --version))"
ensure_gemini_cli
ok "gemini: $(command -v gemini)"
ensure_gh
ok "gh: $(command -v gh)"

# If asdf is active, ensure .tool-versions exists so node/python resolve in this dir
if command -v asdf >/dev/null 2>&1 && [[ ! -f "$REPO_ROOT/.tool-versions" ]]; then
  NODE_VER="$(node --version 2>/dev/null | sed 's/^v//')"
  if [[ -n "$NODE_VER" ]]; then
    echo "nodejs $NODE_VER" > "$REPO_ROOT/.tool-versions"
    ok "created .tool-versions (nodejs $NODE_VER) for asdf compatibility"
  fi
fi

# -----------------------------------------------------------------------------
# Step 2: user profile
# -----------------------------------------------------------------------------
step "2/8 · Tell me about yourself"

USER_NAME="$(prompt 'Your full name' "${USER:-}")"
USER_VOICE="$(prompt 'Describe your writing voice in a sentence' 'direct, terse, no filler')"

# -----------------------------------------------------------------------------
# Step 3: customize GEMINI.md
# -----------------------------------------------------------------------------
step "3/8 · Customizing GEMINI.md"

BOOTSTRAP_DATE="$(date +%Y-%m-%d)"
GEMINI_MD="$REPO_ROOT/GEMINI.md"

"$PYTHON_BIN" - "$GEMINI_MD" "$USER_NAME" "$USER_VOICE" "$BOOTSTRAP_DATE" <<'PY'
import sys
path, name, voice, date = sys.argv[1:]
content = open(path).read()
content = (content
    .replace("{{USER_NAME}}", name)
    .replace("{{USER_VOICE}}", voice)
    .replace("{{BOOTSTRAP_DATE}}", date)
    # Placeholder blocks get cleared to a "none configured" stub; the tables
    # get populated fully by a later pass (after accounts are added).
    .replace("{{ASANA_ROUTING_TABLE}}",  "_No Asana workspaces configured yet. Run `./bootstrap/lib/add-asana.sh personal|work` to add one._")
    .replace("{{GOOGLE_ACCOUNTS_TABLE}}", "_No Google accounts configured yet. Run `./bootstrap/lib/add-google-account.sh <email>` to add one._")
    .replace("{{SLACK_WORKSPACES_TABLE}}", "_No Slack workspaces configured yet. Run `./bootstrap/lib/add-slack-workspace.sh <subdomain>` to add one._")
    .replace("{{FATHOM_TABLE}}", "_Fathom not configured. Run `./bootstrap/lib/add-fathom.sh` to add it._")
)
open(path, "w").write(content)
PY
ok "GEMINI.md customized"

# Generate Home.md if missing
if [[ ! -f "$REPO_ROOT/Home.md" ]]; then
  cat >"$REPO_ROOT/Home.md" <<EOF
---
title: Home
tags: [moc]
created: $BOOTSTRAP_DATE
---

# ${USER_NAME}'s OpenBrain

The front door. Edit the MOC index below as you add new Maps of Content.

## Top MOCs

<!-- openbrain:moc-index:start -->
<!-- openbrain:moc-index:end -->

## Quick access

- [[+ Inbox]] — capture first, triage later
- [[+ Atlas/Daily]] — daily notes
- [[+ Sources]] — literature / references
- [[+ Extras/Templates]] — note templates

## How this vault works

- **Capture first, organize later.** Everything starts in \`+ Inbox/\`.
- **Atomic notes.** One idea per note.
- **Links over folders.** Structure comes from \`[[wikilinks]]\` and MOCs.
- See [[GEMINI]] for the full operating manual.
EOF
  ok "Home.md created"
fi

# -----------------------------------------------------------------------------
# Step 4: install config dir + env
# -----------------------------------------------------------------------------
step "4/8 · Installing ~/.config/openbrain/"
ensure_env_file
mkdir -p "$TOKEN_DIR" "$LIB_DIR"
chmod 700 "$CONFIG_DIR" "$TOKEN_DIR"
chmod 755 "$LIB_DIR"
chmod 600 "$ENV_FILE"
ok "config dir: $CONFIG_DIR"

# Copy launchers
for f in "$REPO_ROOT/.openbrain/lib/"*.sh; do
  dest="$LIB_DIR/$(basename "$f")"
  cp "$f" "$dest"
  chmod 755 "$dest"
done
ok "launcher scripts installed"

# -----------------------------------------------------------------------------
# Step 5: wire up services
# -----------------------------------------------------------------------------
step "5/8 · Wiring up services"

# Google — optional but recommended
if yes_no "Wire up Google accounts (Gmail + Calendar + Meet + Drive)?" y; then
  "$HERE/lib/setup-google-oauth.sh"
  while true; do
    email="$(prompt 'Google account email to add (blank to finish)')"
    [[ -z "$email" ]] && break
    "$HERE/lib/add-google-account.sh" "$email" || warn "failed to add $email — continuing"
  done
fi

# Slack
if yes_no "Wire up Slack workspaces?" n; then
  while true; do
    sub="$(prompt 'Slack workspace subdomain (e.g. acme → acme.slack.com, blank to finish)')"
    [[ -z "$sub" ]] && break
    "$HERE/lib/add-slack-workspace.sh" "$sub" || warn "failed to add $sub — continuing"
  done
fi

# Asana
if yes_no "Wire up Asana (personal)?" n; then
  "$HERE/lib/add-asana.sh" personal || warn "failed to add personal Asana"
fi
if yes_no "Wire up Asana (work)?" n; then
  "$HERE/lib/add-asana.sh" work || warn "failed to add work Asana"
fi

# Fathom
if yes_no "Wire up Fathom?" n; then
  "$HERE/lib/add-fathom.sh" || warn "failed to add Fathom"
fi

# -----------------------------------------------------------------------------
# Step 6: register MCPs in ~/.gemini/settings.json
# -----------------------------------------------------------------------------
step "6/8 · Registering MCPs with Gemini CLI"
"$HERE/lib/register-mcps.sh"

# -----------------------------------------------------------------------------
# Step 7: git hook
# -----------------------------------------------------------------------------
step "7/8 · Git hook"
if [[ -d "$REPO_ROOT/.git" ]]; then
  HOOK="$REPO_ROOT/.git/hooks/pre-commit"
  if [[ ! -e "$HOOK" ]] || ! cmp -s "$REPO_ROOT/.openbrain/pre-commit.sh" "$HOOK"; then
    ln -sf "$REPO_ROOT/.openbrain/pre-commit.sh" "$HOOK"
    chmod +x "$REPO_ROOT/.openbrain/pre-commit.sh"
    ok "pre-commit hook linked"
  else
    ok "pre-commit hook already linked"
  fi
else
  warn "not a git repo — skipping pre-commit hook. Run 'git init' then re-run this script."
fi

# -----------------------------------------------------------------------------
# Step 8: validate
# -----------------------------------------------------------------------------
step "8/8 · Validating install"
"$HERE/lib/validate.sh" || true

# -----------------------------------------------------------------------------
# Final: next steps
# -----------------------------------------------------------------------------
banner "Setup complete"
cat <<EOF
Next steps:

  1. ${_C_BOLD}Start Gemini CLI${_C_RESET} in this vault directory:
       ${_C_CYAN}cd $REPO_ROOT && gemini${_C_RESET}

  2. Inside a fresh Gemini CLI session, try:
       ${_C_CYAN}/tools${_C_RESET}               # verify MCP tools are discovered
       ${_C_CYAN}/daily-brief${_C_RESET}       # smoke-test your first skill

  3. Open the vault in Obsidian:
       ${_C_CYAN}open -a Obsidian $REPO_ROOT${_C_RESET}

     Then install these recommended community plugins:
       • Templater (set folder to + Extras/Templates/)
       • Local Images Plus
           - realTimeUpdate: true
           - processCreated: true
           - attachment pattern: .resources/\${notename}/

  4. Add more accounts any time with:
       ${_C_CYAN}./bootstrap/lib/add-google-account.sh jane@newdomain.com${_C_RESET}
       ${_C_CYAN}./bootstrap/lib/add-slack-workspace.sh newteam${_C_RESET}
       ${_C_CYAN}./bootstrap/lib/add-asana.sh personal${_C_RESET}

  5. (Optional) Push this vault to a private git remote for cross-device sync:
       ${_C_CYAN}gh repo create my-vault --private --source=. --push${_C_RESET}

See README.md and bootstrap/README.md for troubleshooting.
EOF
