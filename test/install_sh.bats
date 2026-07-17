load 'helpers/setup'

# install.sh is a separate file from baize itself -- these tests always
# invoke it as a subprocess via `bash install.sh ...`, never source it.
INSTALL_SH() { printf '%s\n' "$BAIZE_ROOT/install.sh"; }

@test "BAIZE_VERSION 設定時完全不打 releases API" {
  export BAIZE_VERSION="v0.9.9"
  run bash "$(INSTALL_SH)"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/baize" ]
  [ -x "$HOME/.local/bin/baize" ]
  ! grep -q 'releases/latest' "$BAIZE_STUB_CURL_LOG"
  grep -q 'download/v0.9.9/baize' "$BAIZE_STUB_CURL_LOG"
}

@test "未設定 BAIZE_VERSION 時，從 releases API 的 JSON 解出 tag_name" {
  run bash "$(INSTALL_SH)"
  [ "$status" -eq 0 ]
  grep -q 'releases/latest' "$BAIZE_STUB_CURL_LOG"
  grep -q 'download/v1.2.3/baize' "$BAIZE_STUB_CURL_LOG"
  [ -f "$HOME/.local/bin/baize" ]
}

@test "releases API 失敗時，報錯並 exit 非零，絕不 fallback 到 main" {
  export BAIZE_STUB_CURL_RELEASES_FAIL=1
  run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  ! grep -q 'download/main/' "$BAIZE_STUB_CURL_LOG"
  ! grep -q '/baize$' "$BAIZE_STUB_CURL_LOG"
  [ ! -e "$HOME/.local/bin/baize" ]
}

@test "API 回傳無法解析的 JSON 時，報錯而非用空字串組出爛 URL" {
  export BAIZE_STUB_RELEASES_JSON='not json at all'
  run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  # No download attempt with an empty version would look like a double
  # slash in the asset URL -- assert that never happened.
  ! grep -q 'releases/download//' "$BAIZE_STUB_CURL_LOG"
  [ ! -e "$HOME/.local/bin/baize" ]
}

@test "checksum 相符時，baize 被放進 \$HOME/.local/bin 且可執行" {
  run bash "$(INSTALL_SH)"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/baize" ]
  [ -x "$HOME/.local/bin/baize" ]
}

@test "checksum 不符時，exit 非零，且 baize 不存在" {
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  baize\n'
  run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum verification FAILED"* ]]
  [ ! -e "$HOME/.local/bin/baize" ]
}

@test "SHA256SUMS 沒有列出 baize 時，exit 非零，擋掉 --ignore-missing 的空過關陷阱" {
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  some-other-file\n'
  run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not list baize"* ]]
  [ ! -e "$HOME/.local/bin/baize" ]
}

@test "以 root 執行時 exit 非零" {
  local fake_id_dir="$TEST_TMP/fake-id-bin"
  mkdir -p "$fake_id_dir"
  cat > "$fake_id_dir/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  printf '0\n'
  exit 0
fi
exec /usr/bin/id "$@"
EOF
  chmod +x "$fake_id_dir/id"

  PATH="$fake_id_dir:$PATH" run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not run as root"* ]]
  [ ! -e "$HOME/.local/bin/baize" ]
}

@test "--dsn X --threshold 90 原封不動傳給 baize install" {
  local log="$TEST_TMP/fake_baize_args.log"
  export BAIZE_STUB_BAIZE_CONTENT
  # hand_off invokes the placed binary as `baize install "$@"` -- shift off
  # the "install" verb so the log captures exactly what a real cmd_install
  # would see in its own "$@", i.e. the passed-through flags.
  BAIZE_STUB_BAIZE_CONTENT="$(printf '#!/usr/bin/env bash\nshift\nprintf "%%s\\n" "$@" > "%s"\n' "$log")"

  run bash "$(INSTALL_SH)" --dsn X --threshold 90
  [ "$status" -eq 0 ]
  [ -f "$log" ]
  run cat "$log"
  [ "${lines[0]}" = "--dsn" ]
  [ "${lines[1]}" = "X" ]
  [ "${lines[2]}" = "--threshold" ]
  [ "${lines[3]}" = "90" ]
}

@test "沒有帶參數時，仍呼叫 baize install（不帶參數）" {
  local log="$TEST_TMP/fake_baize_args_empty.log"
  export BAIZE_STUB_BAIZE_CONTENT
  BAIZE_STUB_BAIZE_CONTENT="$(printf '#!/usr/bin/env bash\nprintf "install-called\\n" > "%s"\n' "$log")"

  run bash "$(INSTALL_SH)"
  [ "$status" -eq 0 ]
  [ -f "$log" ]
  [ "$(cat "$log")" = "install-called" ]
}

@test "失敗時暫存目錄有被清掉" {
  local tmproot="$TEST_TMP/tmproot"
  mkdir -p "$tmproot"
  export TMPDIR="$tmproot"
  export BAIZE_STUB_SHA256SUMS=$'0000000000000000000000000000000000000000000000000000000000000000  baize\n'

  run bash "$(INSTALL_SH)"
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$tmproot")" ]
}

@test "\$HOME/.local/bin 不在 PATH 時，警告訊息包含要加的那行 export PATH" {
  local minimal_path="$BAIZE_ROOT/test/helpers/stubs:/usr/bin:/bin:/sbin:/usr/sbin"
  PATH="$minimal_path" run bash "$(INSTALL_SH)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/.local/bin"* ]]
  [[ "$output" == *"export PATH=\"$HOME/.local/bin:\$PATH\""* ]]
}

@test "script 裡沒有 jq、git、sudo" {
  ! grep -E 'jq|sudo|git ' "$(INSTALL_SH)"
}
