# qsbn-ai-toolkit-plugin-setup

Public install/update scripts for the qsbn skills in
[`qsbn-ai-toolkit-plugin`](https://github.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin) (private).
The skills live in the private repo; these scripts only run the installers, so you need GitHub access
to that repo (signed in with `git`/`gh`) for the install to succeed.

One script per shell. Each one installs when the skills are missing and updates when they are
present, in the **current project only** (run it from inside the project's git repo).

## Prerequisites

- `git`, signed in to GitHub with access to `justinnguyenqsbn/qsbn-ai-toolkit-plugin`
- Claude Code (`claude` CLI) for the plugin method, or Node.js (`npx`) for the skills.sh method

## Install or update

Pick ONE method. Never use both: every qsbn skill would be installed twice. If the other method is
already installed, the script offers to remove it first.

macOS / Linux / Git Bash:

```sh
curl -fsSL https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.sh | sh -s -- --plugin
```

Windows PowerShell:

```powershell
$env:QSBN_METHOD='plugin'; irm https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.ps1 | iex
```

Replace `plugin` with `skills` to install through skills.sh instead. Without a method the script
asks. Re-run the same command later to update.

| Option | `setup.sh` | `setup.ps1` |
|---|---|---|
| Claude Code plugin | `--plugin` | `-Method plugin` or `QSBN_METHOD=plugin` |
| skills.sh | `--skills` | `-Method skills` or `QSBN_METHOD=skills` |
| Auto-confirm removal prompts (CI) | `--yes` | `-Yes` |

With a downloaded copy, pass a parameter the usual way, for example
`& ([scriptblock]::Create((irm <url>))) -Method plugin -Yes`.

## What the scripts do

- Plugin: `claude plugin marketplace add` + `claude plugin install qsbn@qsbn-ai-toolkit-plugin -s project`
  (or `marketplace update` + `plugin update` when already installed). A copy at user/local scope is
  removed after a prompt, since this setup is project-only.
- skills.sh: removes every installed `qsbn-*` skill, then `npx skills add` the repo, so skills
  deleted upstream disappear and new ones appear. Skills are internal, so the script sets
  `INSTALL_INTERNAL_SKILLS=1` for each `skills` call.
