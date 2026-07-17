load 'helpers/setup'

@test "df 回報 88% 時，disk_used_pct / 印出 88（沒有 %）" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=88 run disk_used_pct /
  [ "$status" -eq 0 ]
  [ "$output" = "88" ]
}

@test "df 回報 0% 時印出 0" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=0 run disk_used_pct /
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "df 回報 100% 時印出 100" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_PCT=100 run disk_used_pct /
  [ "$status" -eq 0 ]
  [ "$output" = "100" ]
}

@test "df 失敗（exit 非零）時，disk_used_pct 回傳非零且不印出東西" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_EXIT=1 run disk_used_pct /
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "df 輸出無法解析（capacity 欄是 -）時，回傳非零而非印出空字串" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  BAIZE_STUB_DF_RAW=$'Filesystem     1024-blocks     Used Available Capacity Mounted on\n/dev/stub          10485760  1048576   9437184         - /' run disk_used_pct /
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "MOUNTS=\"/ /mnt/data\" 時，each_mount_pct 印出兩行" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  MOUNTS="/ /mnt/data"
  BAIZE_STUB_DF_PCT=42 run each_mount_pct
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "/ 42" ]
  [ "${lines[1]}" = "/mnt/data 42" ]
}

@test "其中一個 mount 讀不到時，另一個仍然被印出，且 stderr 有警告" {
  BAIZE_LIB_ONLY=1 source "$BAIZE_BIN"
  MOUNTS="/ /mnt/data"

  df() {
    if [[ "${*: -1}" == "/mnt/data" ]]; then
      return 1
    fi
    command df "$@"
  }
  export -f df

  run each_mount_pct
  [ "$status" -eq 0 ]
  [[ "$output" == *"/ 10"* ]]
  [[ "$output" == *"cannot read disk usage for mount: /mnt/data"* ]]
}
