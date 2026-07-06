# rfv-skill

A portable [agent skill](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
that runs a multi-model **review → fix → verify → iterate** workflow for code changes.

- **Fan-out review** — 2 parallel reviewers on different fast models (3 with `--thorough`), high-signal findings only.
- **Consolidate** — orchestrator dedupes and renders an ACCEPT/REJECT verdict table.
- **Fix** — builder subagent applies accepted fixes and runs the repo's own test suite until green (bounded).
- **Verify** — reviewer on a _different_ model than the builder checks only the fix diff for regressions.
- **Iterate** — bounded loop back to Fix if the verifier finds real issues.

`rfv-prep.sh` auto-detects the test command across Node, Make, Go, Rust, Python,
Java (Maven/Gradle), .NET, Swift, Ruby, PHP, and Elixir.

Full skill docs: [`skills/review-fix-verify/README.md`](skills/review-fix-verify/README.md)

---

## Repository layout

```
rfv-skill/
├── docs/
│   ├── installation.md   # install, uninstall, compatibility
│   └── development.md    # testing, contributing, versioning
└── skills/
    └── review-fix-verify/
        ├── SKILL.md        # skill definition (frontmatter + procedure)
        ├── README.md       # detailed skill docs
        └── rfv-prep.sh     # pre-flight diff + test-command detector
```

---

## Quick install

```bash
# Global (all projects)
npx skills add zyeap-JNPR/rfv-skill -g -s review-fix-verify -y

# Per-project (run from inside target repo)
npx skills add zyeap-JNPR/rfv-skill -p -s review-fix-verify -y
```

Then invoke inside any git repo with `/review-fix-verify`, `review and fix`, or `rfv`.

→ Full install guide (symlink dev-mode, VS Code, uninstall): [docs/installation.md](docs/installation.md)

---

## Security

- `rfv-prep.sh` reads only git history and project files — no `.env`, no credential stores, no network requests.
- Diffs are inlined into subagent prompts and sent to external AI models. Don't run on diffs with secrets or PII.
- Found a vulnerability? See [SECURITY.md](SECURITY.md).

---

## Contributing

See [docs/development.md](docs/development.md).

---

## License

[MIT](LICENSE) © Zach Yeap
