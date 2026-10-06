# qsbn-ai-toolkit-plugin-setup

Public install/update scripts for the qsbn skills in
[`qsbn-ai-toolkit-plugin`](https://github.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin) (private).
The skills live in the private repo; these scripts only fetch and place them, so you need GitHub
access to that repo (signed in with `git`/`gh`) for the install to succeed.

One script per shell. Each one installs when the skills are missing and updates when they are
present, in the **current project only** (run it from inside the project's git repo).

## Prerequisites

- `git`, signed in to GitHub with access to `justinnguyenqsbn/qsbn-ai-toolkit-plugin`
- Claude Code (`claude` CLI) for the plugin method. The files method needs only `git`.

## Install or update

Pick ONE method. Never use both: every qsbn skill and command would be installed twice. If the
other method is already installed, the script offers to remove it first.

macOS / Linux / Git Bash:

```sh
curl -fsSL https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.sh | sh -s -- --plugin
```

Windows PowerShell:

```powershell
$env:QSBN_METHOD='plugin'; irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1 | iex
```

Replace `plugin` with `files` to copy everything into the repo instead. Without a method the
script asks. Re-run the same command later to update.

| Option | `setup.sh` | `setup.ps1` |
|---|---|---|
| Claude Code plugin | `--plugin` | `-Method plugin` or `QSBN_METHOD=plugin` |
| Files in the repo | `--files` (alias `--skills`) | `-Method files` or `QSBN_METHOD=files` |
| Auto-confirm removal prompts (CI) | `--yes` | `-Yes` |

With a downloaded copy, pass a parameter the usual way, for example
`& ([scriptblock]::Create((irm <url>))) -Method plugin -Yes`.

> GitHub's raw CDN caches for up to 5 minutes, so a fresh push may take that long to reach `irm`/`curl`.

## What the scripts do

**Plugin**: `claude plugin marketplace add` + `claude plugin install qsbn@qsbn-ai-toolkit-plugin -s project`
(or `marketplace update` + `plugin update` when already installed). A copy at user/local scope is
removed after a prompt, since this setup is project-only. Commit `.claude/settings.json` so
teammates are prompted to install it.

**Files**: shallow-clones the toolkit to a temp folder (deleted afterwards), then

- copies each `skills/qsbn-*` to `.agents/skills/` and links it into `.claude/skills/`
  (relative symlink on macOS/Linux, junction on Windows, plain copy if linking is not possible),
- copies `commands/qsbn/*.md` to `.claude/commands/qsbn/`, so `/qsbn:*` works in Claude Code,
- copies `agents/*.md` to `.claude/agents/` (the subagents some skills spawn).

On update it first removes every `qsbn-*` skill and agent and the `qsbn` commands folder, so skills deleted
upstream disappear. Anything not named `qsbn-*` is left alone. The installer never touches git:
commit `.agents/` and `.claude/` yourself to share the skills with your team (on Windows, git
stores a junction's contents as regular files, so teammates get real copies).
