# OpenBrain (Gemini CLI Edition)

**A personal AI Chief of Staff in an Obsidian vault, managed by Gemini CLI.**

OpenBrain is a portable template for a [Linking Your Thinking](https://www.linkingyourthinking.com/) (LYT) knowledge base that doubles as an operating layer for [Gemini CLI](https://geminicli.com/). Clone it, run one setup script, and you get:

- A fully scaffolded Obsidian vault (Inbox, Spaces, Atlas, Sources, Templates)
- 21 pre-built Chief of Staff [skills](#skills) with matching [slash commands](#commands)
- Multi-account MCP wiring for Gmail, Google Calendar, Google Meet, Google Drive/Docs/Sheets, Slack, Asana, and Fathom — any number of accounts per service
- A people data model with cadence tracking, interaction logging, and alias resolution

Built for people who want Gemini to act on their calendar, email, tasks, and notes the way a human chief of staff would — proactively, with context, and without constant re-briefing.

> This is the **Gemini CLI** edition of [OpenBrain](https://github.com/davidianstyle/openbrain-claude-starter). The original Claude Code edition lives at [openbrain-claude-starter](https://github.com/davidianstyle/openbrain-claude-starter).

---

## Prerequisites

- **macOS** (Linux should work; untested)
- **Obsidian** — [download](https://obsidian.md)

Everything else (git, Python, Node.js, Gemini CLI, GitHub CLI) is **auto-installed** by the setup wizard if missing. You don't need to install anything manually except Obsidian.

---

## Install

```bash
git clone https://github.com/davidianstyle/openbrain-gemini-starter.git ~/OpenBrain
cd ~/OpenBrain
./bootstrap/setup.sh
```

The wizard will:

1. Ask for your name and writing-voice blurb
2. Customize `GEMINI.md` with your details
3. Create `~/.config/openbrain/` and copy launcher scripts
4. Walk you through Google Cloud OAuth setup (one-time, 5 minutes)
5. Loop through each service and ask which accounts to add:
   - "Add a Google account?" → y → paste email → browser OAuth → done
   - "Add another?" → repeat for as many as you want
   - Same for Slack workspaces, Asana, Fathom
6. Register every MCP server in `~/.gemini/settings.json`
7. Link the pre-commit hook and validate the install

Start Gemini CLI in the vault directory and run `/daily-brief` as your first skill.

---

## Adding accounts later

The wizard is not a one-shot. You can add services any time:

```bash
./bootstrap/lib/add-google-account.sh jane@newdomain.com
./bootstrap/lib/add-slack-workspace.sh newteam           # → newteam.slack.com
./bootstrap/lib/add-asana.sh personal                    # or work
./bootstrap/lib/add-fathom.sh
./bootstrap/lib/register-mcps.sh                         # re-sync ~/.gemini/settings.json
```

Each script is idempotent — safe to re-run.

---

## What you get

### Vault layout

```
~/OpenBrain/
├── + Inbox/                  # capture first, triage later
├── + Spaces/                 # MOCs (Maps of Content)
│   └── People.md             # people MOC (created on demand)
├── + Atlas/                  # atomic notes — the actual knowledge
│   ├── Daily/                # daily notes
│   ├── Weekly Reviews/       # weekly synthesis
│   ├── People/               # person notes
│   ├── Interactions/         # meeting/call/thread notes
│   ├── Ideas/
│   ├── Decisions/
│   ├── Goals/
│   ├── Places/
│   ├── Organizations/
│   └── Quotes/
├── + Sources/                # literature / reference notes
├── + Extras/
│   └── Templates/            # 14 note templates
├── + Archive/                # cold storage
├── GEMINI.md                 # the operating manual Gemini reads every session
├── Home.md                   # front door with MOC index
├── .gemini/
│   ├── settings.json         # hooks + MCP server config
│   ├── skills/               # 21 Chief of Staff agent skills
│   └── commands/             # slash command wrappers (TOML)
└── .openbrain/               # git hooks + env template
```

### Skills

Gemini CLI auto-discovers skills in `.gemini/skills/` and activates them when a task matches. Each skill is a SKILL.md file with instructions Gemini follows.

| Skill | Purpose |
|---|---|
| `daily-brief` | Morning briefing across all your calendars, mail, Slack, tasks |
| `daily-review` | End-of-day reconciliation — check off tasks, push Asana updates |
| `process-inbox` | Triage `+ Inbox/` + Gmail + Slack; auto-push tagged tasks to Asana |
| `meeting-prep` | Assemble a briefing for a meeting or 1:1 |
| `capture-meeting` | Turn notes/transcript into an interaction note, update people |
| `capture-youtube` | Literature note from a YouTube video |
| `log-person` | Create a person note, seeded from Gmail/Slack |
| `log-note` | Quick-capture a thought as an atomic note |
| `log-interaction` | Manual touchpoint log |
| `log-idea` | Record an idea |
| `log-decision` | Record a decision with context and alternatives |
| `log-goal` | Create a goal with definition of done |
| `log-place` | Create a place note |
| `log-organization` | Create an organization note |
| `log-quote` | Save a quote |
| `follow-up-draft` | Draft a reply email/Slack message (never sends) |
| `what-am-i-missing` | Surface overdue tasks, cadence misses, unanswered mail |
| `people-audit` | Cadence health report + regenerate People MOC |
| `people-sync` | Discovery pass across Gmail/Calendar/Slack to find unknown people |
| `weekly-review` | Monday synthesis |
| `asana` | Quick view of upcoming Asana tasks with interactive check-off |

### Commands

Custom commands in `.gemini/commands/` provide explicit slash-command access to each skill:

```
/daily-brief          # run the daily briefing
/daily-brief 2026-04-20  # briefing for a specific date
/log-note My thought about X
/capture-meeting <paste notes>
/what-am-i-missing
```

### Supported MCP servers

One stdio MCP server per (service x account) pair, so routing is explicit:

- **Google** (`google-mcp`) — Gmail, Calendar, Meet, Drive, Docs, Sheets, Slides — one consolidated server per Google account
- **Slack** (`slack-mcp`) — one per workspace
- **Asana** (`asana-mcp`) — personal + work
- **Fathom** (`fathom-mcp`) — single instance

All launched via `~/.config/openbrain/lib/*-mcp.sh` wrappers that source `~/.config/openbrain/.env`.

---

## How it differs from the Claude Code edition

| Feature | Claude Code edition | Gemini CLI edition |
|---|---|---|
| Context file | `CLAUDE.md` | `GEMINI.md` |
| Config directory | `.claude/` | `.gemini/` |
| MCP registration | `~/.claude.json` | `~/.gemini/settings.json` |
| Git hooks | Pre-commit linter only | Pre-commit linter only |
| Slash commands | Built into skills (Claude auto-invokes) | `.gemini/commands/*.toml` wrappers |
| Skills format | `.claude/skills/<name>/SKILL.md` | `.gemini/skills/<name>/SKILL.md` (same format!) |
| MCP tool prefix | `mcp__server__tool` | `mcp_server_tool` |

The vault structure, templates, people model, and skill procedures are identical. You can run both editions side-by-side on the same vault if you have both CLIs installed — just add both `CLAUDE.md` and `GEMINI.md`, and both `.claude/` and `.gemini/` directories.

---

## Design principles

- **Capture first, organize later.** Everything starts in `+ Inbox/`.
- **Atomic notes.** One idea per note. If it wants to split, split it.
- **Links over folders.** Structure comes from `[[wikilinks]]` and MOCs.
- **Never delete, always archive.** Move to `+ Archive/`, never `rm`.
- **Git is the sync layer.** No Obsidian Sync. You control when to commit and push.
- **Skills are markdown procedures.** Gemini reads them and performs the steps.
- **People are first-class entities.** Every person gets a note. Interactions link back. Cadence is tracked.
- **Multi-account by default.** Every external service is wired per-account with routing tags.

---

## Troubleshooting

See [`bootstrap/README.md`](bootstrap/README.md) for:
- Re-running parts of the wizard
- Google OAuth gotchas (admin-managed Workspace accounts, "unverified app" screens)
- Slack workspace admin approval
- Rotating tokens
- Removing an account

---

## Credits

Developed by [@davidianstyle](https://github.com/davidianstyle) as the Gemini CLI adaptation of the [OpenBrain template](https://github.com/davidianstyle/openbrain-claude-starter).

The underlying LYT methodology is from [Nick Milo](https://www.linkingyourthinking.com/).
