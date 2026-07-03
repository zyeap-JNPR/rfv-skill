# Security Policy

## Scope

This repository contains a shell script (`rfv-prep.sh`) and an AI agent skill
definition (`SKILL.md`). Neither makes network requests or stores data. Security
concerns are most likely to arise from:

1. **Diff content** — when the skill is invoked, your git diff is inlined into AI
   model prompts. If your diff contains secrets, credentials, or PII, that data
   is sent to external AI providers. This is a user responsibility, not a code
   vulnerability, but it is worth documenting.

2. **Shell injection** — `rfv-prep.sh` passes user-supplied `SCOPE` arguments to
   `git` commands. This is bounded (arguments are passed as array elements, not
   via shell expansion), but unusual inputs should still be validated.

3. **Prompt injection** — `SKILL.md` instructs AI subagents. A malicious diff could
   attempt to override subagent instructions. The skill's "High signal only" and
   "Do not commit" instructions are the primary guardrails.

## Supported versions

Only the latest commit on `main` is supported.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Email: open a [GitHub private security advisory](https://github.com/zyeap-JNPR/rfv-skill/security/advisories/new)
instead. Include:

- A description of the vulnerability
- Steps to reproduce
- Impact assessment (what an attacker or misbehaving subagent could do)
- Suggested fix (if you have one)

We aim to respond within 5 business days and to publish a fix within 14 days of
confirmation.

## Security best practices for users

- **Do not run this skill on diffs containing secrets.** Stage and diff only the
  files you intend to review. Use `.gitignore` to keep secret files out of
  version control.
- **Review the diff before invoking.** Run `git diff` (or `git diff HEAD~1..HEAD`)
  and confirm no credential files are included before triggering the skill.
- **Production safety.** The skill is designed for local development and CI. Never
  configure its test command to point at production databases or production APIs.
