load 'helpers/setup'

DSN_OK='https://abc123@glitchtip.example.com/7'

# Simulates the host already having a working baize installed -- exactly
# what `update` assumes going in. Mirrors remove.bats's install_fake_binary.
install_fake_binary() {
  mkdir -p "$HOME/.local/bin"
  cp "$BAIZE_BIN" "$HOME/.local/bin/baize"
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

leftover_tmp_dirs() {
  find "$HOME/.local/bin" -maxdepth 1 -name '.baize-update.*' 2>/dev/null
}

# A synthetic "downloaded candidate" whose `version` output and `check`
# exit code are both controlled by the caller -- used only for the
# self-test / rollback failure-mode tests, where reusing $BAIZE_BIN's own
# bytes (the happy-path fixture below) can't produce the needed behavior.
fake_candidate_content() {   # fake_candidate_content VERSION_OUTPUT CHECK_EXIT
  local version_output="$1" check_exit="$2"
  cat <<EOF
#!/usr/bin/env bash
case "\$1" in
  version) printf '%s\n' "$version_output" ;;
  check) exit $check_exit ;;
  *) exit 0 ;;
esac
EOF
}

# The happy-path fixture: serve $BAIZE_BIN's own bytes as the "new"
# release. It is a real, working baize, so its self-test genuinely passes
# rather than being scripted to -- and the checksum stub (unset
# BAIZE_STUB_SHA256SUMS) hashes exactly what gets served, so it verifies
# too.
use_real_binary_as_candidate() {
  export BAIZE_STUB_BAIZE_CONTENT
  BAIZE_STUB_BAIZE_CONTENT="$(cat "$BAIZE_BIN")"
}

# --- Already latest / --force ------------------------------------------------

@test "已是最新版時,不下載,印出 already on latest,exit 0" {
  install_fake_binary
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.1.0"}'
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already on 0.1.0"* ]]
  grep -q 'releases/latest' "$BAIZE_STUB_CURL_LOG"
  ! grep -q 'releases/download' "$BAIZE_STUB_CURL_LOG"
}

@test "--force 時即使同版本也重裝" {
  install_fake_binary
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.1.0"}'
  use_real_binary_as_candidate
  run "$BAIZE_BIN" update --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated baize"* ]]
  [ -f "$HOME/.local/bin/baize.prev" ]
}

@test "BAIZE_VERSION=v0.1.0 時不打 API" {
  install_fake_binary
  export BAIZE_VERSION="v0.1.0"
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already on 0.1.0"* ]]
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]
}

# --- Verification gates -------------------------------------------------------

@test "checksum 不符時,exit 非零,且現有的 baize 原封不動" {
  install_fake_binary
  local before; before="$(sha "$HOME/.local/bin/baize")"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  baize\n'
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum verification FAILED"* ]]
  [ "$(sha "$HOME/.local/bin/baize")" = "$before" ]
  [ ! -f "$HOME/.local/bin/baize.prev" ]
}

@test "SHA256SUMS 沒列出 baize 時,拒絕更新(空過關陷阱)" {
  install_fake_binary
  local before; before="$(sha "$HOME/.local/bin/baize")"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  some-other-file\n'
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not list baize"* ]]
  [ "$(sha "$HOME/.local/bin/baize")" = "$before" ]
  [ ! -f "$HOME/.local/bin/baize.prev" ]
}

@test "新版 self-test 失敗(check 回非零)時,不做 swap,現有版本仍在" {
  install_fake_binary
  local before; before="$(sha "$HOME/.local/bin/baize")"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  export BAIZE_STUB_BAIZE_CONTENT
  BAIZE_STUB_BAIZE_CONTENT="$(fake_candidate_content 'baize 0.2.0' 1)"
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  [[ "$output" == *"self-test"* ]]
  [ "$(sha "$HOME/.local/bin/baize")" = "$before" ]
  [ ! -f "$HOME/.local/bin/baize.prev" ]
}

@test "swap 後 version 失敗時,從 .prev 回滾,且回滾後的檔案內容等於原本的" {
  install_fake_binary
  local before; before="$(sha "$HOME/.local/bin/baize")"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'

  # `version` succeeds the first time it is called (the pre-swap
  # self-test) and fails every time after (the post-swap check) -- the
  # candidate is genuinely a single file, so the only way to tell those two
  # calls apart is which one happens first.
  local version_calls="$TEST_TMP/version_calls"
  : > "$version_calls"
  export BAIZE_STUB_BAIZE_CONTENT
  BAIZE_STUB_BAIZE_CONTENT="$(cat <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "version" ]]; then
  echo x >> "$version_calls"
  n=\$(wc -l < "$version_calls" | tr -d ' ')
  if [[ "\$n" -eq 1 ]]; then
    printf 'baize 0.2.0\n'
    exit 0
  fi
  exit 1
fi
[[ "\$1" == "check" ]] && exit 0
exit 0
EOF
)"

  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  [[ "$output" == *"rolled back"* ]]
  [ "$(sha "$HOME/.local/bin/baize")" = "$before" ]
}

# --- Success path -------------------------------------------------------------

@test "成功更新後,baize.prev 存在且內容是舊版" {
  install_fake_binary
  local before; before="$(sha "$HOME/.local/bin/baize")"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  use_real_binary_as_candidate
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/baize.prev" ]
  [ "$(sha "$HOME/.local/bin/baize.prev")" = "$before" ]
}

@test "更新後 config 檔的內容與 digest 完全不變" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  local cfg="$HOME/.config/baize/config"
  local before_content before_sha
  before_content="$(cat "$cfg")"
  before_sha="$(sha "$cfg")"

  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  use_real_binary_as_candidate
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  [ "$(sha "$cfg")" = "$before_sha" ]
  [ "$(cat "$cfg")" = "$before_content" ]
}

@test "更新後 crontab -l 完全不變" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  cp "$HOME/.crontab_stub" "$TEST_TMP/before_crontab"

  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  use_real_binary_as_candidate
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  run cmp "$TEST_TMP/before_crontab" "$HOME/.crontab_stub"
  [ "$status" -eq 0 ]
}

# --- Release resolution failure modes, through the verb ----------------------

@test "releases API 失敗時報錯,不 fallback 到 main" {
  install_fake_binary
  export BAIZE_STUB_CURL_RELEASES_FAIL=1
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  ! grep -q 'download/main/' "$BAIZE_STUB_CURL_LOG"
  ! grep -q 'releases/download' "$BAIZE_STUB_CURL_LOG"
}

@test "API 回傳無法解析時報錯,而非用空字串組出爛 URL" {
  install_fake_binary
  export BAIZE_STUB_RELEASES_JSON='not json at all'
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  ! grep -q 'releases/download//' "$BAIZE_STUB_CURL_LOG"
}

# --- Same-filesystem guard -----------------------------------------------------

@test "same_device: 相同 device id 視為同一個 filesystem" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run same_device "16777229" "16777229"
  [ "$status" -eq 0 ]
}

@test "same_device: 不同 device id 視為不同 filesystem" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run same_device "16777229" "1"
  [ "$status" -ne 0 ]
}

@test "fs_device_id: 同一個安裝目錄底下,新建的暫存目錄和它自己回報相同 device id" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$HOME/.local/bin"
  local sub; sub="$(mktemp -d "$HOME/.local/bin/.baize-update.XXXXXX")"
  local a b
  a="$(fs_device_id "$HOME/.local/bin")"
  b="$(fs_device_id "$sub")"
  rm -rf "$sub"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

# --- Cleanup ---------------------------------------------------------------

@test "暫存目錄在成功路徑被清掉,~/.local/bin 底下沒有殘留的 .baize-update.*" {
  install_fake_binary
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  use_real_binary_as_candidate
  run "$BAIZE_BIN" update
  [ "$status" -eq 0 ]
  [ -z "$(leftover_tmp_dirs)" ]
}

@test "暫存目錄在失敗路徑也被清掉" {
  install_fake_binary
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.2.0"}'
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  baize\n'
  run "$BAIZE_BIN" update
  [ "$status" -ne 0 ]
  [ -z "$(leftover_tmp_dirs)" ]
}
