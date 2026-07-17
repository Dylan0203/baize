load 'helpers/setup'

DSN_OK='https://abc123@glitchtip.example.com/7'

# --- Redaction -----------------------------------------------------------

@test "DSN key 被遮蔽為 ***,host 和 project id 仍可見" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://***@glitchtip.example.com/7"* ]]
  [[ "$output" != *"abc123"* ]]
}

@test "HEARTBEAT_URL 的完整內容不出現在輸出中的任何地方" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  local hb='https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/deadbeef-1234-5678-9abc-def012345678/'
  cmd_install --dsn "$DSN_OK" --heartbeat "$hb" >/dev/null
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" != *"$hb"* ]]
  [[ "$output" != *"deadbeef-1234-5678-9abc-def012345678"* ]]
}

@test "HEARTBEAT_URL 有設定時顯示 configured,未設定時顯示 not configured" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  run cmd_status
  [[ "$output" == *"HEARTBEAT  not configured"* ]]

  cmd_install --heartbeat 'https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/uuid/' >/dev/null
  run cmd_status
  [[ "$output" == *"HEARTBEAT  configured"* ]]
}

# --- Config header ---------------------------------------------------------

@test "config 路徑顯示為 ~/... 的縮寫,而非展開成真正登入使用者的家目錄" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Config     ~/.config/baize/config"* ]]
}

# --- Cron state ------------------------------------------------------------

@test "cron block 存在時顯示排程和 active" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" --interval 15m >/dev/null
  run cmd_status
  [[ "$output" == *"Cron       */15 * * * *  (active)"* ]]
}

@test "cron block 不存在時顯著顯示 NOT SCHEDULED" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  printf '' | crontab -
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT SCHEDULED"* ]]
}

@test "crontab 完全為空時也不會炸" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  rm -f "$HOME/.crontab_stub"
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT SCHEDULED"* ]]
}

# --- Last alert --------------------------------------------------------------

@test "state 檔沒有任何 last_sent 時,Last alert 顯示 never" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Last alert never"* ]]
}

@test "有 last_sent 時顯示時間戳,標籤是 Last alert 而不是 Last run" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  mkdir -p "$(state_dir)"
  write_state "/" breach 1700000000
  export BAIZE_STUB_NOW=1700003600
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Last alert 2023-11-14 22:13:20 UTC"* ]]
  [[ "$output" != *"Last run"* ]]
}

# --- Update check --------------------------------------------------------------

@test "有新版時顯示 update available: vX.Y.Z" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v9.9.9"}'
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"update available: 9.9.9"* ]]
}

@test "已是最新版時不顯示 update available" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v0.1.0"}'
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" != *"update available"* ]]
}

@test "網路失敗時仍 exit 0,顯示 update check unavailable,且 config / cron / disk 全部照常印出" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  export BAIZE_STUB_CURL_EXIT=1
  run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"update check unavailable"* ]]
  [[ "$output" != *"update available"* ]]
  [[ "$output" == *"Config"* ]]
  [[ "$output" == *"Cron"* ]]
  [[ "$output" == *"Disk"* ]]
}

# --- Disk ----------------------------------------------------------------------

@test "磁碟使用率超過門檻時標記 OVER" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" --threshold 85 >/dev/null
  BAIZE_STUB_DF_PCT=90 run cmd_status
  [ "$status" -eq 0 ]
  [[ "$output" == *"90%  OVER"* ]]
}

# --- No side effects -------------------------------------------------------

@test "status 完全不呼叫 curl 以外的網路,且不送任何事件(curl log 只有 releases API 那一筆)" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null
  run cmd_status
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BAIZE_STUB_CURL_LOG" | tr -d ' ')" = "1" ]
  grep -q 'releases/latest' "$BAIZE_STUB_CURL_LOG"
}

@test "status 不寫入 ~/.local/bin(執行前後 digest 相同)" {
  mkdir -p "$HOME/.local/bin"
  cp "$BAIZE_BIN" "$HOME/.local/bin/baize"
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  cmd_install --dsn "$DSN_OK" >/dev/null

  local before after
  before="$(sha256sum "$HOME/.local/bin/baize" | cut -d' ' -f1)"
  run "$BAIZE_BIN" status
  [ "$status" -eq 0 ]
  after="$(sha256sum "$HOME/.local/bin/baize" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
}

# --- No config -------------------------------------------------------------

@test "沒有 config 時 exit 非零並提示 baize install" {
  run "$BAIZE_BIN" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"baize install"* ]]
}
