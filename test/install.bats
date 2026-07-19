load 'helpers/setup'

# Portable file-mode reader: GNU stat on Linux CI, BSD stat on a dev Mac.
file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

DSN_OK='https://abc123@glitchtip.example.com/7'

# --- config: presence, permissions, merge order --------------------------

@test "第一次安裝時，--dsn 缺席就報錯 exit 非零" {
  run "$BAIZE_BIN" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"--dsn"* ]]
  [ ! -e "$HOME/.config/baize/config" ]
}

@test "--dsn 寫進 config，權限是 600，config 目錄是 700" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/baize/config" ]
  [ "$(file_mode "$HOME/.config/baize/config")" = "600" ]
  [ "$(file_mode "$HOME/.config/baize")" = "700" ]
  grep -q "DSN=\"$DSN_OK\"" "$HOME/.config/baize/config"
}

@test "--hostname 寫進 config 的 SERVER_NAME" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK" --hostname web-2
  [ "$status" -eq 0 ]
  grep -q 'SERVER_NAME="web-2"' "$HOME/.config/baize/config"
}

@test "重裝時不給 --hostname，既有 SERVER_NAME 保留" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --hostname web-1
  run "$BAIZE_BIN" install --threshold 90
  [ "$status" -eq 0 ]
  grep -q 'SERVER_NAME="web-1"' "$HOME/.config/baize/config"
}

@test "重裝時只給 --threshold 90，DSN、MOUNTS、HEARTBEAT_URL 全部保留" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --heartbeat 'https://hb.example/x'
  run "$BAIZE_BIN" install --threshold 90
  [ "$status" -eq 0 ]

  local cfg="$HOME/.config/baize/config"
  grep -q "DSN=\"$DSN_OK\"" "$cfg"
  grep -q 'MOUNTS="/"' "$cfg"
  grep -q 'HEARTBEAT_URL="https://hb.example/x"' "$cfg"
  grep -q 'THRESHOLD=90' "$cfg"
}

@test "合併：只給新 heartbeat 再重裝 threshold，兩者都保留在 config 裡" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --heartbeat 'https://hb.example/x'
  "$BAIZE_BIN" install --threshold 90
  grep -q 'https://hb.example/x' "$HOME/.config/baize/config"
}

@test "重裝不會產生重複的 key" {
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  "$BAIZE_BIN" install --threshold 42
  "$BAIZE_BIN" install --heartbeat 'https://hb.example/y'

  local cfg="$HOME/.config/baize/config"
  [ "$(grep -c '^DSN=' "$cfg")" -eq 1 ]
  [ "$(grep -c '^THRESHOLD=' "$cfg")" -eq 1 ]
  [ "$(grep -c '^HEARTBEAT_URL=' "$cfg")" -eq 1 ]
  [ "$(grep -c '^MOUNTS=' "$cfg")" -eq 1 ]
  [ "$(grep -c '^INTERVAL=' "$cfg")" -eq 1 ]
}

@test "寫出的 config 帶註解，且可以被 load_config 直接 source" {
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  grep -q '^#' "$HOME/.config/baize/config"

  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ "$DSN" = "$DSN_OK" ]
}

@test "門檻 0、100、abc 都被拒絕" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK" --threshold 0
  [ "$status" -ne 0 ]

  run "$BAIZE_BIN" install --dsn "$DSN_OK" --threshold 100
  [ "$status" -ne 0 ]

  run "$BAIZE_BIN" install --dsn "$DSN_OK" --threshold abc
  [ "$status" -ne 0 ]
}

@test "格式錯誤的 DSN 被拒絕" {
  run "$BAIZE_BIN" install --dsn 'not-a-dsn'
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.config/baize/config" ]
}

@test "未知旗標 exit 2 並列出合法旗標" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK" --bogus foo
  [ "$status" -eq 2 ]
  [[ "$output" == *"--dsn"* ]]
}

# --- cron: marker block ----------------------------------------------------

@test "空 crontab 安裝後，恰好有一個 baize block，且開頭沒有多餘的空行" {
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  local out; out="$(crontab -l)"
  [ "$(printf '%s\n' "$out" | grep -c '^# BEGIN baize$')" -eq 1 ]
  [ "$(printf '%s\n' "$out" | head -n1)" = "# BEGIN baize" ]
}

@test "裝兩次後，仍然恰好有一個 baize block" {
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  [ "$(crontab -l | grep -c '^# BEGIN baize$')" -eq 1 ]
}

@test "使用者原有的 cron 行在安裝後原封不動、順序不變" {
  printf '0 3 * * * /usr/bin/backup\n30 4 * * * /usr/bin/other\n' | crontab -
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  local out; out="$(crontab -l)"
  [ "$(printf '%s\n' "$out" | sed -n '1p')" = "0 3 * * * /usr/bin/backup" ]
  [ "$(printf '%s\n' "$out" | sed -n '2p')" = "30 4 * * * /usr/bin/other" ]
}

@test "使用者自己排版用的空行在安裝後仍然存在" {
  printf '0 3 * * * /usr/bin/backup\n\n# a note\n30 4 * * * /usr/bin/other\n' | crontab -
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  local out; out="$(crontab -l)"
  local before_block; before_block="$(printf '%s\n' "$out" | sed -n '1,4p')"
  local expected; expected=$'0 3 * * * /usr/bin/backup\n\n# a note\n30 4 * * * /usr/bin/other'
  [ "$before_block" = "$expected" ]
}

@test "改 --interval 1h 後，block 被取代而非新增，且內容是 0 * * * *" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --interval 15m
  "$BAIZE_BIN" install --interval 1h
  local out; out="$(crontab -l)"
  [ "$(printf '%s\n' "$out" | grep -c '^# BEGIN baize$')" -eq 1 ]
  [[ "$out" == *"0 * * * * $HOME/.local/bin/baize run"* ]]
}

@test "cron 行用的是展開後的絕對路徑" {
  "$BAIZE_BIN" install --dsn "$DSN_OK"
  local out; out="$(crontab -l)"
  [[ "$out" != *'$HOME'* ]]
  [[ "$out" == *"$HOME/.local/bin/baize run"* ]]
}

# --- interval parsing (unit-level) -----------------------------------------

@test "15m -> */15 * * * *；1h -> 0 * * * *；6h -> 0 */6 * * *" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run cron_schedule_from_interval 15m
  [ "$status" -eq 0 ]
  [ "$output" = "*/15 * * * *" ]

  run cron_schedule_from_interval 1h
  [ "$status" -eq 0 ]
  [ "$output" = "0 * * * *" ]

  run cron_schedule_from_interval 6h
  [ "$status" -eq 0 ]
  [ "$output" = "0 */6 * * *" ]
}

@test "7m、5s、0m、90m 都被拒絕且錯誤訊息列出可接受的值" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  for bad in 7m 5s 0m 90m; do
    run cron_schedule_from_interval "$bad"
    [ "$status" -ne 0 ]
    [[ "$output" == *"1 2 3 4 5 6 10 12 15 20 30"* ]]
    [[ "$output" == *"1 2 3 4 6 8 12"* ]]
  done
}

@test "格式錯誤的 --interval 在 install 時被拒絕" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK" --interval 7m
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/.config/baize/config" ]
}

# --- --dry-run ---------------------------------------------------------------

@test "dry-run 印出 config 內容和 cron 行，且什麼都不寫" {
  run "$BAIZE_BIN" install --dsn "$DSN_OK" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DSN=\"$DSN_OK\""* ]]
  [[ "$output" == *"*/15 * * * * $HOME/.local/bin/baize run"* ]]
}

@test "dry-run 時 config 檔沒有被建立" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --dry-run
  [ ! -e "$HOME/.config/baize/config" ]
  [ ! -e "$HOME/.config/baize" ]
}

@test "dry-run 時 crontab 完全沒有被呼叫寫入" {
  "$BAIZE_BIN" install --dsn "$DSN_OK" --dry-run
  [ ! -e "$HOME/.crontab_stub" ]
}
