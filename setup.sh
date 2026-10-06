#!/bin/sh
# Install or update the qsbn skills in the current project, using EITHER the Claude Code plugin
# OR plain files copied into the repo (never both). Project scope only. Safe to re-run: installs
# when missing, updates when present.
#
# Usage:
#   ./setup.sh [--plugin | --files] [--yes]
#   curl -fsSL https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.sh | sh -s -- --plugin
#
# --files clones the toolkit to a temp folder, then copies skills/ to .agents/skills/ (linked into
# .claude/skills/) and commands/qsbn/ to .claude/commands/qsbn/. Commit those folders to share them.
# Run it from inside the project's git repo. POSIX sh, so it also works when piped to `sh`.
set -eu

MARKETPLACE_REPO="justinnguyenqsbn/qsbn-ai-toolkit-plugin"
MARKETPLACE_NAME="qsbn-ai-toolkit-plugin"
PLUGIN="qsbn@qsbn-ai-toolkit-plugin"
REPO_URL="https://github.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin"

METHOD="${QSBN_METHOD:-}"
YES=0
for arg in "$@"; do
  case "$arg" in
    --plugin) METHOD=plugin ;;
    --files|--skills) METHOD=files ;;
    -y|--yes) YES=1 ;;
    -h|--help) sed -n '2,12p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
[ "$METHOD" = skills ] && METHOD=files

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# True only if /dev/tty can really be opened (it can exist yet fail, e.g. in CI).
has_tty() { (: </dev/tty) 2>/dev/null; }

# Prompts read from the terminal, not stdin, so they work under `curl ... | sh`.
ask() {
  # ask "<question>" -> returns 0 for yes. Default is no.
  [ "$YES" = 1 ] && return 0
  has_tty || die "No terminal available to prompt. Re-run with --yes to confirm automatically."
  printf '%s [y/N] ' "$1" >/dev/tty
  read -r answer </dev/tty || answer=""
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- Project root: everything is installed at project scope -------------------------------
have git || die "git not found."
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "Not inside a git repository. cd into your project first."
cd "$root"
echo "Project: $root"

# --- Pick a method ------------------------------------------------------------------------
if [ -z "$METHOD" ]; then
  has_tty || die "No terminal to prompt. Pass --plugin or --files."
  {
    echo
    echo "How do you want to install the qsbn skills? Pick ONE - do not use both."
    echo "  1) Claude Code plugin  (recommended for Claude Code users)"
    echo "  2) Files in this repo  (skills + /qsbn:* commands copied in, shareable through git)"
    printf 'Choice [1/2]: '
  } >/dev/tty
  read -r choice </dev/tty || choice=""
  case "$choice" in 1) METHOD=plugin ;; 2) METHOD=files ;; *) die "Invalid choice." ;; esac
fi
case "$METHOD" in plugin|files) ;; *) die "Invalid method '$METHOD' (use plugin or files)." ;; esac

# --- Helpers ------------------------------------------------------------------------------
# Scopes (user/project/local) the qsbn plugin is installed at for THIS project, one per line.
# A project-scope install belonging to another project (projectPath differs) is ignored.
plugin_scopes() {
  have claude || return 0
  here=$(pwd -W 2>/dev/null || pwd)
  claude plugin list --json 2>/dev/null | awk -v id="$PLUGIN" -v here="$here" '
    function norm(s) { gsub(/[\\]+/, "/", s); return tolower(s) }
    /^[[:space:]]*\{/ { eid = ""; scope = ""; path = "" }
    /"id":/ { eid = $0; sub(/.*"id": *"/, "", eid); sub(/".*/, "", eid) }
    /"scope":/ { scope = $0; sub(/.*"scope": *"/, "", scope); sub(/".*/, "", scope) }
    /"projectPath":/ { path = $0; sub(/.*"projectPath": *"/, "", path); sub(/".*/, "", path) }
    /^[[:space:]]*\}/ { if (eid == id && (scope != "project" || path == "" || norm(path) == norm(here))) print scope }
  '
}

# Paths of a previous files install (also catches skills left behind by skills.sh), one per line.
files_installed() {
  for p in .agents/skills/qsbn-* .claude/skills/qsbn-* .claude/commands/qsbn; do
    if [ -e "$p" ] || [ -L "$p" ]; then echo "$p"; fi
  done
}

# rm -rf on a link removes the link itself, never what it points at.
remove_files() {
  existing=$(files_installed)
  [ -n "$existing" ] || return 0
  echo "Removing previously installed qsbn files:"
  echo "$existing"
  # .claude first so links go before their targets.
  for p in .claude/skills/qsbn-* .claude/commands/qsbn .agents/skills/qsbn-*; do
    if [ -e "$p" ] || [ -L "$p" ]; then rm -rf "$p"; fi
  done
}

# --- Plugin -------------------------------------------------------------------------------
if [ "$METHOD" = plugin ]; then
  have claude || die "claude CLI not found. Install Claude Code first."

  existing=$(files_installed)
  if [ -n "$existing" ]; then
    echo
    echo "WARNING: qsbn files are already installed in this project:"
    echo "$existing"
    echo "Do NOT use both the plugin and the files: every qsbn skill and command would be installed twice."
    ask "Remove the installed files now?" || die "Aborted. Delete those paths first."
    remove_files
  fi

  scopes=$(plugin_scopes)
  # Project scope only: drop copies at other scopes.
  for scope in $scopes; do
    if [ "$scope" != project ]; then
      echo
      echo "WARNING: the plugin is installed at '$scope' scope. This setup is project-only."
      ask "Uninstall the $scope-scope copy?" || die "Aborted. Run: claude plugin uninstall $PLUGIN -s $scope"
      claude plugin uninstall "$PLUGIN" -s "$scope"
    fi
  done

  claude plugin marketplace add "$MARKETPLACE_REPO" --scope project || echo "Marketplace already added, continuing."
  if printf '%s\n' "$scopes" | grep -qx project; then
    echo "Plugin already installed in this project - updating."
    claude plugin marketplace update "$MARKETPLACE_NAME"
    claude plugin update "$PLUGIN" -s project
  else
    claude plugin install "$PLUGIN" -s project
  fi
  echo "Done. Restart Claude Code (or run /reload-plugins) to load the skills."
  exit 0
fi

# --- Files --------------------------------------------------------------------------------
if [ -n "$(plugin_scopes)" ]; then
  echo
  echo "WARNING: the qsbn Claude Code plugin ($PLUGIN) is installed."
  echo "Do NOT use both the plugin and the files: every qsbn skill and command would be installed twice."
  ask "Remove the plugin now?" || die "Aborted. Remove it first with: claude plugin uninstall $PLUGIN"
  for scope in $(plugin_scopes); do
    claude plugin uninstall "$PLUGIN" -s "$scope"
  done
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Cloning $REPO_URL ..."
git clone --depth 1 -q "$REPO_URL" "$tmp/repo" || die "Could not clone $REPO_URL. Check your GitHub access to it."
src="$tmp/repo"
[ -d "$src/skills" ] || die "The cloned repo has no skills/ folder."

# Remove first so skills deleted upstream disappear and new ones are picked up.
remove_files
mkdir -p .agents/skills .claude/skills .claude/commands/qsbn

count=0
for dir in "$src"/skills/*/; do
  dir=${dir%/}
  [ -f "$dir/SKILL.md" ] || continue
  name=${dir##*/}
  case "$name" in qsbn-*) ;; *) echo "Skipping '$name' (name must start with qsbn-)."; continue ;; esac
  cp -R "$dir" ".agents/skills/$name"
  # Relative link so the repo stays portable. Where links are unavailable (e.g. Git Bash without
  # symlink support) `ln` makes a copy or fails: fall back to a plain copy.
  ln -s "../../.agents/skills/$name" ".claude/skills/$name" 2>/dev/null || true
  if [ ! -L ".claude/skills/$name" ]; then
    rm -rf ".claude/skills/$name"
    cp -R "$dir" ".claude/skills/$name"
  fi
  count=$((count + 1))
done
[ "$count" -gt 0 ] || die "No skills found in the cloned repo."

if [ -d "$src/commands/qsbn" ]; then
  cp "$src"/commands/qsbn/*.md .claude/commands/qsbn/
fi

echo "Installed $count skills into .agents/skills (linked from .claude/skills) and the /qsbn:* commands into .claude/commands/qsbn."
echo "Done. Restart your agent session so they are picked up. Commit .agents/ and .claude/ to share them with your team."
