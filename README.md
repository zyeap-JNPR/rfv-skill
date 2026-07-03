# rfv-skill

A portable [agent skill](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
that runs a multi-model **review → fix → verify → iterate** workflow for code changes.

- **Fan-out review** — 2 parallel reviewers on different fast models (3 with `--thorough`), high-signal findings only.
- **Consolidate** — orchestrator dedupes and renders an ACCEPT/REJECT verdict table.
- **Fix** — one builder subagent applies accepted fixes and runs the repo's own test suite until green (bounded).
- **Verify** — a reviewer on a _different_ model than the builder reviews only the fix diff, hunting regressions.
- **Iterate** — bounded loop back to Fix if the verifier finds real issues.

The pre-flight script (`rfv-prep.sh`) auto-detects the test command across many
ecosystems: Node, Make, Go, Rust, Python, Java (Maven/Gradle), .NET, Swift, Ruby,
PHP, and Elixir. Full skill docs live in
[`skills/review-fix-verify/README.md`](skills/review-fix-verify/README.md).

---

## Repository layout

```
rfv-skill/
└── skills/
    └── review-fix-verify/
        ├── SKILL.md        # skill definition (frontmatter + procedure)
        ├── README.md       # detailed skill docs
        └── rfv-prep.sh     # pre-flight diff + test-command detector
```

---

## Installation

GitHub Copilot (both the **CLI** and the **VS Code** extension) discovers agent
skills in an `.agents/skills/` directory:

| Scope | Directory | Applies to |
|-------|-----------|-----------|
| **Per-project** | `<your-repo>/.agents/skills/` | only that repository |
| **Global (all projects)** | `~/.agents/skills/` | every project on your machine |

Pick **one** install method below. Method A is easiest for consumers; Method B
is best if you want to hack on the skill yourself.

### Method A — `skills` CLI (managed, recommended)

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

### Method B — Git clone + symlink (for development)

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

### VS Code Copilot notes

The VS Code Copilot extension reads the same `.agents/skills/` locations as the
CLI, so either method above enables the skill in VS Code too. After installing,
reload the VS Code window so the extension re-scans skills. Trigger the skill in
Copilot Chat with `/review-fix-verify` or a phrase like "review and fix".

### Copilot CLI notes

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

## Contributing / updating the skill

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide. Quick summary:

1. Edit files under `skills/review-fix-verify/` in your clone.
2. Run the test suite: `bats tests/rfv-prep.bats` (requires [bats-core](https://github.com/bats-core/bats-core)).
3. Run shellcheck: `shellcheck -S warning skills/review-fix-verify/rfv-prep.sh`
4. Commit and push. Consumers pick up changes via `npx skills update` (Method A)
   or `git pull` (Method B).

---

## Testing

The shell script has a behavioral test suite using [bats-core](https://github.com/bats-core/bats-core).

```bash
# Install bats-core
brew install bats-core          # macOS
sudo apt-get install bats       # Debian/Ubuntu

# Run all tests (from repo root)
bats tests/rfv-prep.bats

# Syntax check only
bash -n skills/review-fix-verify/rfv-prep.sh

# Shellcheck (static analysis)
shellcheck -S warning skills/review-fix-verify/rfv-prep.sh
```

CI runs all three checks on every push and PR via GitHub Actions.

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

---

## Security

- **No secrets in this repo.** `rfv-prep.sh` reads only your git history and project
  files to detect test commands. It does not read `.env` files or credential stores.
- **Diffs may contain sensitive data.** When you run this skill, your diff is inlined
  into subagent prompts and processed by external AI models. Avoid running it on diffs
  that contain secrets, credentials, PII, or employer-confidential data.
- **No network access.** `rfv-prep.sh` makes no network requests.
- Found a security issue? See [SECURITY.md](SECURITY.md).

---

## Versioning

This repo uses [Semantic Versioning](https://semver.org/):

- **Patch** (x.y.**Z**) — bug fixes to `rfv-prep.sh`, doc corrections, test additions.
- **Minor** (x.**Y**.0) — new ecosystem support, new structured output markers, additive SKILL.md changes.
- **Major** (**X**.0.0) — breaking changes to SKILL.md phases, `rfv-prep.sh` exit codes, or structured output format.

`npx skills update` pulls the latest commit from `main`. Pin to a tag if you need
stability: `git checkout v1.2.3` in your Method B clone.

---

## License

[MIT](LICENSE) © Zach Yeap
