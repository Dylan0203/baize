load 'helpers/setup'

DSN_OK='https://abc123@glitchtip.example.com/7'

# Simulates install.sh having placed the binary -- `baize install` itself
# never copies the script to bin_path, that is the bootstrapper's job.
install_fake_binary() {
  mkdir -p "$HOME/.local/bin"
  cp "$BAIZE_BIN" "$HOME/.local/bin/baize"
}

# --- teardown: files and crontab --------------------------------------------

@test "移除後,crontab 的 baize block 消失" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ "$(crontab -l | grep -c '^# BEGIN baize$')" -eq 0 ]
}

@test "使用者原有的 cron 行原封不動(byte-for-byte)" {
  printf '0 3 * * * /usr/bin/backup\n30 4 * * * /usr/bin/other\n' | crontab -
  cp "$HOME/.crontab_stub" "$TEST_TMP/before_crontab"
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  "$BAIZE_BIN" remove --force
  run cmp "$TEST_TMP/before_crontab" "$HOME/.crontab_stub"
  [ "$status" -eq 0 ]
}

@test "只有 baize block 的 crontab,移除後恰好是空的" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  "$BAIZE_BIN" remove --force
  local out; out="$(crontab -l)"
  [ -z "$out" ]
}

@test "~/.local/bin/baize、config 目錄、state 目錄都消失" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/baize" ]
  [ ! -d "$HOME/.config/baize" ]
  [ ! -d "$HOME/.local/state/baize" ]
}

@test "baize.prev 存在時,移除後也消失" {
  install_fake_binary
  cp "$BAIZE_BIN" "$HOME/.local/bin/baize.prev"
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/baize.prev" ]
}

@test "--keep-config 時 config 保留,其餘照樣移除" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force --keep-config
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/baize/config" ]
  grep -q "DSN=\"$DSN_OK\"" "$HOME/.config/baize/config"
  [ ! -e "$HOME/.local/bin/baize" ]
  [ ! -d "$HOME/.local/state/baize" ]
  [ "$(crontab -l | grep -c '^# BEGIN baize$')" -eq 0 ]
}

# --- farewell event ----------------------------------------------------------

@test "移除時送出一個 baize-removed 事件,level 是 info" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ -s "$BAIZE_STUB_CURL_STDIN" ]
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"level":"info"'* ]]
}

@test "farewell 事件的 fingerprint prefix 是 baize-removed,不是 disk-breach" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  "$BAIZE_BIN" remove --force
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"fingerprint":["baize-removed"'* ]]
  [[ "$body" != *'"fingerprint":["disk-breach"'* ]]
}

# --- the sharp edge: farewell must never block removal -----------------------

@test "curl 失敗時,移除照樣完成且 exit 0" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  export BAIZE_STUB_CURL_EXIT=1
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/baize" ]
  [ ! -d "$HOME/.config/baize" ]
  [ ! -d "$HOME/.local/state/baize" ]
}

@test "沒有設定 DSN 時,移除照樣完成且 exit 0,也不呼叫 curl" {
  install_fake_binary
  write_config 'DSN=""' 'MOUNTS="/"'
  mkdir -p "$HOME/.local/state/baize"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]
  [ ! -e "$HOME/.local/bin/baize" ]
  [ ! -d "$HOME/.config/baize" ]
}

@test "config 檔損毀無法 source 時,移除照樣完成" {
  install_fake_binary
  mkdir -p "$HOME/.config/baize"
  printf 'this is not valid bash (((\n' > "$HOME/.config/baize/config"
  mkdir -p "$HOME/.local/state/baize"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/baize" ]
  [ ! -d "$HOME/.config/baize" ]
  [ ! -d "$HOME/.local/state/baize" ]
}

# --- idempotency ---------------------------------------------------------------

@test "什麼都沒裝時執行 remove,exit 0 並印出 nothing to remove" {
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}

@test "連續執行兩次 remove 都 exit 0" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
}

# --- confirmation prompt -------------------------------------------------------

@test "--force 時不提示,直接完成" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"Continue?"* ]]
}

@test "沒有 controlling terminal 又沒給 --force 時,exit 2 並提示用 --force" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove
  [ "$status" -eq 2 ]
  [[ "$output" == *"--force"* ]]
  # nothing was touched -- refusing to prompt must not fall through to teardown
  [ -e "$HOME/.local/bin/baize" ]
}

# --- manual follow-up ----------------------------------------------------------

@test "HEARTBEAT_URL 有設定時,印出 GlitchTip 手動提醒" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK" --heartbeat 'https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/uuid/'
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"Heartbeat monitor"* ]]
}

@test "HEARTBEAT_URL 未設定時,不印 GlitchTip 手動提醒" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"Heartbeat monitor"* ]]
}

# --- $HOME guard -----------------------------------------------------------

@test "HOME 為空字串時拒絕執行" {
  local saved_home="$HOME"
  HOME='' run "$BAIZE_BIN" remove --force
  HOME="$saved_home"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HOME"* ]]
}

# --- unknown flag ------------------------------------------------------------

@test "未知旗標 exit 2" {
  install_fake_binary
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  run "$BAIZE_BIN" remove --force --bogus
  [ "$status" -eq 2 ]
}
