# tests/helpers/setup.bash
RBOOT="${BATS_TEST_DIRNAME}/../bin/rboot"

# create_test_repo <dir> <name>
create_test_repo() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "https://github.com/test/${name}.git"
  git -C "$dir" commit --allow-empty -q -m "init"
}

# write_links — reads a JSON links array from stdin and writes it to the
# testrepo entry in the global config.
# Usage: write_links <<'EOF' ... EOF
write_links() {
  local links tmp
  links=$(cat)
  tmp=$(mktemp)
  jq --argjson links "$links" '.repos.testrepo.links = $links' "$RBOOT_CONFIG" > "$tmp"
  mv "$tmp" "$RBOOT_CONFIG"
}

rboot_setup() {
  export ORIG_HOME="$HOME"
  export HOME
  HOME="$(mktemp -d)"
  export REPO_DIR="${HOME}/testrepo"
  create_test_repo "$REPO_DIR" testrepo
  export RBOOT_CONFIG="${HOME}/.config/rboot/config.json"
  export CONFIG_PATH="${HOME}/.rboot/testrepo"
  mkdir -p "${HOME}/.config/rboot"
  mkdir -p "$CONFIG_PATH"
  jq -n --arg cp "$CONFIG_PATH" \
    '{"repos":{"testrepo":{"config_path":$cp,"links":[]}}}' \
    > "$RBOOT_CONFIG"
  cd "$REPO_DIR"
}

rboot_teardown() {
  local tmp_home="$HOME"
  export HOME="$ORIG_HOME"
  rm -rf "$tmp_home"
}
