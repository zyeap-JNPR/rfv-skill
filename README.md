# rfv-skill

Portable GitHub Copilot skill for a bounded multi-model
**review -> fix -> verify** workflow.

- Sonnet and Terra review correctness in parallel.
- The orchestrator validates every finding before fixes begin.
- A Sonnet builder edits only accepted findings and runs repository tests.
- A Terra verifier reviews changes isolated from a pre-fix snapshot.
- Fix/test and fix/verify loops have hard limits.

`rfv-prep.sh` supplies bounded diff context and detects commands for Node, Make,
Go, Rust, Python, Maven, Gradle, .NET, Swift, Ruby, PHP, and Elixir. For
working-tree scopes, it rejects relevant untracked input and common sensitive file
paths before prompt content is emitted.

Full behavior: [`skills/review-fix-verify/README.md`](skills/review-fix-verify/README.md)

## Install

```bash
# Global
npx skills add zyeap-JNPR/rfv-skill -g -s review-fix-verify -y

# Per repository
npx skills add zyeap-JNPR/rfv-skill -p -s review-fix-verify -y
```

Invoke inside a Git repository:

```text
review and fix
rfv --fast
/review-fix-verify src/api/
rfv --thorough
```

See [docs/installation.md](docs/installation.md) for symlink development,
upgrades, removal, and compatibility.

## Layout

```text
skills/review-fix-verify/
  SKILL.md       execution contract
  README.md      user guide
  rfv-prep.sh    bounded preflight
tests/
  rfv-prep.bats  behavioral coverage
Makefile         local and CI validation entrypoint
```

## Security

Diffs are sent to configured AI models. The preflight blocks common secret-bearing
paths, external diff/text-conversion helpers, and ANSI output, but cannot identify
every secret or PII value. Inspect scope before invocation and never target
production systems. See [SECURITY.md](SECURITY.md).

## Development

See [docs/development.md](docs/development.md).

## License

[MIT](LICENSE) (c) Zach Yeap
