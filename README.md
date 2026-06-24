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

All config lives in a single file: `~/.rboot/config.json`. Create it before first use:

```bash
mkdir -p ~/.rboot && echo '{}' > ~/.rboot/config.json
```

`rboot add` updates it automatically. To write an entry manually:

```json
{
  "repos": {
    "my-repo": {
      "links": [
        { "from": "{{config_path}}/.env", "to": "{{current_repo_root}}/.env" },
        { "from": "{{config_path}}/.secrets", "to": "{{current_repo_root}}/.secrets" }
      ]
    }
  }
}
```

The actual files (`.env`, `.secrets/`, etc.) live in `~/.rboot/<repo-name>/` by default. Override per-repo with a `config_path` key:

```json
{
  "repos": {
    "my-repo": {
      "config_path": "~/Dropbox/rboot/my-repo",
      "links": [...]
    }
  }
}
```
