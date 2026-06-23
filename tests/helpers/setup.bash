# tests/helpers/setup.bash
# Shared setup for all rboot bats tests.

RBOOT="${BATS_TEST_DIRNAME}/../bin/rboot"

# create_test_repo <dir> <repo-name>
# Initialises a git repo with a remote origin so rboot can derive the repo name.
create_test_repo() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "https://github.com/test/${name}.git"
  git -C "$dir" commit --allow-empty -q -m "init"
}

# global_setup — called in bats setup()
# Creates a temp HOME and a standard test repo named "testrepo".
rboot_setup() {
  export ORIG_HOME="$HOME"
  export HOME
  HOME="$(mktemp -d)"
  export REPO_DIR="${HOME}/testrepo"
  create_test_repo "$REPO_DIR" testrepo
  export CONFIG_BASE="${HOME}/repos/.repo-config"
  mkdir -p "${CONFIG_BASE}/testrepo"
  # Create empty setup.json so apply_config (required=true) does not exit 1
  echo '{"links":[]}' > "${CONFIG_BASE}/testrepo/setup.json"
  cd "$REPO_DIR"
}

# global_teardown
rboot_teardown() {
  local tmp_home="$HOME"
  export HOME="$ORIG_HOME"
  rm -rf "$tmp_home"
}
