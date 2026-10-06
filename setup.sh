#!/bin/sh
# Install or update the qsbn skills in the current project, using EITHER the Claude Code plugin
# OR skills.sh (never both). Project scope only. Safe to re-run: installs when missing, updates
# when present.
#
# Usage:
#   ./setup.sh [--plugin | --skills] [--yes]
#   curl -fsSL https://raw.githubusercontent.com/justinnguyenqsbn/qsbn-ai-toolkit-plugin-setup/main/setup.sh | sh -s -- --plugin
#
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
    --skills) METHOD=skills ;;
    -y|--yes) YES=1 ;;
    -h|--help) sed -n '2,10p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

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
  has_tty || die "No terminal to prompt. Pass --plugin or --skills."
  {
    echo
    echo "How do you want to install the qsbn skills? Pick ONE - do not use both."
    echo "  1) Claude Code plugin  (recommended for Claude Code users)"
    echo "  2) skills.sh           (for other agents, or to copy skills into the repo)"
    printf 'Choice [1/2]: '
  } >/dev/tty
  read -r choice </dev/tty || choice=""
  case "$choice" in 1) METHOD=plugin ;; 2) METHOD=skills ;; *) die "Invalid choice." ;; esac
fi
case "$METHOD" in plugin|skills) ;; *) die "Invalid method '$METHOD' (use plugin or skills)." ;; esac

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

# Names of qsbn-* skills installed in this project by skills.sh.
skills_installed() {
  have npx || return 0
  # The skills are internal, so list/remove only see them with INSTALL_INTERNAL_SKILLS=1.
  # Keep only the skill-name column (lines starting with qsbn-), after stripping colour codes.
  esc=$(printf '\033')
  INSTALL_INTERNAL_SKILLS=1 npx -y skills@latest list 2>/dev/null | sed "s/$esc\[[0-9;]*m//g" | awk '/^qsbn-/ { print $1 }' | sort -u || true
}

remove_skills() {
  names=$(skills_installed)
  [ -n "$names" ] || return 0
  echo "Removing installed qsbn skills:"
  echo "$names"
  # shellcheck disable=SC2086
  # npx can crash on exit on Windows (libuv assertion) after a successful run, so judge by the
  # result, not the exit code.
  INSTALL_INTERNAL_SKILLS=1 npx -y skills@latest remove $names -y || true
  [ -z "$(skills_installed)" ] || die "Removing the installed skills failed."
}

# --- Plugin -------------------------------------------------------------------------------
if [ "$METHOD" = plugin ]; then
  have claude || die "claude CLI not found. Install Claude Code first."

  existing=$(skills_installed)
  if [ -n "$existing" ]; then
    echo
    echo "WARNING: qsbn skills are already installed through skills.sh in this project:"
    echo "$existing"
    echo "Do NOT use both the plugin and skills.sh: every qsbn skill would be installed twice."
    ask "Remove the skills.sh skills now?" || die "Aborted. Remove them first with: npx skills remove <names>"
    remove_skills
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

# --- skills.sh ----------------------------------------------------------------------------
have npx || die "npx not found. Install Node.js first."

if [ -n "$(plugin_scopes)" ]; then
  echo
  echo "WARNING: the qsbn Claude Code plugin ($PLUGIN) is installed."
  echo "Do NOT use both the plugin and skills.sh: every qsbn skill would be installed twice."
  ask "Remove the plugin now?" || die "Aborted. Remove it first with: claude plugin uninstall $PLUGIN"
  for scope in $(plugin_scopes); do
    claude plugin uninstall "$PLUGIN" -s "$scope"
  done
fi

# Remove first so skills deleted upstream disappear and new ones are picked up.
remove_skills
# Project scope is the default: never pass -g.
INSTALL_INTERNAL_SKILLS=1 npx -y skills@latest add "$REPO_URL" || true
[ -n "$(skills_installed)" ] || die "skills.sh install failed."
echo "Done. Restart your agent session so the skills are picked up."
