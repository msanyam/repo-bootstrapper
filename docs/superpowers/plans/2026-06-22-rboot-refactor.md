# rboot Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the loose `~/.repo-config` tooling into this repo as `bin/rboot`, rename commands to `rboot run` / `rboot add`, and provide `make install` / `make uninstall` as the installation interface.

**Architecture:** The project ships a single self-contained bash script at `bin/rboot` that manages symlinks from a `repos/` config directory into target git repos. A `Makefile` handles installation. `repos/` is gitignored because it holds secrets.

**Tech Stack:** Bash, jq, GNU Make

---

## File Map

| Path | Action | Responsibility |
|------|--------|----------------|
| `bin/rboot` | Create | Main CLI script — all symlink management logic |
| `Makefile` | Create | `make install` and `make uninstall` targets |
| `.gitignore` | Create | Ignore `repos/` directory |

---

### Task 1: Project skeleton

**Files:**
- Create: `.gitignore`
- Create: `bin/` directory

- [ ] **Step 1: Create `.gitignore`**

```
repos/
```

File path: `.gitignore`

- [ ] **Step 2: Create `bin/` directory**

```bash
mkdir -p bin
```

- [ ] **Step 3: Verify `.gitignore` content**

```bash
cat .gitignore
```

Expected output:
```
repos/
```

---

### Task 2: Makefile

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create `Makefile`**

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

- [ ] **Step 2: Verify `make install` runs without error (dry check — no `bin/rboot` yet, skip if it fails)**

```bash
make --dry-run install
```

Expected: prints the commands it would run without executing them.

---

### Task 3: `bin/rboot` script

**Files:**
- Create: `bin/rboot`

This is the primary task. The script is based on the full-featured sprinkle-it version with these specific changes:

- `SPRINKLE_CONFIG_DIR` env var renamed to `RBOOT_CONFIG_DIR`
- Default `CONFIG_DIR` changed from `${SCRIPT_DIR}/repos` to `${SCRIPT_DIR}/../repos` (since script lives in `bin/`, config lives at project root `repos/`)
- `cmd_apply` function renamed to `cmd_run`
- Bare invocation (no subcommand) now shows usage instead of running apply
- `usage()` updated to show `rboot` command names
- All `sprinkle-it` references in strings replaced with `rboot`
- `apply` subcommand replaced with `run`

- [ ] **Step 1: Create `bin/rboot` with the full script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Resolve the real script location, following symlinks (e.g. when invoked via
# the rboot symlink in ~/.local/bin).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  dir="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="${dir}/${SOURCE}"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
CONFIG_DIR="${RBOOT_CONFIG_DIR:-${SCRIPT_DIR}/../repos}"

# repo_name_from <repo_root>
# Echoes the config name for a repo, derived from its git remote origin URL.
repo_name_from() {
  local repo_root="$1"
  local url
  url=$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null) || return 1
  basename -s .git "$url"
}

# apply_config <repo_name> <repo_root> <indent> [required]
# Applies the symlink config (files + directories) for a single repo.
apply_config() {
  local repo_name="$1"
  local repo_root="$2"
  local indent="${3:-}"
  local required="${4:-false}"
  local config_file="${CONFIG_DIR}/${repo_name}/setup.json"

  if [[ ! -f "$config_file" ]]; then
    if [[ "$required" == "true" ]]; then
      echo "Error: no config found for '${repo_name}' at ${config_file}." >&2
      exit 1
    fi
    return
  fi

  echo "${indent}Running setup for ${repo_name}..."

  # Symlink files
  jq -r '.files[]?' "$config_file" | while IFS= read -r file; do
    local source="${CONFIG_DIR}/${repo_name}/${file}"
    local target="${repo_root}/${file}"

    if [[ ! -f "$source" && ! -L "$source" ]]; then
      echo "${indent}  Warning: ${source} not found — skipping"
      continue
    fi

    mkdir -p "$(dirname "$target")"
    ln -sf "$source" "$target"
    echo "${indent}  Symlinked ${file} -> ${source}"
  done

  # Symlink directories
  # - If the target does not exist (or is already a symlink), replace it with a
  #   single symlink to the source directory.
  # - If the target is a real directory, merge: symlink each child of the source
  #   into the target, replacing any existing children.
  jq -r '.directories[]?' "$config_file" | while IFS= read -r dir; do
    local source="${CONFIG_DIR}/${repo_name}/${dir}"
    local target="${repo_root}/${dir}"

    if [[ ! -d "$source" && ! -L "$source" ]]; then
      echo "${indent}  Warning: ${source} not found — skipping"
      continue
    fi

    if [[ -d "$target" && ! -L "$target" ]]; then
      for child_path in "$source"/* "$source"/.[!.]*; do
        [[ -e "$child_path" || -L "$child_path" ]] || continue
        local child_name
        child_name=$(basename "$child_path")
        local child_target="${target}/${child_name}"
        if [[ -e "$child_target" || -L "$child_target" ]]; then
          echo "${indent}  Skipped ${dir}/${child_name} — already exists"
          continue
        fi
        ln -sfn "$child_path" "$child_target"
        echo "${indent}  Symlinked ${dir}/${child_name} -> ${child_path}"
      done
    else
      mkdir -p "$(dirname "$target")"
      ln -sfn "$source" "$target"
      echo "${indent}  Symlinked ${dir} -> ${source}"
    fi
  done
}

usage() {
  cat <<'EOF'
Usage:
  rboot run              Apply symlink config for the current repo (+ nested repos)
  rboot add <path>...    Move path(s) into the rboot config and replace with symlinks
  rboot help             Show this help
EOF
}

# require_env — guards + identity. Called only by command bodies (NOT at file
# scope), so help works outside a git repo.
require_env() {
  if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "Error: config directory not found at ${CONFIG_DIR}." >&2
    echo "       (resolved script dir: ${SCRIPT_DIR})" >&2
    exit 1
  fi
  git rev-parse --is-inside-work-tree &>/dev/null || { echo "Error: not inside a git repository." >&2; exit 1; }
  git config --get remote.origin.url &>/dev/null || { echo "Error: no remote 'origin' configured." >&2; exit 1; }
  command -v jq &>/dev/null || { echo "Error: jq is required but not installed. Run: brew install jq" >&2; exit 1; }
  REPO_NAME=$(repo_name_from ".") || { echo "Error: could not determine repository name." >&2; exit 1; }
  [[ -n "$REPO_NAME" ]] || { echo "Error: could not determine repository name." >&2; exit 1; }
  REPO_ROOT=$(cd "$(git rev-parse --show-toplevel)" && pwd -P) || { echo "Error: could not resolve repository root." >&2; exit 1; }
}

# resolve_rel — print repo-root-relative path; nonzero if missing/outside.
resolve_rel() {
  local arg="$1" abs base dir
  if [[ -d "$arg" ]]; then
    abs=$(cd "$arg" && pwd -P) || return 1
  elif [[ -e "$arg" || -L "$arg" ]]; then
    base=$(basename "$arg")
    dir=$(cd "$(dirname "$arg")" && pwd -P) || return 1
    abs="$dir/$base"
  else
    return 2
  fi
  local rel="${abs#"$REPO_ROOT"/}"
  if [[ "$abs" == "$REPO_ROOT" || "$rel" == "$abs" ]]; then return 3; fi
  printf '%s\n' "$rel"
}

# update_config — atomic, idempotent setup.json write.
update_config() {   # <cfg_path> <rel> <files|directories>
  local cfg="$1" rel="$2" key="$3" tmp
  tmp=$(mktemp "${cfg}.XXXXXX") || return 1
  if jq --arg p "$rel" --arg key "$key" '
        .files = (.files // [])
        | .directories = (.directories // [])
        | if (.[$key] | index($p)) then . else .[$key] += [$p] end
      ' "$cfg" > "$tmp"; then
    mv "$tmp" "$cfg"
  else
    rm -f "$tmp"; return 1
  fi
}

# add_one — validate-then-mutate, set -e-safe.
add_one() {
  local arg="$1" rel dest src key cfg label
  if [[ -L "$arg" ]]; then echo "Skip: '$arg' is already a symlink (already managed by rboot)." >&2; return 1; fi
  if [[ ! -e "$arg" ]]; then echo "Error: '$arg' does not exist." >&2; return 1; fi
  rel=$(resolve_rel "$arg") || { echo "Error: '$arg' is outside the repository." >&2; return 1; }
  if [[ -d "$arg" ]]; then key=directories; else key=files; fi
  dest="${CONFIG_DIR}/${REPO_NAME}/${rel}"
  src="${REPO_ROOT}/${rel}"
  if [[ -e "$dest" || -L "$dest" ]]; then
    echo "Error: destination already exists: ${dest} (refusing to clobber)." >&2; return 1; fi

  cfg="${CONFIG_DIR}/${REPO_NAME}/setup.json"
  mkdir -p "${CONFIG_DIR}/${REPO_NAME}"
  [[ -f "$cfg" ]] || printf '{\n    "files": [],\n    "directories": []\n}\n' > "$cfg"

  mkdir -p "$(dirname "$dest")"
  if ! mv "$src" "$dest"; then echo "Error: failed to move ${src} -> ${dest}." >&2; return 1; fi

  mkdir -p "$(dirname "$src")"
  if ! ln -sfn "$dest" "$src"; then
    echo "Error: failed to create symlink; rolling back move." >&2; mv "$dest" "$src"; return 1; fi

  if ! update_config "$cfg" "$rel" "$key"; then
    echo "Warning: moved+linked ${rel} but failed to update ${cfg}; add '${rel}' manually." >&2; return 1; fi

  if git -C "$REPO_ROOT" ls-files --error-unmatch -- "$rel" &>/dev/null; then
    echo "Warning: '${rel}' was git-tracked; the symlink will now show as a change. Update .gitignore yourself if desired." >&2; fi

  if [[ "$key" == "directories" ]]; then label="directory"; else label="file"; fi
  echo "Added ${rel} (${label}) -> ${dest}"
}

# cmd_add — batch with per-path continue.
cmd_add() {
  require_env
  [[ $# -ge 1 ]] || { echo "Error: 'add' requires at least one path." >&2; usage >&2; exit 1; }
  local rc=0
  for arg in "$@"; do
    add_one "$arg" || rc=1
  done
  return "$rc"
}

# cmd_run — apply symlink config for current repo + nested repos.
cmd_run() {
  require_env

  apply_config "$REPO_NAME" "$REPO_ROOT" "" "true"

  local applied_names=""
  while IFS= read -r gitpath; do
    sub_root=$(dirname "$gitpath")
    sub_root=$(cd "$sub_root" && pwd -P) || continue
    sub_name=$(repo_name_from "$sub_root") || continue
    [[ -n "$sub_name" ]] || continue
    [[ "$sub_name" != "$REPO_NAME" ]] || continue
    case " $applied_names " in *" $sub_name "*) continue ;; esac
    applied_names="$applied_names $sub_name"
    apply_config "$sub_name" "$sub_root" "  "
  done < <(find "$REPO_ROOT" -mindepth 2 \
             -path '*/node_modules/*' -prune -o \
             -path "$REPO_ROOT/.worktrees/*" -prune -o \
             -name .git -print 2>/dev/null)

  echo "Done."
}

case "${1:-}" in
  run)             shift;         cmd_run ;;
  add)             shift;         cmd_add "$@" ;;
  -h|--help|help)  usage ;;
  "")              usage ;;
  *)               echo "Error: unknown command '$1'." >&2; usage >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Make `bin/rboot` executable**

```bash
chmod +x bin/rboot
```

- [ ] **Step 3: Verify bare invocation shows usage**

```bash
bin/rboot
```

Expected output:
```
Usage:
  rboot run              Apply symlink config for the current repo (+ nested repos)
  rboot add <path>...    Move path(s) into the rboot config and replace with symlinks
  rboot help             Show this help
```

- [ ] **Step 4: Verify `help` subcommand shows same usage**

```bash
bin/rboot help
```

Expected: same output as Step 3.

- [ ] **Step 5: Verify unknown command exits non-zero with error**

```bash
bin/rboot apply 2>&1; echo "exit: $?"  # 'apply' is intentionally an unknown command now
```

Expected:
```
Error: unknown command 'apply'.
...usage block...
exit: 1
```

- [ ] **Step 6: Verify `run` outside a git repo exits with error**

```bash
(cd /tmp && "$PWD/bin/rboot" run) 2>&1; echo "exit: $?"
```

Expected: `Error: not inside a git repository.` with non-zero exit.

---

### Task 4: `make install` end-to-end

- [ ] **Step 1: Run `make install`**

```bash
make install
```

Expected output includes:
```
Installed: ~/.local/bin/rboot -> /path/to/repo-bootstrapper/bin/rboot
```

- [ ] **Step 2: Verify symlink was created**

```bash
ls -la ~/.local/bin/rboot
```

Expected: a symlink pointing to the absolute path of `bin/rboot`.

- [ ] **Step 3: Verify `rboot` is invocable from PATH**

```bash
rboot
```

Expected: shows usage (same as Task 3 Step 3).

- [ ] **Step 4: Run `make uninstall`**

```bash
make uninstall
```

Expected:
```
Removed: /Users/<you>/.local/bin/rboot
```

- [ ] **Step 5: Verify symlink is gone**

```bash
ls ~/.local/bin/rboot 2>&1; echo "exit: $?"
```

Expected: `No such file or directory` with non-zero exit.

- [ ] **Step 6: Re-run `make install` to restore**

```bash
make install
```

---

### Final: Commit

- [ ] **Verify project structure is correct**

```bash
find . -not -path './.git/*' -not -path './.context/*' | sort
```

Expected:
```
.
./Makefile
./bin
./bin/rboot
./docs
./docs/superpowers
./docs/superpowers/plans
./docs/superpowers/plans/2026-06-22-rboot-refactor.md
./docs/superpowers/specs
./docs/superpowers/specs/2026-06-22-rboot-refactor-design.md
./.gitignore
./.gitkeep
```

- [ ] **Commit using the project commit skill**

Use the `commit` skill. Format: `[<module>] :<gitmoji>: <short description>`

```bash
git add bin/rboot Makefile .gitignore docs/
git commit -m "[rboot] :sparkles: add rboot CLI, Makefile install, migrate from sprinkle-it"
```
