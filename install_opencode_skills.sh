#!/usr/bin/env bash
# Install a curated set of global OpenCode skills on Linux and verify them.
# Safe to rerun: managed source repositories are updated and managed skill copies are replaced.
# Version: 2026.08.02.4

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

SUPERPOWERS_SPEC='superpowers@git+https://github.com/obra/superpowers.git'
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPENCODE_DIR="$CONFIG_HOME/opencode"
SKILLS_DIR="$OPENCODE_DIR/skills"
SOURCES_DIR="$DATA_HOME/opencode-skill-sources"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$OPENCODE_DIR/backups/skill-install-$STAMP"
MANAGED_MARKER='.managed-by-opencode-skill-installer'

COLOR=false
if [[ -t 1 ]]; then COLOR=true; fi

color() {
  local code="$1"; shift
  if $COLOR; then printf '\033[%sm%s\033[0m\n' "$code" "$*"; else printf '%s\n' "$*"; fi
}
info() { color '1;34' "[INFO] $*"; }
ok()   { color '1;32' "[ OK ] $*"; }
warn() { color '1;33' "[WARN] $*" >&2; }
die()  { color '1;31' "[FAIL] $*" >&2; exit 1; }

on_error() {
  local exit_code=$?
  color '1;31' "[FAIL] Command failed at line $1: $2" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

sync_repo() {
  local url="$1"
  local dest="$2"
  local branch="${3:-main}"

  if [[ -d "$dest/.git" ]]; then
    info "Updating $(basename "$dest")"
    git -C "$dest" remote set-url origin "$url"
    git -C "$dest" fetch --depth=1 origin "$branch"
    git -C "$dest" reset --hard FETCH_HEAD >/dev/null
    git -C "$dest" clean -fd >/dev/null
  elif [[ -e "$dest" ]]; then
    die "$dest exists but is not a Git repository. Move or remove it, then rerun."
  else
    info "Cloning $(basename "$dest")"
    git clone --depth=1 --branch "$branch" "$url" "$dest" >/dev/null
  fi
}

install_skill() {
  local source_dir="$1"
  local skill_name="$2"
  local dest="$SKILLS_DIR/$skill_name"

  [[ -f "$source_dir/SKILL.md" ]] || die "Missing SKILL.md for $skill_name at $source_dir"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -f "$dest/$MANAGED_MARKER" ]]; then
      rm -rf -- "$dest"
    else
      mkdir -p "$BACKUP_DIR"
      warn "Backing up existing unmanaged skill: $skill_name"
      mv -- "$dest" "$BACKUP_DIR/$skill_name"
    fi
  fi

  cp -a -- "$source_dir" "$dest"
  cat > "$dest/$MANAGED_MARKER" <<EOF
Installed by install_opencode_skills.sh
Installed at: $(date --iso-8601=seconds)
Source: $source_dir
EOF
  ok "Installed $skill_name"
}

fallback_add_superpowers_to_config() {
  local config_file
  if [[ -f "$OPENCODE_DIR/opencode.json" ]]; then
    config_file="$OPENCODE_DIR/opencode.json"
  elif [[ -f "$OPENCODE_DIR/opencode.jsonc" ]]; then
    config_file="$OPENCODE_DIR/opencode.jsonc"
  else
    config_file="$OPENCODE_DIR/opencode.json"
    printf '{\n  "$schema": "https://opencode.ai/config.json"\n}\n' > "$config_file"
  fi

  if [[ ! -f "$config_file.backup-$STAMP" ]]; then
    cp -a -- "$config_file" "$config_file.backup-$STAMP"
  fi
  warn "Using config fallback; backup is at $config_file.backup-$STAMP"

  python3 - "$config_file" "$SUPERPOWERS_SPEC" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = sys.argv[2]
source = path.read_text(encoding="utf-8")

# Strip JSONC comments without damaging comment-like text inside strings.
def strip_comments(text: str) -> str:
    out = []
    i = 0
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if ch in "\r\n":
                line_comment = False
                out.append(ch)
            i += 1
            continue
        if block_comment:
            if ch == "*" and nxt == "/":
                block_comment = False
                i += 2
            else:
                if ch in "\r\n":
                    out.append(ch)
                i += 1
            continue
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
        elif ch == "/" and nxt == "/":
            line_comment = True
            i += 2
        elif ch == "/" and nxt == "*":
            block_comment = True
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)

# Remove JSONC trailing commas outside strings.
def strip_trailing_commas(text: str) -> str:
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        ch = text[i]
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == ",":
            j = i + 1
            while j < len(text) and text[j].isspace():
                j += 1
            if j < len(text) and text[j] in "]}":
                i += 1
                continue
        out.append(ch)
        i += 1
    return "".join(out)

try:
    data = json.loads(strip_trailing_commas(strip_comments(source)))
except json.JSONDecodeError as exc:
    raise SystemExit(f"Cannot safely parse {path}: {exc}")

if not isinstance(data, dict):
    raise SystemExit(f"OpenCode config root must be an object: {path}")

plugins = data.get("plugin", [])
if isinstance(plugins, str):
    plugins = [plugins]
elif plugins is None:
    plugins = []
elif not isinstance(plugins, list) or not all(isinstance(item, str) for item in plugins):
    raise SystemExit("The OpenCode 'plugin' setting must be a string array")

if spec not in plugins:
    plugins.append(spec)
data["plugin"] = plugins
data.setdefault("$schema", "https://opencode.ai/config.json")

path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

  ok "Configured Superpowers in $config_file"
}

install_superpowers() {
  info "Installing/configuring Superpowers"

  local existing_config
  for existing_config in "$OPENCODE_DIR/opencode.json" "$OPENCODE_DIR/opencode.jsonc"; do
    if [[ -f "$existing_config" ]]; then
      cp -a -- "$existing_config" "$existing_config.backup-$STAMP"
      ok "Backed up OpenCode config: $existing_config.backup-$STAMP"
    fi
  done

  if command -v opencode >/dev/null 2>&1 && opencode plugin --help >/dev/null 2>&1; then
    if opencode plugin "$SUPERPOWERS_SPEC" --global; then
      ok "Superpowers plugin installed through OpenCode"
      return
    fi
    warn "OpenCode's plugin command failed; trying the config fallback"
  else
    warn "Current OpenCode has no usable 'plugin' command; using config fallback"
  fi

  fallback_add_superpowers_to_config
}

write_manifest() {
  local manifest="$OPENCODE_DIR/skills-install-manifest.txt"
  {
    echo "Installed: $(date --iso-8601=seconds)"
    echo "Skills directory: $SKILLS_DIR"
    echo
    echo "Sources:"
    for repo in \
      "$SOURCES_DIR/andrej-karpathy-skills" \
      "$SOURCES_DIR/anthropic-skills" \
      "$SOURCES_DIR/addy-agent-skills" \
      "$SOURCES_DIR/scientific-agent-skills" \
      "$SOURCES_DIR/humanize"
    do
      printf '%s  %s\n' "$(git -C "$repo" rev-parse HEAD)" "$repo"
    done
    echo
    echo "Expected skills:"
    printf '%s\n' "${EXPECTED_SKILLS[@]}"
    echo
    echo "Plugin: $SUPERPOWERS_SPEC"
  } > "$manifest"
  ok "Wrote installation manifest: $manifest"
}

validate_filesystem_skills() {
  info "Validating installed SKILL.md files"
  python3 - "$SKILLS_DIR" "${EXPECTED_SKILLS[@]}" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = sys.argv[2:]
errors = []

for expected_name in expected:
    path = root / expected_name / "SKILL.md"
    if not path.is_file():
        errors.append(f"{expected_name}: missing {path}")
        continue

    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"^---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not match:
        errors.append(f"{expected_name}: missing valid YAML frontmatter")
        continue

    frontmatter = match.group(1)
    name_match = re.search(r"(?m)^name:\s*['\"]?([^'\"\n]+?)['\"]?\s*$", frontmatter)
    desc_match = re.search(r"(?m)^description:\s*(.+?)\s*$", frontmatter)

    if not name_match:
        errors.append(f"{expected_name}: frontmatter has no name")
    else:
        actual_name = name_match.group(1).strip()
        if actual_name != expected_name:
            errors.append(
                f"{expected_name}: frontmatter name is {actual_name!r}; OpenCode requires an exact directory match"
            )
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", actual_name):
            errors.append(f"{expected_name}: invalid OpenCode skill name {actual_name!r}")

    if not desc_match or not desc_match.group(1).strip():
        errors.append(f"{expected_name}: frontmatter has no description")

if errors:
    print("Skill validation failed:")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print(f"Validated {len(expected)} skills:")
for name in expected:
    print(f"  - {name}")
PY
  ok "Filesystem skill validation passed"
}

validate_opencode() {
  info "Validating OpenCode integration"

  if ! command -v opencode >/dev/null 2>&1; then
    warn "OpenCode executable was not found in PATH. Files are installed, but live OpenCode validation was skipped."
    return 0
  fi

  opencode --version

  local config_output
  config_output="$(mktemp)"
  if opencode debug config >"$config_output" 2>&1; then
    if grep -Fq "$SUPERPOWERS_SPEC" "$config_output"; then
      ok "OpenCode resolved the Superpowers plugin in its effective config"
    else
      cat "$config_output" >&2
      rm -f "$config_output"
      die "OpenCode parsed its config, but the Superpowers plugin was not present"
    fi
  else
    cat "$config_output" >&2
    rm -f "$config_output"
    die "OpenCode could not parse/load its effective config"
  fi
  rm -f "$config_output"

  # This debug subcommand exists in many recent OpenCode builds but is not
  # guaranteed across every version, so it is an optional stronger check.
  local skill_output
  skill_output="$(mktemp)"
  if opencode debug skill >"$skill_output" 2>&1; then
    local missing=0
    local skill
    for skill in "${EXPECTED_SKILLS[@]}"; do
      if ! grep -Fq "$skill" "$skill_output"; then
        warn "OpenCode debug output did not list: $skill"
        missing=1
      fi
    done
    if [[ "$missing" -eq 0 ]]; then
      ok "OpenCode discovered all installed filesystem skills"
    else
      warn "Filesystem validation passed, but OpenCode's optional discovery check was incomplete. Restart OpenCode and list skills from the skill tool."
    fi

    if grep -Fq 'superpowers/brainstorming' "$skill_output"; then
      ok "OpenCode discovered Superpowers skills"
    else
      warn "The optional skill-discovery output did not show superpowers/brainstorming. Restart OpenCode and ask: Tell me about your superpowers."
    fi
  else
    warn "Your OpenCode build does not expose 'opencode debug skill'; skipped the optional discovery check."
  fi
  rm -f "$skill_output"
}

main() {
  require_command git
  require_command python3

  mkdir -p "$OPENCODE_DIR" "$SKILLS_DIR" "$SOURCES_DIR"

  local KARPATHY_REPO="$SOURCES_DIR/andrej-karpathy-skills"
  local ANTHROPIC_REPO="$SOURCES_DIR/anthropic-skills"
  local ADDY_REPO="$SOURCES_DIR/addy-agent-skills"
  local KDENSE_REPO="$SOURCES_DIR/scientific-agent-skills"
  local HUMANIZE_REPO="$SOURCES_DIR/humanize"

  local -a EXPECTED_SKILLS=(
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
    humanize
    ai-check
  )

  sync_repo 'https://github.com/multica-ai/andrej-karpathy-skills.git' "$KARPATHY_REPO"
  sync_repo 'https://github.com/anthropics/skills.git' "$ANTHROPIC_REPO"
  sync_repo 'https://github.com/addyosmani/agent-skills.git' "$ADDY_REPO"
  sync_repo 'https://github.com/K-Dense-AI/scientific-agent-skills.git' "$KDENSE_REPO"
  sync_repo 'https://github.com/harshaneel/humanize.git' "$HUMANIZE_REPO"

  install_skill "$KARPATHY_REPO/skills/karpathy-guidelines" karpathy-guidelines

  install_skill "$ANTHROPIC_REPO/skills/skill-creator" skill-creator
  install_skill "$ANTHROPIC_REPO/skills/webapp-testing" webapp-testing
  install_skill "$ANTHROPIC_REPO/skills/frontend-design" frontend-design
  install_skill "$ANTHROPIC_REPO/skills/mcp-builder" mcp-builder
  install_skill "$ANTHROPIC_REPO/skills/pdf" pdf
  install_skill "$ANTHROPIC_REPO/skills/xlsx" xlsx

  install_skill "$ADDY_REPO/skills/code-review-and-quality" code-review-and-quality
  mkdir -p "$SKILLS_DIR/code-review-and-quality/references"
  for reference in security-checklist.md performance-checklist.md; do
    if [[ -f "$ADDY_REPO/references/$reference" ]]; then
      cp -a -- "$ADDY_REPO/references/$reference" \
        "$SKILLS_DIR/code-review-and-quality/references/$reference"
    else
      warn "Optional code-review reference not found: $reference"
    fi
  done

  install_skill "$KDENSE_REPO/skills/scikit-learn" scikit-learn
  install_skill "$KDENSE_REPO/skills/statsmodels" statsmodels

  install_skill "$HUMANIZE_REPO/humanize" humanize
  install_skill "$HUMANIZE_REPO/ai-check" ai-check

  install_superpowers
  write_manifest
  validate_filesystem_skills
  validate_opencode

  echo
  ok "Installation and verification completed"
  echo "Skills:  $SKILLS_DIR"
  echo "Sources: $SOURCES_DIR"
  if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backups: $BACKUP_DIR"
  fi
  echo
  echo "Restart OpenCode, then ask:"
  echo "  Use the skill tool to list all available skills."
  echo "  Tell me about your superpowers."
}

main "$@"
