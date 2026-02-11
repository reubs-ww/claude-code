#!/bin/bash

# Test assertion helpers for stop-hook.sh tests

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Current test name for error reporting
CURRENT_TEST=""

# Initialize test suite
init_tests() {
  TESTS_RUN=0
  TESTS_PASSED=0
  TESTS_FAILED=0
}

# Start a new test
start_test() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "  Running: %s ... " "$1"
}

# Mark test as passed
pass_test() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC}\n"
}

# Mark test as failed with message
fail_test() {
  local msg="$1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "${RED}FAIL${NC}\n"
  printf "    ${RED}→ %s${NC}\n" "$msg"
}

# Assert two strings are equal
assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Expected '$expected' but got '$actual'}"

  if [[ "$expected" == "$actual" ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert string contains substring
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Expected string to contain '$needle'}"

  if [[ "$haystack" == *"$needle"* ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert string does not contain substring
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-Expected string to NOT contain '$needle'}"

  if [[ "$haystack" != *"$needle"* ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert string is valid JSON
assert_valid_json() {
  local json="$1"
  local msg="${2:-Expected valid JSON}"

  if echo "$json" | jq . >/dev/null 2>&1; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert command exit code
assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-Expected exit code $expected but got $actual}"

  if [[ "$expected" -eq "$actual" ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert file exists
assert_file_exists() {
  local filepath="$1"
  local msg="${2:-Expected file '$filepath' to exist}"

  if [[ -f "$filepath" ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert file does not exist
assert_file_not_exists() {
  local filepath="$1"
  local msg="${2:-Expected file '$filepath' to NOT exist}"

  if [[ ! -f "$filepath" ]]; then
    return 0
  else
    fail_test "$msg"
    return 1
  fi
}

# Assert JSON field value using jq
assert_json_field() {
  local json="$1"
  local field="$2"
  local expected="$3"
  local msg="${4:-Expected JSON field '$field' to be '$expected'}"

  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null)

  if [[ "$actual" == "$expected" ]]; then
    return 0
  else
    fail_test "$msg (got '$actual')"
    return 1
  fi
}

# Print test summary
print_summary() {
  local suite_name="${1:-Tests}"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$suite_name Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "  Total:  %d\n" "$TESTS_RUN"
  printf "  ${GREEN}Passed: %d${NC}\n" "$TESTS_PASSED"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    printf "  ${RED}Failed: %d${NC}\n" "$TESTS_FAILED"
  else
    printf "  Failed: %d\n" "$TESTS_FAILED"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ $TESTS_FAILED -gt 0 ]]; then
    return 1
  fi
  return 0
}

# Create a temporary directory for tests
create_temp_dir() {
  mktemp -d
}

# Clean up temporary directory
cleanup_temp_dir() {
  local dir="$1"
  if [[ -d "$dir" ]] && [[ "$dir" == /tmp/* || "$dir" == /var/folders/* ]]; then
    rm -rf "$dir"
  fi
}
