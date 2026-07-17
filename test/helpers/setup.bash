setup() {
  BAIZE_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BAIZE_BIN="$BAIZE_ROOT/baize"
  TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME"
  unset XDG_CONFIG_HOME XDG_STATE_HOME
  export PATH="$BAIZE_ROOT/test/helpers/stubs:$PATH"
  export BAIZE_STUB_CURL_LOG="$TEST_TMP/curl.log"
}

teardown() {
  [[ -n "${TEST_TMP:-}" ]] && rm -rf "$TEST_TMP"
}

write_config() {   # write_config "DSN=..." "THRESHOLD=90"
  mkdir -p "$HOME/.config/baize"
  printf '%s\n' "$@" > "$HOME/.config/baize/config"
}
