load 'helpers/setup'

# --- cmd_check ---------------------------------------------------------------

@test "check 印出每個 mount 的百分比,超標時標記 OVER" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=90 run cmd_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"90%"* ]]
  [[ "$output" == *"OVER"* ]]
}

@test "check 低於門檻時標記 ok 而非 OVER" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=10 run cmd_check
  [ "$status" -eq 0 ]
  [[ "$output" == *"10%"* ]]
  [[ "$output" != *"OVER"* ]]
}

@test "check 完全不呼叫 curl(這個動詞的核心保證)" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=90 run cmd_check
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]
}

@test "check 沒有 DSN 也能跑,exit 0" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=10 run cmd_check
  [ "$status" -eq 0 ]
}

@test "check 超標時仍然 exit 0" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=99 run cmd_check
  [ "$status" -eq 0 ]
}

@test "check 所有 mount 都讀不到時 exit 1" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_EXIT=1 run cmd_check
  [ "$status" -eq 1 ]
}

# --- cmd_run: transitions ------------------------------------------------------

@test "run: ok 狀態下 90% 送出一個 disk-breach 事件,且 state 變成 breach <now>" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_NOW=1700000000

  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$BAIZE_STUB_CURL_LOG" | tr -d ' ')" = "1" ]
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"fingerprint":["disk-breach"'* ]]

  run read_state "/"
  [ "$output" = "breach 1700000000" ]
}

@test "run: 已經是 breach 且剛送過時,完全不送事件" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85' 'RESTATE_HOURS=24'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$(state_dir)"
  write_state "/" breach 1700000000
  export BAIZE_STUB_NOW=1700003600

  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]

  run read_state "/"
  [ "$output" = "breach 1700000000" ]
}

@test "run: breach 狀態下降到 80% 送出 disk-recovery 事件,且 state 變成 ok 0" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$(state_dir)"
  write_state "/" breach 1700000000
  export BAIZE_STUB_NOW=1700010000

  BAIZE_STUB_DF_PCT=80 run cmd_run
  [ "$status" -eq 0 ]

  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"fingerprint":["disk-recovery"'* ]]

  run read_state "/"
  [ "$output" = "ok 0" ]
}

@test "run: 送出失敗時 state 不變,exit 非零" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_NOW=1700000000
  export BAIZE_STUB_CURL_EXIT=1

  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -ne 0 ]

  run read_state "/"
  [ "$output" = "ok 0" ]
}

@test "run: 成功且無事可報時,stdout 完全空白(cron 不會寄信)" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  BAIZE_STUB_DF_PCT=10 run cmd_run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "run: 兩個 mount 各自獨立判斷,一個超標另一個沒有時只送一個事件" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/ /mnt/data"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_NOW=1700000000

  # shellcheck disable=SC2317  # invoked indirectly via each_mount_pct -> disk_used_pct
  df() {
    if [[ "${*: -1}" == "/mnt/data" ]]; then
      printf 'Filesystem     1024-blocks     Used Available Capacity Mounted on\n'
      printf '/dev/stub          10485760  1048576   9437184      10%% /mnt/data\n'
    else
      command df "$@"
    fi
  }
  export -f df

  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BAIZE_STUB_CURL_LOG" | tr -d ' ')" = "1" ]

  run read_state "/"
  [ "$output" = "breach 1700000000" ]
  run read_state "/mnt/data"
  [ "$output" = "ok 0" ]
}

# --- cmd_run: heartbeat ---------------------------------------------------------

@test "run: HEARTBEAT_URL 有設定時,每次 run 都 POST 一次" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85' \
    'HEARTBEAT_URL="https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/uuid/"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  BAIZE_STUB_DF_PCT=10 run cmd_run
  [ "$status" -eq 0 ]

  run cat "$BAIZE_STUB_CURL_LOG"
  [[ "$output" == *"heartbeat_check/uuid"* ]]
}

@test "run: HEARTBEAT_URL 未設定時,不 POST 也不警告" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  BAIZE_STUB_DF_PCT=10 run cmd_run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]
}

@test "run: heartbeat 失敗時仍完成前面的告警工作(先送事件再 heartbeat),run 不因此失敗" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85' \
    'HEARTBEAT_URL="https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/uuid/"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_NOW=1700000000

  # Fail only the heartbeat POST; the disk-breach POST (a different URL)
  # goes through the real stub untouched, so a passing send is provably
  # what wrote the breach state below.
  # shellcheck disable=SC2317  # invoked indirectly via http_post -> curl
  curl() {
    local url="${*: -1}"
    if [[ "$url" == *"heartbeat_check"* ]]; then
      return 1
    fi
    command curl "$@"
  }
  export -f curl

  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"heartbeat check-in failed"* ]]

  run read_state "/"
  [ "$output" = "breach 1700000000" ]
}

@test "run: 所有 mount 都讀不到時 exit 1,但仍然送出 heartbeat" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85' \
    'HEARTBEAT_URL="https://glitchtip.example.com/api/0/organizations/x/heartbeat_check/uuid/"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  BAIZE_STUB_DF_EXIT=1 run cmd_run
  [ "$status" -ne 0 ]

  run cat "$BAIZE_STUB_CURL_LOG"
  [[ "$output" == *"heartbeat_check/uuid"* ]]
}

# --- cmd_run: DSN / lifecycle ----------------------------------------------------

@test "run: 沒有 DSN 時 exit 1 並提到 baize install" {
  write_config 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  run cmd_run
  [ "$status" -ne 0 ]
  [[ "$output" == *"baize install"* ]]
}

@test "run: 完整生命週期 — 90% 一次 breach、重複 90% 不送、80% 一次 recovery、重複 80% 不送,總共兩個事件" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"' 'MOUNTS="/"' 'THRESHOLD=85'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"

  export BAIZE_STUB_NOW=1700000000
  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]

  export BAIZE_STUB_NOW=1700000900
  BAIZE_STUB_DF_PCT=90 run cmd_run
  [ "$status" -eq 0 ]

  export BAIZE_STUB_NOW=1700001800
  BAIZE_STUB_DF_PCT=80 run cmd_run
  [ "$status" -eq 0 ]

  export BAIZE_STUB_NOW=1700002700
  BAIZE_STUB_DF_PCT=80 run cmd_run
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$BAIZE_STUB_CURL_LOG" | tr -d ' ')" = "2" ]
}
