#!/usr/bin/env bash
# OpenBrain vault SessionStart hook.
# Pulls latest from origin/main (rebase) so the session starts current.
# Fails soft: network errors never block Gemini from starting.

set -uo pipefail

VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VAULT" || exit 0

log() { printf '[on-start] %s\n' "$*" >&2; }

# Only pull if the repo has a remote tracking branch
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git pull --rebase --autostash 2>&1 || log "pull failed (non-fatal)"
else
  log "no upstream configured, skipping pull"
fi

# Warm Google OAuth access tokens so MCP calls don't pay refresh latency mid-session,
# and surface any revoked refresh tokens up front. Silent on success; logs the tail
# of stderr on failure. Guarded on the venv so this is a no-op on machines that
# haven't run bootstrap/setup.sh yet.
if [[ -x "$VAULT/bootstrap/lib/refresh-google-tokens.sh" && -d "$HOME/.config/openbrain/venv" ]]; then
  refresh_out="$("$VAULT/bootstrap/lib/refresh-google-tokens.sh" 2>&1)" && refresh_rc=0 || refresh_rc=$?
  if printf '%s' "$refresh_out" | grep -q 'OPENBRAIN_AUTH_NUDGE_BEGIN'; then
    # Google auth settings changed — surface the friendly reconnect nudge
    # verbatim (regardless of probe exit code) so the operator is offered a
    # reconnect rather than hitting silent failures mid-session.
    log "Google auth settings changed — offer to reconnect (ask first, let the operator pick which accounts):"
    printf '%s\n' "$refresh_out" \
      | sed -n '/OPENBRAIN_AUTH_NUDGE_BEGIN/,/OPENBRAIN_AUTH_NUDGE_END/p' \
      | grep -vE 'OPENBRAIN_AUTH_NUDGE_(BEGIN|END)' >&2
  elif (( refresh_rc != 0 )); then
    log "google token refresh: $(printf '%s' "$refresh_out" | tail -3 | tr '\n' ' ')"
  fi
fi

exit 0
