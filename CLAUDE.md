# repo-bootstrapper

## Quick Start

```bash
make install    # symlink bin/rboot -> ~/.local/bin/rboot
make uninstall  # remove the symlink
```

## Commands

```bash
rboot run           # apply symlink config for current repo + link Claude worktree memory
rboot add <path>    # move file/dir into config and replace with a symlink
rboot help          # show usage
```

## Architecture

```
bin/rboot                        # single bash script — all logic lives here
repos/                           # gitignored config dir (one subdir per repo)
repos/<name>/setup.json          # declares files[] and directories[] to symlink
repos/<name>/<path>              # the actual managed file or directory
```

`<name>` is derived from `basename $(git remote get-url origin)` (strips `.git`).

## Key Patterns

- `RBOOT_CONFIG_DIR` overrides the `repos/` directory location
- `CLAUDE_PROJECTS_DIR` overrides `~/.claude/projects`
- `rboot run` inside a git worktree symlinks that worktree's Claude project dir to the main repo's so memories are shared
- All loops use process substitution `< <(...)`, not pipes — preserves `set -euo pipefail`
- Directory symlink strategy: symlink the whole dir if target doesn't exist; merge children into target if it's a real directory

## Gotchas

- `repos/` must exist before `rboot run` works — it is not auto-created
- `setup.json` is created automatically by `rboot add`; no need to create it manually
- `encode_claude_path` replaces both `/` and `.` with `-` (not just `/`)
- `git worktree list --porcelain`: first entry is always the main worktree
- `.gitignore` covers `repos/` and `docs/superpowers` — neither is tracked
