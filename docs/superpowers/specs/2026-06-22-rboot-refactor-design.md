# rboot refactor design

**Date:** 2026-06-22
**Status:** approved

## Overview

Migrate `~/.repo-config` (a loose, unversioned directory holding a symlink-management script and per-repo config data) into this `repo-bootstrapper` git repository. Rename the CLI tool from `sprinkle-it` to `rboot`, restructure the project with a `bin/` directory and a Makefile, and gitignore the `repos/` config directory that holds secrets.

---

## Problem

The current setup has two problems:

1. **Unversioned, homedir-coupled tool.** `~/.repo-config/setup.sh` and `~/.repo-config/monorepo/` live outside any git repo. Changes aren't tracked; the tool can't be shared or reproduced easily.
2. **Confusing command name.** `sprinkle-it` is hard to remember and doesn't communicate intent. Subcommands (`apply`, default bare invocation) are inconsistent.

---

## Goals

- Move all script logic and per-repo config structure into `repo-bootstrapper`
- Gitignore `repos/` (contains `.env` files, `settings.local.json`, and other secrets)
- Rename the tool to `rboot` with clear subcommands
- Provide `make install` / `make uninstall` as the single installation interface
- Preserve all existing functionality from the feature-complete script (symlink resolution, `add`, nested repo discovery, atomic config writes)

---

## Project structure

```
repo-bootstrapper/
├── bin/
│   └── rboot           ← main executable
├── Makefile
├── repos/              ← gitignored; one subdirectory per managed repo
│   └── monorepo/
│       ├── setup.json
│       ├── .claude/
│       ├── client/
│       └── ...
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-06-22-rboot-refactor-design.md
└── .gitignore
```

---

## `bin/rboot` — command surface

| Command | Behaviour |
|---|---|
| `rboot` | Show usage listing available commands (no default action) |
| `rboot help` | Same as bare `rboot` |
| `rboot run` | Apply symlink config for current repo + auto-discovered nested repos |
| `rboot add <path>…` | Move path(s) into `repos/<repo-name>/` and replace originals with symlinks |

**Env var:** `RBOOT_CONFIG_DIR` overrides the default config directory (`${SCRIPT_DIR}/../repos`, resolved to an absolute path). Replaces the old `SPRINKLE_CONFIG_DIR`.

### `rboot run` behaviour (unchanged from `sprinkle-it apply`)

1. Resolves the current git repo's name from `remote.origin.url`
2. Looks up `repos/<repo-name>/setup.json`; exits with error if not found (hard requirement)
3. Symlinks each path listed in `.files[]` and each path listed in `.directories[]` into the repo root
4. Auto-discovers nested git repos (skips `node_modules/`, `.worktrees/`); applies their configs silently if found, deduplicating by repo name

### `rboot add <path>…` behaviour (unchanged from `sprinkle-it add`)

1. Validates the path exists, is not already a symlink, and is inside the current git repo
2. Moves it into `repos/<repo-name>/<rel-path>`
3. Creates a symlink at the original location pointing to the new destination
4. Atomically updates `repos/<repo-name>/setup.json` (idempotent jq write)
5. Warns if the path was git-tracked (symlink will show as a change)

---

## Makefile

```makefile
BIN_DIR  := $(HOME)/.local/bin
CMD      := rboot
TARGET   := $(abspath bin/rboot)
LINK     := $(BIN_DIR)/$(CMD)

.PHONY: install uninstall

install:
	chmod +x $(TARGET)
	mkdir -p $(BIN_DIR)
	ln -sfn $(TARGET) $(LINK)
	@echo "Installed: $(LINK) -> $(TARGET)"
	@case ":$$PATH:" in \
	  *":$(BIN_DIR):"*) echo "Run 'rboot' from inside any git repo." ;; \
	  *) echo "Warning: $(BIN_DIR) is not on your PATH." ; \
	     echo "Add to ~/.zshrc:  export PATH=\"$(BIN_DIR):$$PATH\"" ;; \
	esac

uninstall:
	rm -f $(LINK)
	@echo "Removed: $(LINK)"
```

---

## `.gitignore`

```
repos/
```

---

## Migration steps (one-time, manual)

1. Run `make install` from the `repo-bootstrapper` directory
2. Move `~/.repo-config/monorepo/` → `repos/monorepo/`
3. Verify with `rboot run` from inside the monorepo
4. Remove `~/.repo-config/` once confirmed working

---

## Out of scope

- No `rboot init` or `rboot list` commands
- No changes to `setup.json` schema
- No support for repos without a `remote.origin.url`
