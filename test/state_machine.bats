load 'helpers/setup'

# --- decide_action: the four transitions ------------------------------------

@test "ok 且 80%（低於門檻）→ none" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 80 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "ok 且 90%（超過門檻）→ breach" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 90 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "breach" ]
}

@test "breach 且 90%、剛送過 → none（不洗頻）" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 90 85 breach 1000000 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "breach 且 90%、8 小時前送過 → none" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  local last=1000000 now=$((1000000 + 8 * 3600))
  run decide_action 90 85 breach "$last" "$now" 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "breach 且 90%、25 小時前送過 → restate" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  local last=1000000 now=$((1000000 + 25 * 3600))
  run decide_action 90 85 breach "$last" "$now" 24
  [ "$status" -eq 0 ]
  [ "$output" = "restate" ]
}

@test "breach 且 80%（低於門檻）→ recovery" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 80 85 breach 1000000 1000010 24
  [ "$status" -eq 0 ]
  [ "$output" = "recovery" ]
}

@test "ok 且 80%、last_sent 為 0 → none" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 80 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

# --- Boundaries ---------------------------------------------------------------

@test "恰好 85%（等於門檻）→ breach" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 85 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "breach" ]
}

@test "84%（低於門檻一個百分點）→ none" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 84 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "恰好 24 小時（86400 秒）→ restate" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 90 85 breach 0 86400 24
  [ "$status" -eq 0 ]
  [ "$output" = "restate" ]
}

@test "86399 秒（差 1 秒不到 24 小時）→ none" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 90 85 breach 0 86399 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "THRESHOLD=90 時 85% → none（門檻確實可設定）" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 85 90 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "0% 不會炸" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 0 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "100% 不會炸" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run decide_action 100 85 ok 0 1000000 24
  [ "$status" -eq 0 ]
  [ "$output" = "breach" ]
}

# --- State file: read_state ----------------------------------------------------

@test "沒有 state 檔時，read_state 回 ok 0" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run read_state "/"
  [ "$status" -eq 0 ]
  [ "$output" = "ok 0" ]
}

@test "state 檔存在但沒有這個 mount 時，read_state 回 ok 0" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$(state_dir)"
  printf '/data breach 1700000000\n' > "$(state_file)"
  run read_state "/"
  [ "$status" -eq 0 ]
  [ "$output" = "ok 0" ]
}

@test "state 檔有這個 mount 時，read_state 回它的 level 和 last_sent" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$(state_dir)"
  printf '/ breach 1700000000\n/data ok 0\n' > "$(state_file)"
  run read_state "/"
  [ "$status" -eq 0 ]
  [ "$output" = "breach 1700000000" ]
}

# --- State file: write_state ----------------------------------------------------

@test "write_state 建立 state 檔並寫入一行" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run write_state "/" breach 1700000000
  [ "$status" -eq 0 ]
  [ "$(cat "$(state_file)")" = "/ breach 1700000000" ]
}

@test "write_state 更新一個 mount 時，另一個 mount 的那行原封不動" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  write_state "/" breach 1700000000
  write_state "/data" ok 0
  run write_state "/" ok 0
  [ "$status" -eq 0 ]
  run read_state "/"
  [ "$output" = "ok 0" ]
  run read_state "/data"
  [ "$output" = "ok 0" ]
}

@test "write_state 覆寫同一個 mount 不會產生重複行" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  write_state "/" breach 1700000000
  write_state "/" breach 1700003600
  run bash -c 'grep -c "^/ " "'"$(state_file)"'"'
  [ "$output" = "1" ]
}

@test "state 目錄無法寫入時，write_state 回傳 0 並在 stderr 警告" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$HOME/.local/state"
  chmod 500 "$HOME/.local/state"
  run write_state "/" breach 1700000000
  chmod 700 "$HOME/.local/state"
  [ "$status" -eq 0 ]
  [[ "$output" == *"state"* ]]
}

# --- Simulated week: no-spam requirement, proven ------------------------------

@test "模擬一週：88% 持續 672 次執行，恰好 1 次 breach 與 6 次 restate" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  mkdir -p "$(state_dir)"

  local threshold=85 restate_hours=24 pct=88
  local mount="/"
  local now=0 level last_sent action
  local breach_count=0 restate_count=0 none_count=0

  level="ok"
  last_sent=0

  for ((i = 0; i < 672; i++)); do
    now=$((i * 900))
    action="$(decide_action "$pct" "$threshold" "$level" "$last_sent" "$now" "$restate_hours")"
    case "$action" in
      breach)
        breach_count=$((breach_count + 1))
        level="breach"
        last_sent="$now"
        ;;
      restate)
        restate_count=$((restate_count + 1))
        level="breach"
        last_sent="$now"
        ;;
      recovery)
        level="ok"
        last_sent=0
        ;;
      none)
        none_count=$((none_count + 1))
        ;;
    esac
  done

  [ "$breach_count" -eq 1 ]
  [ "$restate_count" -eq 6 ]
  [ "$none_count" -eq 665 ]
}
