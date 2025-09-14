#!/usr/bin/env bats

setup() {
  # Load the log-common functions
  source "${BATS_TEST_DIRNAME}/../commands/log-common.sh"
}

@test "log_info hidden at error level" {
  export BASH_LOG=error
  run log_info "Hello"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log_info shown at info level" {
  export BASH_LOG=info
  run log_info "Hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hello"* ]]
}

@test "log_error emits message (stderr merged)" {
  export BASH_LOG=error
  run log_error "Boom"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Boom"
}

@test "log_exec returns 0 on success" {
  export BASH_LOG=debug
  run log_exec "ok" "" printf ok
  [ "$status" -eq 0 ]
}

@test "log_exec returns non-zero on failure" {
  export BASH_LOG=debug
  run log_exec "fail" "" bash -c "exit 1"
  [ "$status" -ne 0 ]
}

@test "log_error shows timestamp when BASH_LOG_TIMESTAMP=true (BASH_LOG unset)" {
  unset BASH_LOG
  export BASH_LOG_TIMESTAMP=true
  run log_error "Error with timestamp"
  [ "$status" -eq 0 ]
  # Should show timestamp pattern like [2025-01-01 12:00:00]
  [[ "$output" == *"["*"]"*"Error with timestamp"* ]]
}
