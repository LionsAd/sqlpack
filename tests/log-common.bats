#!/usr/bin/env bats

@test "log_info hidden at error level" {
  run bash -lc 'BASH_LOG=error; source ../commands/log-common.sh; log_info "Hello"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log_info shown at info level" {
  run bash -lc 'BASH_LOG=info; source ../commands/log-common.sh; log_info "Hello"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Hello"
}

@test "log_error emits message (stderr merged)" {
  run bash -lc 'BASH_LOG=error; source ../commands/log-common.sh; log_error "Boom" 2>&1'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Boom"
}

@test "log_exec returns 0 on success" {
  run bash -lc 'BASH_LOG=debug; source ../commands/log-common.sh; log_exec "ok" "" printf ok'
  [ "$status" -eq 0 ]
}

@test "log_exec returns non-zero on failure" {
  run bash -lc 'BASH_LOG=debug; source ../commands/log-common.sh; log_exec "fail" "" bash -lc "exit 1"'
  [ "$status" -ne 0 ]
}
