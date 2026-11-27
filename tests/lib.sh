#!/bin/sh
# Small helpers shared by the test files. Never print secret values.

PASSED=0
FAILED=0
CLEANUP=""

pass() {
  echo "PASS  $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "FAIL  $1: $2"
  FAILED=$((FAILED + 1))
}

# expect_eq <test name> <expected> <actual>
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

# expect_ne <test name> <unexpected> <actual>
expect_ne() {
  if [ "$2" != "$3" ]; then pass "$1"; else fail "$1" "did not expect '$3'"; fi
}

# on_exit <shell command>: runs when the suite ends, also after a failure.
on_exit() {
  CLEANUP="$1; $CLEANUP"
}

# http_status <curl args...>: prints only the HTTP status code.
http_status() {
  curl -s -o /dev/null -w '%{http_code}' "$@"
}

random_fin() {
  tr -dc 'A-Z0-9' </dev/urandom | head -c 7
}
