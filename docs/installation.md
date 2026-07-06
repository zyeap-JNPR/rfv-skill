# Installation

GitHub Copilot (both the **CLI** and the **VS Code** extension) discovers agent
skills in an `.agents/skills/` directory:

| Scope | Directory | Applies to |
|-------|-----------|-----------|
| **Per-project** | `<your-repo>/.agents/skills/` | only that repository |
| **Global (all projects)** | `~/.agents/skills/` | every project on your machine |

---

## Method A — `skills` CLI (recommended)

Installs the skill and tracks the source repo so you can pull updates later.

```bash
# Global install (all projects)
npx skills add zyeap-JNPR/rfv-skill -g -s review-fix-verify -y

# …or per-project (run from inside the target repo)
npx skills add zyeap-JNPR/rfv-skill -p -s review-fix-verify -y

# See what's installed
npx skills list

# Pull the latest version later
npx skills update review-fix-verify
```

> The `skills` CLI writes a lock file (`.skill-lock.json`) recording the source
> repo and a content hash, which is what powers `npx skills update`.

---

## Method B — Git clone + symlink (for development)

Keep a single git working copy and symlink it into the agent skills directory,
so local edits are live and `git pull` updates the skill instantly.

```bash
# 1. Clone the canonical copy somewhere you keep repos
git clone https://github.com/zyeap-JNPR/rfv-skill.git ~/work/github/rfv-skill

# 2. Symlink the skill into your global agent skills dir
mkdir -p ~/.agents/skills
ln -s ~/work/github/rfv-skill/skills/review-fix-verify \
      ~/.agents/skills/review-fix-verify

# Update anytime:
git -C ~/work/github/rfv-skill pull
```

For a **per-project** symlink instead, replace the target with
`<your-repo>/.agents/skills/review-fix-verify`.

---

## VS Code notes

The VS Code Copilot extension reads the same `.agents/skills/` locations as the
CLI. After installing, reload the VS Code window so the extension re-scans skills.
Trigger the skill in Copilot Chat with `/review-fix-verify` or a phrase like
"review and fix".

## Copilot CLI notes

No extra step — the CLI auto-discovers skills in `.agents/skills/` on startup.
Verify with:

```bash
ls ~/.agents/skills/review-fix-verify   # files present (or a valid symlink)
```

Then invoke inside a git repo with `/review-fix-verify [path|range]`,
`review and fix`, or `rfv`.

---

## Uninstall

```bash
# Method A
npx skills remove review-fix-verify

# Method B
rm ~/.agents/skills/review-fix-verify        # removes the symlink only
```

---

## Compatibility

| Requirement | Notes |
|-------------|-------|
| Shell | `bash` ≥ 4.0 (uses arrays, process substitution) |
| Git | ≥ 2.0 |
| `jq` | Optional but recommended for `package.json` detection |
| OS | macOS, Linux. Windows: use WSL2 or Git Bash |
| GNU vs BSD tools | `awk`, `grep`, `sed` use only POSIX-compatible flags |

The skill (SKILL.md) requires a Copilot CLI or VS Code Copilot extension that supports
the `task` tool with `model` overrides and `agent_type: code-review`.
