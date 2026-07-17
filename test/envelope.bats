load 'helpers/setup'

@test "parse_dsn 正確拆出 key / host / project id" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  parse_dsn "https://abc123@glitchtip.example.com/7"
  [ "$DSN_KEY" = "abc123" ]
  [ "$DSN_HOST" = "glitchtip.example.com" ]
  [ "$DSN_PROJECT" = "7" ]
}

@test "parse_dsn 對缺 @ 的 DSN 回傳非零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run parse_dsn "https://abc123glitchtip.example.com/7"
  [ "$status" -ne 0 ]
}

@test "parse_dsn 對缺 project id 的 DSN 回傳非零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run parse_dsn "https://abc123@glitchtip.example.com/"
  [ "$status" -ne 0 ]
}

@test "parse_dsn 對 project id 非數字的 DSN 回傳非零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run parse_dsn "https://abc123@glitchtip.example.com/seven"
  [ "$status" -ne 0 ]
}

@test "parse_dsn 拒絕 http:// (只接受 https://)" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run parse_dsn "http://abc123@glitchtip.example.com/7"
  [ "$status" -ne 0 ]
}

@test "設定 BAIZE_STUB_NOW 時，envelope 的 sent_at 和事件的 timestamp 都跟著它走" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  export BAIZE_STUB_NOW=1752710400
  send_event info Foo "bar" baize-test "-"
  run cat "$BAIZE_STUB_CURL_STDIN"
  [ "$status" -eq 0 ]
  local sent_at_line; sent_at_line="$(sed -n '1p' <<< "$output")"
  local event_line; event_line="$(sed -n '3p' <<< "$output")"
  [[ "$sent_at_line" == *'"sent_at":"2025-07-17T00:00:00Z"'* ]]
  [[ "$event_line" == *'"timestamp":"2025-07-17T00:00:00Z"'* ]]
}

@test "同一個事件的 sent_at 和 timestamp 一致" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event info Foo "bar" baize-test "-"
  local body; body="$(cat "$BAIZE_STUB_CURL_STDIN")"
  local sent_at; sent_at="$(sed -n '1p' <<< "$body" | grep -o '"sent_at":"[^"]*"')"
  local timestamp; timestamp="$(sed -n '3p' <<< "$body" | grep -o '"timestamp":"[^"]*"')"
  local sent_at_val="${sent_at#*:}"
  local timestamp_val="${timestamp#*:}"
  [ "$sent_at_val" = "$timestamp_val" ]
}

@test "new_event_id 產生 32 個小寫十六進位字元、不含 -" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run new_event_id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{32}$ ]]
}

@test "json_escape 正確處理雙引號、反斜線、換行" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run json_escape 'a"b\c'$'\n''d'
  [ "$status" -eq 0 ]
  [ "$output" = 'a\"b\\c\nd' ]
}

@test "envelope 是三行，且 event JSON 那行不含換行" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event info Foo "bar" baize-test "-"
  local lines; lines="$(wc -l < "$BAIZE_STUB_CURL_STDIN" | tr -d ' ')"
  [ "$lines" = "3" ]
}

@test "URL 帶 sentry_key，Content-Type 是 application/x-sentry-envelope" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event info Foo "bar" baize-test "-"
  run cat "$BAIZE_STUB_CURL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://glitchtip.example.com/api/7/envelope/?sentry_key=abc123"* ]]
  [[ "$output" == *"application/x-sentry-envelope"* ]]
}

@test "fingerprint 是 disk-breach / host / mount，且不含百分比" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event warning DiskUsageHigh "Disk usage 94% on / (threshold 85%)" disk-breach "/" '"used_pct":94'
  local host; host="$(server_name)"
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *"\"fingerprint\":[\"disk-breach\",\"$host\",\"/\"]"* ]]
  local fp; fp="$(printf '%s' "$body" | grep -o '"fingerprint":\[[^]]*\]')"
  [[ "$fp" != *"94"* ]]
}

@test "同一個 mount 兩次不同百分比的事件，fingerprint 完全相同" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"

  send_event warning DiskUsageHigh "Disk usage 88% on /" disk-breach "/" '"used_pct":88'
  local fp1; fp1="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN" | grep -o '"fingerprint":\[[^]]*\]')"

  send_event warning DiskUsageHigh "Disk usage 93% on /" disk-breach "/" '"used_pct":93'
  local fp2; fp2="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN" | grep -o '"fingerprint":\[[^]]*\]')"

  [ -n "$fp1" ]
  [ "$fp1" = "$fp2" ]
}

@test "事件用 exception 而非 message" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event info Foo "bar" baize-test "-"
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"exception":{"values":[{"type":"Foo","value":"bar"}]}'* ]]
  [[ "$body" != *'"message"'* ]]
}

@test "省略 extra_json 時，payload 完全沒有 extra 這個 key，且仍是合法 JSON" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event info Foo "bar" baize-test "-"
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" != *'"extra"'* ]]
  # matched-brace sanity check (poor man's JSON validity, no jq available)
  local opens; opens="$(printf '%s' "$body" | tr -cd '{' | wc -c | tr -d ' ')"
  local closes; closes="$(printf '%s' "$body" | tr -cd '}' | wc -c | tr -d ' ')"
  [ "$opens" = "$closes" ]
}

@test "帶 extra_json 時，extra 是合法的 JSON object" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  send_event warning DiskUsageHigh "bar" disk-breach "/" '"used_pct":88,"threshold_pct":85'
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"extra":{"used_pct":88,"threshold_pct":85}'* ]]
}

@test "curl 失敗時 send_event 回傳非零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  export BAIZE_STUB_CURL_EXIT=1
  run send_event info Foo "bar" baize-test "-"
  [ "$status" -ne 0 ]
}

@test "錯誤訊息不含 DSN key" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  DSN="https://abc123@glitchtip.example.com/7"
  export BAIZE_STUB_CURL_EXIT=1
  run send_event info Foo "bar" baize-test "-"
  [[ "$output" != *"abc123"* ]]
}

@test "cmd_test 在沒有 DSN 時失敗並提到 baize install" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run cmd_test
  [ "$status" -ne 0 ]
  [[ "$output" == *"baize install"* ]]
}

@test "cmd_test 有 DSN 時送出一個 baize-test 事件並回報成功" {
  write_config 'DSN="https://abc123@glitchtip.example.com/7"'
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run cmd_test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent test event"* ]]
  local body; body="$(sed -n '3p' "$BAIZE_STUB_CURL_STDIN")"
  [[ "$body" == *'"fingerprint":["baize-test"'* ]]
}
