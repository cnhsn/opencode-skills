#!/usr/bin/env bash
# Configure Bash helpers for the curated OpenCode skills installer.
# Run from the directory containing install_opencode_skills.sh, or pass its path as argument 1.

set -Eeuo pipefail
IFS=$'\n\t'

INSTALLER_SOURCE="${1:-./install_opencode_skills.sh}"
BASHRC="${HOME}/.bashrc"
LOCAL_BIN="${HOME}/.local/bin"
INSTALLER_DEST="${LOCAL_BIN}/opencode-skills-sync"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
OPENCODE_DIR="${CONFIG_HOME}/opencode"
ENV_FILE="${OPENCODE_DIR}/secrets.env"
BEGIN_MARKER='# >>> opencode skills helpers >>>'
END_MARKER='# <<< opencode skills helpers <<<'

if [[ ! -f "$INSTALLER_SOURCE" ]]; then
  printf 'Installer not found: %s\n' "$INSTALLER_SOURCE" >&2
  printf 'Run this from the directory containing install_opencode_skills.sh,\n' >&2
  printf 'or pass its full path as the first argument.\n' >&2
  exit 1
fi

command -v git >/dev/null 2>&1 || {
  printf 'Missing required command: git\n' >&2
  exit 1
}

mkdir -p "$LOCAL_BIN" "$OPENCODE_DIR"
install -m 0755 "$INSTALLER_SOURCE" "$INSTALLER_DEST"

if [[ ! -e "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<'ENV'
# Optional provider credentials for OpenCode.
# Add only variables required by the provider you use.
# Prefer `opencode auth login` when your provider supports it.
#
# Examples:
# ANTHROPIC_API_KEY='replace-me'
# OPENAI_API_KEY='replace-me'
# OPENROUTER_API_KEY='replace-me'
ENV
fi
chmod 600 "$ENV_FILE"

touch "$BASHRC"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

# Remove an older copy of our managed block, preserving all other Bash configuration.
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  $0 == begin { skipping = 1; next }
  $0 == end   { skipping = 0; next }
  !skipping   { print }
' "$BASHRC" > "$TMP_FILE"
cat "$TMP_FILE" > "$BASHRC"

cat >> "$BASHRC" <<'BASHRC_BLOCK'

# >>> opencode skills helpers >>>
# Managed by setup_opencode_bashrc.sh. Safe to regenerate.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export OPENCODE_USER_CONFIG_DIR="$XDG_CONFIG_HOME/opencode"
export OPENCODE_SKILLS_DIR="$OPENCODE_USER_CONFIG_DIR/skills"
export OPENCODE_SKILL_SOURCES_DIR="$XDG_DATA_HOME/opencode-skill-sources"
export OPENCODE_ENV_FILE="$OPENCODE_USER_CONFIG_DIR/secrets.env"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Load optional provider API keys without requiring `export` on every line.
if [[ -r "$OPENCODE_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$OPENCODE_ENV_FILE"
  set +a
fi

opencode-skills-check() {
  local quiet=0
  [[ "${1:-}" == "--quiet" ]] && quiet=1

  if ! command -v git >/dev/null 2>&1; then
    printf '[ERROR] git is not available.\n' >&2
    return 1
  fi

  local -a repositories=(
    andrej-karpathy-skills
    anthropic-skills
    addy-agent-skills
    scientific-agent-skills
  )

  local repository path branch local_sha remote_sha
  local updates=0 missing=0 errors=0

  for repository in "${repositories[@]}"; do
    path="$OPENCODE_SKILL_SOURCES_DIR/$repository"

    if [[ ! -d "$path/.git" ]]; then
      printf '[MISSING] %s\n' "$repository"
      missing=$((missing + 1))
      continue
    fi

    branch="$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "$branch" ]] || branch="main"
    local_sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    remote_sha="$(git -C "$path" ls-remote origin "refs/heads/$branch" 2>/dev/null | awk 'NR == 1 { print $1 }')"

    if [[ -z "$local_sha" || -z "$remote_sha" ]]; then
      printf '[ERROR] Unable to check %s\n' "$repository" >&2
      errors=$((errors + 1))
    elif [[ "$local_sha" != "$remote_sha" ]]; then
      printf '[UPDATE] %s\n' "$repository"
      updates=$((updates + 1))
    elif (( quiet == 0 )); then
      printf '[CURRENT] %s\n' "$repository"
    fi
  done

  # Superpowers is managed by OpenCode's git-backed plugin mechanism.
  if command -v opencode >/dev/null 2>&1; then
    if opencode debug config 2>/dev/null \
      | grep -Fq 'superpowers@git+https://github.com/obra/superpowers.git'; then
      (( quiet == 0 )) && printf '[CONFIGURED] superpowers plugin\n'
    else
      printf '[MISSING] superpowers plugin configuration\n'
      missing=$((missing + 1))
    fi
  elif (( quiet == 0 )); then
    printf '[SKIPPED] OpenCode executable not found; Superpowers config not checked.\n'
  fi

  if (( updates > 0 || missing > 0 )); then
    printf 'Run: opencode-skills-update\n'
  elif (( errors == 0 && quiet == 0 )); then
    printf 'All checked skill sources are current.\n'
  fi

  (( errors == 0 ))
}

opencode-skills-update() {
  if ! command -v opencode-skills-sync >/dev/null 2>&1; then
    printf '[ERROR] ~/.local/bin/opencode-skills-sync is missing.\n' >&2
    return 1
  fi

  command opencode-skills-sync "$@"
}

opencode-skills-verify() {
  local -a expected=(
    karpathy-guidelines
    skill-creator
    webapp-testing
    frontend-design
    mcp-builder
    pdf
    xlsx
    code-review-and-quality
    scikit-learn
    statsmodels
  )

  local skill missing=0
  for skill in "${expected[@]}"; do
    if [[ -f "$OPENCODE_SKILLS_DIR/$skill/SKILL.md" ]]; then
      printf '[OK] %s\n' "$skill"
    else
      printf '[MISSING] %s\n' "$skill"
      missing=$((missing + 1))
    fi
  done

  if command -v opencode >/dev/null 2>&1; then
    printf '\nOpenCode version:\n'
    opencode --version

    if opencode debug config >/dev/null 2>&1; then
      printf '[OK] OpenCode configuration parses correctly.\n'
    else
      printf '[ERROR] OpenCode configuration validation failed.\n' >&2
      missing=$((missing + 1))
    fi

    if opencode debug skill >/dev/null 2>&1; then
      printf '[OK] OpenCode skill discovery command succeeded.\n'
    else
      printf '[INFO] This OpenCode build does not expose `opencode debug skill`.\n'
    fi
  else
    printf '[INFO] OpenCode executable is not currently in PATH.\n'
  fi

  (( missing == 0 ))
}

# Check upstream repositories at most once every 24 hours in interactive shells.
# It prints only when an update, missing source, or error is found.
_opencode_skills_daily_check() {
  [[ $- == *i* ]] || return 0

  local state_dir="$XDG_CACHE_HOME/opencode"
  local stamp="$state_dir/skills-update-check.timestamp"
  local now last=0

  mkdir -p "$state_dir"
  now="$(date +%s)"
  [[ -r "$stamp" ]] && read -r last < "$stamp" || true
  [[ "$last" =~ ^[0-9]+$ ]] || last=0

  if (( now - last >= 86400 )); then
    printf '%s\n' "$now" > "$stamp"
    opencode-skills-check --quiet || true
  fi
}

_opencode_skills_daily_check
unset -f _opencode_skills_daily_check
# <<< opencode skills helpers <<<
BASHRC_BLOCK

printf 'Installed updater: %s\n' "$INSTALLER_DEST"
printf 'Updated Bash config: %s\n' "$BASHRC"
printf 'Created secrets file: %s (mode 600)\n' "$ENV_FILE"
printf '\nLoad it now with:\n  source ~/.bashrc\n'
printf '\nAvailable commands:\n'
printf '  opencode-skills-check\n'
printf '  opencode-skills-update\n'
printf '  opencode-skills-verify\n'
