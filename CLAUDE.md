# repo-bootstrapper

## Quick Start

```bash
make install    # symlink bin/rboot -> ~/.local/bin/rboot
make uninstall  # remove the symlink
```

## Commands

```bash
rboot run           # apply symlink config for current repo (+ nested repos)
rboot add <path>    # move file/dir into config and replace with a symlink
rboot help          # show usage
```

## Architecture

```
bin/rboot                              # single bash script — all logic lives here
~/repos/.repo-config/                  # config dir (outside the rboot repo)
~/repos/.repo-config/<name>/setup.json # declares links[] to symlink
~/repos/.repo-config/<name>/<path>     # the actual managed file or directory
```

`<name>` is derived from `basename $(git remote get-url origin)` (strips `.git`).

## Key Patterns

- `CLAUDE_PROJECTS_DIR` overrides `~/.claude/projects`
- `rboot run` inside a git worktree can symlink that worktree's Claude project dir to the main repo's so memories are shared — declare it in `links[]` using `{{main_encoded}}` and `{{worktree_encoded}}`
- All loops use process substitution `< <(...)`, not pipes — preserves `set -euo pipefail`
- `links[]` entries use `{ "from": "...", "to": "..." }` objects with template variables
- Directory symlink strategy: symlink the whole dir if `to` doesn't exist; merge children into `to` if it's a real directory (config-dir source only)

## Template Variables

| Variable | Resolves to |
|---|---|
| `{{repo_root}}` | Absolute path of the current repo root |
| `{{claude_projects_dir}}` | `${CLAUDE_PROJECTS_DIR:-~/.claude/projects}` |
| `{{worktree_encoded}}` | Encoded current worktree path (worktree only) |
| `{{main_encoded}}` | Encoded main worktree path (worktree only) |

`~` at the start of any value expands to `$HOME`.

## Gotchas

- `~/repos/.repo-config/` must exist before `rboot run` works — it is not auto-created
- `setup.json` is created automatically by `rboot add`; no need to create it manually
- `encode_claude_path` replaces both `/` and `.` with `-` (not just `/`)
- `git worktree list --porcelain`: first entry is always the main worktree
- `.gitignore` covers `docs/superpowers` — not tracked
