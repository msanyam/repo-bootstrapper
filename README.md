# repo-bootstrapper

A symlink-based dotfile/config manager for git repos. Run `rboot run` inside any repo to apply your config — symlinks secrets, dotfiles, and shared directories into place. Runs automatically inside git worktrees and links Claude Code project memories so context is shared across branches.

## Install

```bash
make install
```

Symlinks `bin/rboot` into `~/.local/bin/rboot`. Make sure `~/.local/bin` is on your `PATH`.

## Usage

```bash
# After cloning a repo or creating a worktree:
rboot run

# Move a file/dir into the config and replace it with a symlink:
rboot add .env
rboot add .secrets/ config/local.json
```

## Config

`repos/` holds one directory per repo (named by its git remote origin). It is gitignored — keep it in private storage or a backup.

```
repos/
  my-repo/
    setup.json        # declares which files and dirs to symlink
    .env              # the actual secret file
    .secrets/         # a shared directory
```

`setup.json` is created automatically by `rboot add`. To write one manually:

```json
{
  "files": [".env", "config/local.json"],
  "directories": [".secrets"]
}
```
