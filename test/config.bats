load 'helpers/setup'

@test "沒有 config 檔時，使用內建預設值" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ "$MOUNTS" = "/" ]
  [ "$THRESHOLD" = "85" ]
  [ "$RESTATE_HOURS" = "24" ]
  [ "$DSN" = "" ]
  [ "$HEARTBEAT_URL" = "" ]
}

@test "config 檔存在時覆寫預設值" {
  write_config 'DSN="https://key@glitchtip.example.com/7"' 'MOUNTS="/ /data"' 'THRESHOLD=90' 'RESTATE_HOURS=6' 'HEARTBEAT_URL="https://hb.example/x"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ "$DSN" = "https://key@glitchtip.example.com/7" ]
  [ "$MOUNTS" = "/ /data" ]
  [ "$THRESHOLD" = "90" ]
  [ "$RESTATE_HOURS" = "6" ]
  [ "$HEARTBEAT_URL" = "https://hb.example/x" ]
}

@test "config 只設定部分 key 時，其餘維持預設" {
  write_config 'THRESHOLD=95'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ "$THRESHOLD" = "95" ]
  [ "$MOUNTS" = "/" ]
  [ "$RESTATE_HOURS" = "24" ]
  [ "$DSN" = "" ]
}

@test "XDG_CONFIG_HOME 設定時，config 路徑跟著改變" {
  export XDG_CONFIG_HOME="$TEST_TMP/xdg-config"
  mkdir -p "$XDG_CONFIG_HOME/baize"
  printf 'THRESHOLD=77\n' > "$XDG_CONFIG_HOME/baize/config"
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  [ "$(config_file)" = "$XDG_CONFIG_HOME/baize/config" ]
  load_config
  [ "$THRESHOLD" = "77" ]
}

@test "state 路徑也依 XDG_STATE_HOME 改變，預設落在 ~/.local/state" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  [ "$(state_dir)" = "$HOME/.local/state/baize" ]
  export XDG_STATE_HOME="$TEST_TMP/xdg-state"
  [ "$(state_dir)" = "$XDG_STATE_HOME/baize" ]
}

@test "require_dsn 在 DSN 為空時回傳非零並在 stderr 提到 baize install" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  run require_dsn
  [ "$status" -ne 0 ]
  [[ "$output" == *"baize install"* ]]
}

@test "require_dsn 在 DSN 有值時回傳零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  DSN="https://key@glitchtip.example.com/7"
  run require_dsn
  [ "$status" -eq 0 ]
}

@test "baize version 印出版本且 exit 0" {
  run "$BAIZE_BIN" version
  [ "$status" -eq 0 ]
  [ "$output" = "baize 0.1.1" ]
}

@test "baize help 印出用法且 exit 0" {
  run "$BAIZE_BIN" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"baize install"* ]]
  [[ "$output" == *"baize version"* ]]
}

@test "不帶動詞的 baize 印出用法且 exit 0" {
  run "$BAIZE_BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"baize install"* ]]
}

@test "未知動詞 exit 2 並在 stderr 印出錯誤" {
  run "$BAIZE_BIN" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command: bogus"* ]]
}

@test "BAIZE_LIB_ONLY=1 source baize 不執行任何動詞" {
  run bash -c 'BAIZE_LIB_ONLY=1 source "'"$BAIZE_BIN"'" && echo sourced-ok'
  [ "$status" -eq 0 ]
  [ "$output" = "sourced-ok" ]
}

@test "每個 cmd_* 動詞都已定義為函式" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  for cmd in cmd_install cmd_remove cmd_check cmd_run cmd_test cmd_status cmd_update; do
    declare -F "$cmd" >/dev/null || { printf 'missing verb: %s\n' "$cmd"; return 1; }
  done
}

@test "server_name 印出非空字串" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run server_name
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "server_name 在 hostname 完全失敗時仍印出 unknown" {
  run bash -c '
    hostname() { return 1; }
    BAIZE_LIB_ONLY=1 source "'"$BAIZE_BIN"'"
    server_name
  '
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "SERVER_NAME 設定時,server_name 印出該值而非系統 hostname" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  SERVER_NAME="web-2"
  run server_name
  [ "$status" -eq 0 ]
  [ "$output" = "web-2" ]
}

@test "SERVER_NAME 為空時,server_name fall back 到系統 hostname" {
  run bash -c '
    hostname() { printf "real-host\n"; }
    BAIZE_LIB_ONLY=1 source "'"$BAIZE_BIN"'"
    SERVER_NAME=""
    server_name
  '
  [ "$status" -eq 0 ]
  [ "$output" = "real-host" ]
}

@test "load_config 預設 SERVER_NAME 為空" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ -z "$SERVER_NAME" ]
}

@test "config 設定 SERVER_NAME 時 load_config 讀入,server_name 用它" {
  write_config 'DSN="https://k@glitchtip.example.com/7"' 'SERVER_NAME="web-1"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  load_config
  [ "$SERVER_NAME" = "web-1" ]
  run server_name
  [ "$output" = "web-1" ]
}

@test "epoch_to_rfc3339 1752710400 印出正確的 UTC 字串" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run epoch_to_rfc3339 1752710400
  [ "$status" -eq 0 ]
  [ "$output" = "2025-07-17T00:00:00Z" ]
}

@test "TZ=Asia/Taipei 不影響 epoch_to_rfc3339 的輸出" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  TZ="Asia/Taipei" run epoch_to_rfc3339 1752710400
  [ "$status" -eq 0 ]
  [ "$output" = "2025-07-17T00:00:00Z" ]
}

@test "不帶參數的 epoch_to_rfc3339 跟著 BAIZE_STUB_NOW 走" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_NOW=1752710400
  run epoch_to_rfc3339
  [ "$status" -eq 0 ]
  [ "$output" = "2025-07-17T00:00:00Z" ]
}
