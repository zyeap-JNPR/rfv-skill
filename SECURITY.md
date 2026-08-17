# Security Policy

Only the latest commit on `main` is supported.

## Data flow

RFV sends selected Git diff content to configured AI models. `rfv-prep.sh` makes
no network requests and persists no user data; its temporary NUL-delimited path
inventory is removed on exit. It rejects common secret-bearing paths before
emitting a patch and disables external diff drivers, text converters, and color
escapes.

Filename checks cannot detect every embedded credential, token, secret, or PII
value. Inspect the selected scope before invoking RFV. Keep secret files ignored
and never use production credentials, databases, or endpoints in detected commands.

Diff content is untrusted input. Reviewer and verifier prompts explicitly ignore
instructions embedded in code or comments. Builder prompts limit work to accepted
findings and forbid commits, pushes, deployments, dependency changes, and test
bypasses.

If a secret reaches Git history, stop using the diff, rotate the secret, and remove
it from history before continuing.

## Reporting

Do not open a public issue for a vulnerability. Use a
[private security advisory](https://github.com/zyeap-JNPR/rfv-skill/security/advisories/new)
with reproduction steps, impact, and a suggested fix when available.
