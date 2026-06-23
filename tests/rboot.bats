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

# Helper: source rboot and call expand_templates in a subprocess.
# All needed env vars are forwarded explicitly via env(1) prefix.
_expand() {
  env HOME="$HOME" REPO_ROOT="$REPO_DIR" bash -c "
    source '${RBOOT}'
    expand_templates \"\$1\" \"\$2\"
  " -- "$1" "$2"
}

@test "expand_templates: expands ~ to HOME" {
  result=$(_expand "~/some/path" "$REPO_DIR")
  [ "$result" = "${HOME}/some/path" ]
}

@test "expand_templates: expands {{repo_root}}" {
  result=$(_expand "{{repo_root}}/.claude" "$REPO_DIR")
  [ "$result" = "${REPO_DIR}/.claude" ]
}

@test "expand_templates: expands {{claude_projects_dir}} with default" {
  result=$(_expand "{{claude_projects_dir}}/foo" "$REPO_DIR")
  [ "$result" = "${HOME}/.claude/projects/foo" ]
}

@test "expand_templates: honours CLAUDE_PROJECTS_DIR env var" {
  local custom="${HOME}/custom"
  result=$(env HOME="$HOME" REPO_ROOT="$REPO_DIR" CLAUDE_PROJECTS_DIR="$custom" bash -c "
    source '${RBOOT}'
    expand_templates '{{claude_projects_dir}}/foo' '${REPO_DIR}'
  ")
  [ "$result" = "${custom}/foo" ]
}

@test "expand_templates: silently skips worktree vars outside worktree" {
  # REPO_ROOT/.git is a directory (main repo) — not a worktree
  run env HOME="$HOME" REPO_ROOT="$REPO_DIR" bash -c "
    source '${RBOOT}'
    expand_templates '{{worktree_encoded}}' '${REPO_DIR}'
  "
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "expand_templates: warns and fails on unknown variable" {
  run env HOME="$HOME" REPO_ROOT="$REPO_DIR" bash -c "
    source '${RBOOT}'
    expand_templates '{{unknown_var}}' '${REPO_DIR}'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown template variable"* ]]
}

# Helper: write links array to the config
write_setup_json() {
  local links
  links=$(cat)
  write_links <<< "$links"
}

@test "apply_config: creates file symlink from links array" {
  local src="${CONFIG_PATH}/.claude/settings.json"
  mkdir -p "$(dirname "$src")"
  echo '{}' > "$src"

  write_setup_json <<EOF
{
  "links": [
    { "from": "~/.rboot/testrepo/.claude/settings.json",
      "to": "{{repo_root}}/.claude/settings.json" }
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
      "to": "{{repo_root}}/docs/superpowers" }
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
{ "links": [{ "from": "~/.rboot/testrepo/file.txt", "to": "{{repo_root}}/file.txt" }] }
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
{ "links": [{ "from": "~/.rboot/testrepo/file.txt", "to": "{{repo_root}}/file.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"replacing existing link"* ]]
  [ -L "${REPO_DIR}/file.txt" ]
  [ "$(readlink "${REPO_DIR}/file.txt")" = "$src" ]
}

@test "apply_config: warns and skips missing config-dir source" {
  write_setup_json <<EOF
{ "links": [{ "from": "~/.rboot/testrepo/missing.txt", "to": "{{repo_root}}/missing.txt" }] }
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
{ "links": [{ "from": "~/.rboot/testrepo/protected.txt", "to": "{{repo_root}}/protected.txt" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  [[ "$output" == *"real file"* ]]
  # Original file untouched
  [ "$(cat "${REPO_DIR}/protected.txt")" = "real" ]
}

@test "apply_config: skips worktree entries when not in a worktree" {
  # Claude projects dir exists but no worktree
  mkdir -p "${HOME}/.claude/projects"

  write_setup_json <<EOF
{
  "links": [
    { "from": "{{claude_projects_dir}}/{{main_encoded}}",
      "to": "{{claude_projects_dir}}/{{worktree_encoded}}" }
  ]
}
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  # No symlinks created in claude projects dir
  [ -z "$(ls -A "${HOME}/.claude/projects")" ]
}

@test "apply_config: silently skips when claude_projects_dir missing" {
  # Do NOT create ~/.claude/projects

  write_setup_json <<EOF
{
  "links": [
    { "from": "{{claude_projects_dir}}/{{main_encoded}}",
      "to": "{{claude_projects_dir}}/{{worktree_encoded}}" }
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
  [ "$output" = "{{repo_root}}/myfile.txt" ]
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
{ "links": [{ "from": "~/.rboot/testrepo/mydir", "to": "{{repo_root}}/mydir" }] }
EOF

  run bash "$RBOOT" run
  [ "$status" -eq 0 ]
  # a.txt symlinked in, b.txt untouched
  [ -L "${tgt}/a.txt" ]
  [ ! -L "${tgt}/b.txt" ]
  [ "$(cat "${tgt}/b.txt")" = "existing" ]
}
