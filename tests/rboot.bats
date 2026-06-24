#!/usr/bin/env bats
load helpers/setup

setup()    { rboot_setup; }
teardown() { rboot_teardown; }

@test "rboot fails with clear error when global config is missing" {
  rm -f "$RBOOT_CONFIG"
  run bash "$RBOOT" run
  [ "$status" -ne 0 ]
  [[ "$output" == *".rboot/config.json"* ]]
}

@test "rboot succeeds when repo entry exists with empty links" {
  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
}

_call_resolve() {
  env HOME="$HOME" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    resolve_config_path \"\$1\"
  " -- "$1"
}

@test "resolve_config_path: returns explicit config_path from global config" {
  result=$(_call_resolve testrepo)
  [ "$result" = "$CONFIG_PATH" ]
}

@test "resolve_config_path: returns default ~/.rboot/<name> when absent" {
  # Remove config_path from the testrepo entry
  local tmp; tmp=$(mktemp)
  jq '.repos.testrepo |= del(.config_path)' "$RBOOT_CONFIG" > "$tmp"
  mv "$tmp" "$RBOOT_CONFIG"

  result=$(_call_resolve testrepo)
  [ "$result" = "${HOME}/.rboot/testrepo" ]
}

# Helper: source rboot and call expand_templates in a subprocess.
# All needed env vars are forwarded explicitly via env(1) prefix.
_expand() {
  # _expand <string> <repo_root> <config_path>
  env HOME="$HOME" REPO_ROOT="$REPO_DIR" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    expand_templates \"\$1\" \"\$2\" \"\$3\"
  " -- "$1" "$2" "$3"
}

@test "expand_templates: expands ~ to HOME" {
  result=$(_expand "~/some/path" "$REPO_DIR" "$CONFIG_PATH")
  [ "$result" = "${HOME}/some/path" ]
}

@test "expand_templates: expands {{current_repo_root}}" {
  result=$(_expand "{{current_repo_root}}/.claude" "$REPO_DIR" "$CONFIG_PATH")
  [ "$result" = "${REPO_DIR}/.claude" ]
}

@test "expand_templates: expands {{current_repo_root_encoded}}" {
  local expected="${REPO_DIR//\//-}"
  expected="${expected//./-}"
  result=$(_expand "{{current_repo_root_encoded}}" "$REPO_DIR" "$CONFIG_PATH")
  [ "$result" = "$expected" ]
}

@test "expand_templates: expands {{config_path}}" {
  result=$(_expand "{{config_path}}/file.txt" "$REPO_DIR" "$CONFIG_PATH")
  [ "$result" = "${CONFIG_PATH}/file.txt" ]
}

@test "expand_templates: silently skips {{parent_repo_root}} outside worktree" {
  # Test repo has .git as a directory — not a worktree
  run env HOME="$HOME" REPO_ROOT="$REPO_DIR" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    expand_templates '{{parent_repo_root}}' '${REPO_DIR}' '${CONFIG_PATH}'
  "
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "expand_templates: silently skips {{parent_repo_encoded}} outside worktree" {
  run env HOME="$HOME" REPO_ROOT="$REPO_DIR" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    expand_templates '{{parent_repo_encoded}}' '${REPO_DIR}' '${CONFIG_PATH}'
  "
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "expand_templates: warns on removed variable {{repo_root}}" {
  run _expand "{{repo_root}}/foo" "$REPO_DIR" "$CONFIG_PATH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

@test "expand_templates: warns on removed variable {{claude_projects_dir}}" {
  run _expand "{{claude_projects_dir}}/foo" "$REPO_DIR" "$CONFIG_PATH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

@test "expand_templates: warns and fails on unknown variable" {
  run _expand "{{unknown_var}}" "$REPO_DIR" "$CONFIG_PATH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

@test "apply_config: creates file symlink from links array" {
  local src="${CONFIG_PATH}/.claude/settings.json"
  mkdir -p "$(dirname "$src")"
  echo '{}' > "$src"

  write_links <<'EOF'
[{"from":"{{config_path}}/.claude/settings.json","to":"{{current_repo_root}}/.claude/settings.json"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [ -L "${REPO_DIR}/.claude/settings.json" ]
  [ "$(readlink "${REPO_DIR}/.claude/settings.json")" = "$src" ]
}

@test "apply_config: creates directory symlink from links array" {
  local src="${CONFIG_PATH}/docs/superpowers"
  mkdir -p "$src"
  touch "${src}/file.txt"

  write_links <<'EOF'
[{"from":"{{config_path}}/docs/superpowers","to":"{{current_repo_root}}/docs/superpowers"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [ -L "${REPO_DIR}/docs/superpowers" ]
}

@test "apply_config: is idempotent (skips correct symlink)" {
  local src="${CONFIG_PATH}/file.txt"
  echo "content" > "$src"
  mkdir -p "$(dirname "${REPO_DIR}/file.txt")"
  ln -sf "$src" "${REPO_DIR}/file.txt"

  write_links <<'EOF'
[{"from":"{{config_path}}/file.txt","to":"{{current_repo_root}}/file.txt"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [ "$(readlink "${REPO_DIR}/file.txt")" = "$src" ]
}

@test "apply_config: replaces wrong symlink with warning" {
  local src="${CONFIG_PATH}/file.txt"
  echo "content" > "$src"
  local wrong_target="/tmp/wrong-target"
  mkdir -p "$(dirname "${REPO_DIR}/file.txt")"
  ln -sf "$wrong_target" "${REPO_DIR}/file.txt"

  write_links <<'EOF'
[{"from":"{{config_path}}/file.txt","to":"{{current_repo_root}}/file.txt"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"replacing existing link"* ]]
  [ "$(readlink "${REPO_DIR}/file.txt")" = "$src" ]
}

@test "apply_config: warns and skips missing config_path source" {
  write_links <<'EOF'
[{"from":"{{config_path}}/missing.txt","to":"{{current_repo_root}}/missing.txt"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
  [ ! -e "${REPO_DIR}/missing.txt" ]
}

@test "apply_config: skips real file at destination with warning" {
  echo "real" > "${REPO_DIR}/protected.txt"
  local src="${CONFIG_PATH}/protected.txt"
  echo "managed" > "$src"

  write_links <<'EOF'
[{"from":"{{config_path}}/protected.txt","to":"{{current_repo_root}}/protected.txt"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"real file"* ]]
  [ "$(cat "${REPO_DIR}/protected.txt")" = "real" ]
}

@test "apply_config: skips worktree entries when not in a worktree" {
  write_links <<'EOF'
[{"from":"~/.claude/projects/{{parent_repo_encoded}}","to":"~/.claude/projects/{{current_repo_root_encoded}}"}]
EOF

  mkdir -p "${HOME}/.claude/projects"
  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "${HOME}/.claude/projects")" ]
}

@test "apply_config: warns and skips unknown template variable" {
  write_links <<'EOF'
[{"from":"{{config_path}}/f.txt","to":"{{unknown}}/f.txt"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

@test "apply_config: directory merge inserts only missing children" {
  local src="${CONFIG_PATH}/mydir"
  mkdir -p "$src"
  echo "a" > "${src}/a.txt"
  echo "b" > "${src}/b.txt"

  local tgt="${REPO_DIR}/mydir"
  mkdir -p "$tgt"
  echo "existing" > "${tgt}/b.txt"

  write_links <<'EOF'
[{"from":"{{config_path}}/mydir","to":"{{current_repo_root}}/mydir"}]
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [ -L "${tgt}/a.txt" ]
  [ ! -L "${tgt}/b.txt" ]
  [ "$(cat "${tgt}/b.txt")" = "existing" ]
}

@test "rboot add: creates global config entry with correct links" {
  echo "content" > "${REPO_DIR}/myfile.txt"

  run bash "$RBOOT" add myfile.txt
  [ "$status" -eq 0 ]

  run jq -r '.repos.testrepo.links[0].from' "$RBOOT_CONFIG"
  [ "$output" = "{{config_path}}/myfile.txt" ]

  run jq -r '.repos.testrepo.links[0].to' "$RBOOT_CONFIG"
  [ "$output" = "{{current_repo_root}}/myfile.txt" ]
}

@test "update_config: does not add duplicate links entries" {
  env HOME="$HOME" REPO_NAME=testrepo RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    update_config 'myfile.txt'
    update_config 'myfile.txt'
  " || { echo "update_config subprocess failed" >&2; false; }
  local count
  count=$(jq '.repos.testrepo.links | length' "$RBOOT_CONFIG")
  [ "$count" -eq 1 ]
}

@test "rboot add: output shows 'Added <rel> -> {{config_path}}/<rel>'" {
  echo "content" > "${REPO_DIR}/afile.txt"
  run bash "$RBOOT" add afile.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added afile.txt -> {{config_path}}/afile.txt"* ]]
}

@test "rboot add: moves file to config_path and creates symlink" {
  echo "content" > "${REPO_DIR}/moveme.txt"

  run bash "$RBOOT" add moveme.txt
  [ "$status" -eq 0 ]

  # File moved to config_path
  [ -f "${CONFIG_PATH}/moveme.txt" ]
  # Symlink created in repo
  [ -L "${REPO_DIR}/moveme.txt" ]
  [ "$(readlink "${REPO_DIR}/moveme.txt")" = "${CONFIG_PATH}/moveme.txt" ]
}

@test "is_worktree: returns 1 for main (non-worktree) repo" {
  run env HOME="$HOME" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    is_worktree '${REPO_DIR}'
  "
  [ "$status" -eq 1 ]
}

@test "is_worktree: returns 0 for a git worktree" {
  local wt_dir="${HOME}/testrepo-wt"
  git -C "$REPO_DIR" worktree add -q "$wt_dir" -b wt-branch
  run env HOME="$HOME" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    is_worktree '${wt_dir}'
  "
  git -C "$REPO_DIR" worktree remove --force "$wt_dir" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "_get_main_root: returns main repo path from a worktree" {
  local wt_dir="${HOME}/testrepo-wt2"
  # Resolve REPO_DIR through pwd -P to match what _get_main_root returns (macOS /private symlink)
  local repo_dir_real
  repo_dir_real=$(cd "$REPO_DIR" && pwd -P)
  git -C "$REPO_DIR" worktree add -q "$wt_dir" -b wt-branch2
  result=$(env HOME="$HOME" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    _get_main_root '${wt_dir}'
  ")
  local exit_code
  exit_code=$?
  git -C "$REPO_DIR" worktree remove --force "$wt_dir" 2>/dev/null || true
  [ $exit_code -eq 0 ]
  [ "$result" = "$repo_dir_real" ]
}

@test "expand_templates: expands {{parent_repo_root}} inside a worktree" {
  local wt_dir="${HOME}/testrepo-wt3"
  # Resolve REPO_DIR through pwd -P to match what expand_templates returns (macOS /private symlink)
  local repo_dir_real
  repo_dir_real=$(cd "$REPO_DIR" && pwd -P)
  git -C "$REPO_DIR" worktree add -q "$wt_dir" -b wt-branch3
  result=$(env HOME="$HOME" RBOOT_CONFIG="$RBOOT_CONFIG" bash -c "
    source '${RBOOT}'
    expand_templates '{{parent_repo_root}}/.claude' '${wt_dir}' '${CONFIG_PATH}'
  ")
  local exit_code
  exit_code=$?
  git -C "$REPO_DIR" worktree remove --force "$wt_dir" 2>/dev/null || true
  [ $exit_code -eq 0 ]
  [ "$result" = "${repo_dir_real}/.claude" ]
}
