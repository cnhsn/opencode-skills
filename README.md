# OpenCode Skills Installer

Bootstrap a fully-equipped [OpenCode](https://opencode.ai) coding environment with a curated set of community skills and automatic update tracking.

## Overview

OpenCode's skill system lets you load specialized instructions for different tasks — brainstorming, debugging, testing web apps, working with spreadsheets, and more. But finding, installing, and keeping these skills up to date across multiple repositories is tedious.

This installer automates that. It pulls skills from the best community sources, validates them, and gives you shell commands to check for updates daily.

## What's installed

### Skills (10 total)

| Skill | Source | Description |
|---|---|---|
| `karpathy-guidelines` | [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | Behavioral guidelines to reduce common LLM coding mistakes |
| `skill-creator` | [anthropics/skills](https://github.com/anthropics/skills) | Create, edit, and benchmark custom skills |
| `webapp-testing` | [anthropics/skills](https://github.com/anthropics/skills) | Test local web apps with Playwright |
| `frontend-design` | [anthropics/skills](https://github.com/anthropics/skills) | Distinctive, intentional visual design for UIs |
| `mcp-builder` | [anthropics/skills](https://github.com/anthropics/skills) | Build MCP servers in Python or TypeScript |
| `pdf` | [anthropics/skills](https://github.com/anthropics/skills) | Read, merge, split, rotate, OCR PDFs |
| `xlsx` | [anthropics/skills](https://github.com/anthropics/skills) | Create, edit, and clean spreadsheets |
| `code-review-and-quality` | [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | Multi-axis code review with security and performance checklists |
| `scikit-learn` | [K-Dense-AI/scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills) | ML pipelines, preprocessing, model evaluation |
| `statsmodels` | [K-Dense-AI/scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills) | Statistical models with diagnostics and inference |

### Superpowers plugin

The [Superpowers](https://github.com/obra/superpowers) plugin adds process-level skills:

- `brainstorming` — Explore intent and design before implementation
- `test-driven-development` — Write tests first, then code
- `systematic-debugging` — Structured debugging before proposing fixes
- `requesting-code-review` / `receiving-code-review` — Review workflows
- `writing-plans` / `executing-plans` — Plan-then-execute development
- `dispatching-parallel-agents` / `subagent-driven-development` — Parallel and multi-agent workflows
- `verification-before-completion` — Verify before claiming done
- `using-git-worktrees` — Isolated feature workspaces
- `finishing-a-development-branch` — Decide how to integrate completed work

## Prerequisites

- **git**
- **python3**
- **bash 4+**
- **[OpenCode](https://opencode.ai)** already installed

## Quick start

```bash
git clone git@github.com:cnhsn/opencode-skills.git
cd opencode-skills
./setup_opencode_bashrc.sh
source ~/.bashrc
opencode-skills-sync
```

## What the scripts do

### `install_opencode_skills.sh`

The main installer. Clones (or updates) the four skill source repositories, copies skills into `~/.config/opencode/skills/`, enables the Superpowers plugin, and validates everything. Safe to rerun — it updates existing repos and replaces managed skill copies.

### `setup_opencode_bashrc.sh`

Adds convenience commands and environment setup to your `~/.bashrc`. Also copies `install_opencode_skills.sh` to `~/.local/bin/opencode-skills-sync` so you can run it from anywhere.

## Post-install commands

| Command | What it does |
|---|---|
| `opencode-skills-sync` | Run the full installer again (update sources, reinstall skills) |
| `opencode-skills-check` | Check upstream repos for updates |
| `opencode-skills-verify` | Validate all installed skills are present and parse correctly |

Your interactive shells will also run a daily update check (at most once per 24 hours) and notify you if any skill sources have updates.

## Directory layout

```
~/.config/opencode/
  skills/                  # Installed skills (one subdirectory per skill)
  secrets.env              # Provider API keys (optional, mode 600)
  opencode.json            # OpenCode config (Superpowers plugin added here)
  skills-install-manifest.txt  # Record of what was installed and when

~/.local/share/opencode-skill-sources/
  andrej-karpathy-skills/  # Cloned source repos
  anthropic-skills/
  addy-agent-skills/
  scientific-agent-skills/

~/.local/bin/
  opencode-skills-sync     # Copy of installer for easy re-runs
```

## API keys

If your OpenCode provider needs API keys, add them to `~/.config/opencode/secrets.env` (created automatically, mode 600):

```bash
ANTHROPIC_API_KEY='sk-ant-...'
OPENAI_API_KEY='sk-...'
OPENROUTER_API_KEY='sk-or-...'
```

Prefer `opencode auth login` when your provider supports it.

## Uninstalling

1. Remove the skills directory: `rm -rf ~/.config/opencode/skills`
2. Remove source repos: `rm -rf ~/.local/share/opencode-skill-sources`
3. Remove the installer binary: `rm -f ~/.local/bin/opencode-skills-sync`
4. Remove the managed block from `~/.bashrc` — delete everything between `# >>> opencode skills helpers >>>` and `# <<< opencode skills helpers <<<`
5. Optionally remove the Superpowers plugin entry from `~/.config/opencode/opencode.json`

## License

MIT
