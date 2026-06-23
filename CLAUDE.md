# repo-bootstrapper

## Quick Start

```bash
make install    # symlink bin/rboot -> ~/.local/bin/rboot
make uninstall  # remove the symlink
```

## Commands

```bash
rboot run           # apply symlink config for current repo (+ nested repos)
rboot add <path>    # move file/dir into config_path and replace with a symlink
rboot help          # show usage
```

## Architecture

```
bin/rboot                              # single bash script — all logic lives here
~/.config/rboot/config.json           # global config — all repos in one file
```

`~/.config/rboot/config.json` structure:

```json
{
  "repos": {
    "<repo-name>": {
      "config_path": "~/optional/path",
      "links": [
        { "from": "{{config_path}}/file", "to": "{{current_repo_root}}/file" }
      ]
    }
  }
}
```

`<repo-name>` is derived from `basename $(git remote get-url origin)` (strips `.git`).
`config_path` defaults to `~/.rboot/<repo-name>/` when not set.

## Key Patterns

- All loops use process substitution `< <(...)`, not pipes — preserves `set -euo pipefail`
- `links[]` entries use `{ "from": "...", "to": "..." }` objects with template variables
- Directory symlink strategy: symlink the whole dir if `to` doesn't exist; merge children into `to` if it's a real directory (config_path source only)
- `is_worktree(path)` uses `git -C path rev-parse --git-dir vs --git-common-dir` — correctly distinguishes worktrees from submodules

## Template Variables

| Variable | Resolves to |
|---|---|
| `{{config_path}}` | Per-repo `config_path` value (or `~/.rboot/<name>/`) |
| `{{current_repo_root}}` | Absolute path of the repo being processed |
| `{{current_repo_root_encoded}}` | `encode_claude_path(current_repo_root)` |
| `{{parent_repo_root}}` | Main worktree root (worktree only) |
| `{{parent_repo_encoded}}` | `encode_claude_path(main_worktree_root)` (worktree only) |

`~` at the start of any value expands to `$HOME`. `config_path` values are not themselves template-expanded.

## Gotchas

- `~/.config/rboot/config.json` must exist before `rboot run` works — it is not auto-created
- `encode_claude_path` replaces both `/` and `.` with `-` (not just `/`)
- `git worktree list --porcelain`: first entry is always the main worktree
- `shopt -p dotglob || true` — required: `shopt -p` exits 1 when option is off, kills script under `set -euo pipefail`
- Worktree-only variables (`{{parent_repo_*}}`) skip silently in non-worktrees and in submodules (not just main repos)
