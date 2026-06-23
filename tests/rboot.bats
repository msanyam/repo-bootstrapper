#!/usr/bin/env bats
load helpers/setup

setup()    { rboot_setup; }
teardown() { rboot_teardown; }

@test "rboot fails with clear error when global config is missing" {
  rm -f "$RBOOT_CONFIG"
  run bash "$RBOOT" run
  [ "$status" -ne 0 ]
  [[ "$output" == *".config/rboot/config.json"* ]]
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

  write_setup_json <<EOF
{
  "links": [
    { "from": "~/.rboot/testrepo/.claude/settings.json",
      "to": "{{current_repo_root}}/.claude/settings.json" }
  ]
}
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

  write_setup_json <<EOF
{
  "links": [
    { "from": "~/.rboot/testrepo/docs/superpowers",
      "to": "{{current_repo_root}}/docs/superpowers" }
  ]
}
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

  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/file.txt", "to": "{{current_repo_root}}/file.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  # Symlink should still point to same target
  [ "$(readlink "${REPO_DIR}/file.txt")" = "$src" ]
}

@test "apply_config: replaces wrong symlink with warning" {
  local src="${CONFIG_PATH}/file.txt"
  echo "content" > "$src"
  local wrong_target="/tmp/wrong-target"
  mkdir -p "$(dirname "${REPO_DIR}/file.txt")"
  ln -sf "$wrong_target" "${REPO_DIR}/file.txt"

  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/file.txt", "to": "{{current_repo_root}}/file.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"replacing existing link"* ]]
  [ -L "${REPO_DIR}/file.txt" ]
  [ "$(readlink "${REPO_DIR}/file.txt")" = "$src" ]
}

@test "apply_config: warns and skips missing config-dir source" {
  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/missing.txt", "to": "{{current_repo_root}}/missing.txt" }] }
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

  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/protected.txt", "to": "{{current_repo_root}}/protected.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"real file"* ]]
  # Original file untouched
  [ "$(cat "${REPO_DIR}/protected.txt")" = "real" ]
}

@test "apply_config: skips worktree entries when not in a worktree" {
  # Test repo has .git as a directory (main repo) — parent_repo_* vars should be skipped silently
  local proj_dir="${HOME}/.claude/projects"
  mkdir -p "$proj_dir"

  write_setup_json <<EOF
{
  "links": [
    { "from": "{{parent_repo_root}}/.claude",
      "to": "{{current_repo_root}}/.claude-linked" }
  ]
}
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  # No symlink created because parent_repo_root skips silently outside worktree
  [ ! -e "${REPO_DIR}/.claude-linked" ]
}

@test "apply_config: silently skips when parent_repo_encoded used outside worktree" {
  write_setup_json <<EOF
{
  "links": [
    { "from": "~/some/path",
      "to": "~/other/{{parent_repo_encoded}}" }
  ]
}
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}

@test "apply_config: warns and skips unknown template variable" {
  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/f.txt", "to": "{{unknown}}/f.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

@test "rboot add: creates setup.json with links array" {
  echo "content" > "${REPO_DIR}/myfile.txt"

  run bash "$RBOOT" add myfile.txt
  [ "$status" -eq 0 ]

  # setup.json should exist with links array
  local cfg="${CONFIG_PATH}/setup.json"
  [ -f "$cfg" ]
  run jq -r '.links[0].from' "$cfg"
  [ "$output" = "~/.rboot/testrepo/myfile.txt" ]
  run jq -r '.links[0].to' "$cfg"
  [ "$output" = "{{current_repo_root}}/myfile.txt" ]
}

@test "update_config: does not add duplicate links entries" {
  local cfg="${CONFIG_PATH}/setup.json"
  # Call update_config twice with the same rel; REPO_NAME must be exported
  env HOME="$HOME" REPO_NAME=testrepo bash -c "
    source '${RBOOT}'
    update_config '${cfg}' 'myfile.txt'
    update_config '${cfg}' 'myfile.txt'
  " || { echo "update_config subprocess failed" >&2; false; }
  local count
  count=$(jq '.links | length' "$cfg")
  [ "$count" -eq 1 ]
}

@test "rboot add: output shows 'Added <rel> -> <dest>'" {
  echo "content" > "${REPO_DIR}/afile.txt"
  run bash "$RBOOT" add afile.txt
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added afile.txt -> ~/.rboot/testrepo/afile.txt"* ]]
}

@test "apply_config: directory merge inserts only missing children" {
  # Set up source dir with two children
  local src="${CONFIG_PATH}/mydir"
  mkdir -p "$src"
  echo "a" > "${src}/a.txt"
  echo "b" > "${src}/b.txt"

  # Set up target dir that already has b.txt
  local tgt="${REPO_DIR}/mydir"
  mkdir -p "$tgt"
  echo "existing" > "${tgt}/b.txt"

  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/mydir", "to": "{{current_repo_root}}/mydir" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  # a.txt symlinked in, b.txt untouched
  [ -L "${tgt}/a.txt" ]
  [ ! -L "${tgt}/b.txt" ]
  [ "$(cat "${tgt}/b.txt")" = "existing" ]
}
