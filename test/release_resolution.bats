load 'helpers/setup'

# resolve_latest_version is tested here in isolation -- update.bats also
# exercises it indirectly through cmd_update, but a regression here would
# otherwise surface in a file other than the one that broke (the same
# helper backs `baize status`'s update check too).

@test "BAIZE_VERSION 設定時直接回傳它,且完全不打 API" {
  export BAIZE_VERSION="v0.9.9"
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  run resolve_latest_version
  [ "$status" -eq 0 ]
  [ "$output" = "v0.9.9" ]
  [ ! -s "$BAIZE_STUB_CURL_LOG" ]
}

@test "未設定 BAIZE_VERSION 時,從 releases API 的 JSON 解出 tag_name" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":"v2.3.4"}'
  run resolve_latest_version
  [ "$status" -eq 0 ]
  [ "$output" = "v2.3.4" ]
  grep -q 'releases/latest' "$BAIZE_STUB_CURL_LOG"
}

@test "API 失敗(curl 非零)時回傳非零,且不會回傳 main" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_CURL_RELEASES_FAIL=1
  run resolve_latest_version
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [ "$output" != "main" ]
}

@test "API 回傳無法解析的 JSON 時回傳非零,而非印出空字串,也不會回傳 main" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_RELEASES_JSON='not json at all'
  run resolve_latest_version
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [ "$output" != "main" ]
}

@test "tag_name 欄位存在但為空時回傳非零" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  export BAIZE_STUB_RELEASES_JSON='{"tag_name":""}'
  run resolve_latest_version
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
