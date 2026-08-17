# Installation

Copilot discovers skills in:

| Scope | Directory |
|-------|-----------|
| Project | `<repo>/.agents/skills/` |
| Global | `~/.agents/skills/` |

## Skills CLI

Recommended because it records the source for updates:

```bash
# Global
npx skills add zyeap-JNPR/rfv-skill -g -s review-fix-verify -y

# Current project
npx skills add zyeap-JNPR/rfv-skill -p -s review-fix-verify -y

npx skills list
npx skills update review-fix-verify
```

## Development symlink

```bash
git clone https://github.com/zyeap-JNPR/rfv-skill.git ~/work/github/rfv-skill
mkdir -p ~/.agents/skills
ln -s ~/work/github/rfv-skill/skills/review-fix-verify \
  ~/.agents/skills/review-fix-verify
```

Edits become live immediately. Update with:

```bash
git -C ~/work/github/rfv-skill pull --ff-only
```

For project-only use, place the symlink under
`<repo>/.agents/skills/review-fix-verify`.

## Use

Reload VS Code after installation; Copilot CLI discovers the skill on startup.
Invoke inside a Git repository:

```text
/review-fix-verify [path|range]
review and fix
rfv --fast
rfv --thorough
```

## Remove

```bash
# Skills CLI
npx skills remove review-fix-verify

# Development symlink
rm ~/.agents/skills/review-fix-verify
```

The second command removes only the symlink.

## Compatibility

| Requirement | Notes |
|-------------|-------|
| Bash | 3.2+ |
| Git | 2.0+ |
| `jq` | Optional; required only for reliable Node/Composer script parsing |
| OS | macOS, Linux; Windows through WSL2 or Git Bash |
| Copilot | `task` model overrides and `code-review` agent support |

The script uses Bash arrays and process substitution plus POSIX-compatible
`awk`, `grep`, `sed`, and `tr` options.
