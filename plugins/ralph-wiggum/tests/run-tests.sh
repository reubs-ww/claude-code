#!/bin/bash

# Test runner for ralph-wiggum plugin tests
# Runs all test suites and reports overall results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           Ralph Wiggum Plugin Test Suite                             ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Track overall results
SUITES_RUN=0
SUITES_PASSED=0
SUITES_FAILED=0
FAILED_SUITES=()

# Check dependencies
echo "Checking dependencies..."
if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq is required but not installed${NC}"
  echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
  exit 1
fi

if ! command -v perl &> /dev/null; then
  echo -e "${RED}Error: perl is required but not installed${NC}"
  exit 1
fi

echo -e "${GREEN}All dependencies found${NC}"
echo ""

# Run unit tests
run_suite() {
  local suite_name="$1"
  local suite_script="$2"

  echo -e "${CYAN}Running $suite_name...${NC}"
  echo ""

  SUITES_RUN=$((SUITES_RUN + 1))

  if "$SCRIPT_DIR/$suite_script"; then
    SUITES_PASSED=$((SUITES_PASSED + 1))
    echo ""
    echo -e "${GREEN}$suite_name: PASSED${NC}"
  else
    SUITES_FAILED=$((SUITES_FAILED + 1))
    FAILED_SUITES+=("$suite_name")
    echo ""
    echo -e "${RED}$suite_name: FAILED${NC}"
  fi

  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo ""
}

# Make test scripts executable
chmod +x "$SCRIPT_DIR/test-stop-hook.sh"
chmod +x "$SCRIPT_DIR/test-integration.sh"

# Run all test suites
run_suite "Unit Tests" "test-stop-hook.sh"
run_suite "Integration Tests" "test-integration.sh"

# Print final summary
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                        Final Summary                                 ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Test suites run: $SUITES_RUN"
echo -e "${GREEN}Suites passed:   $SUITES_PASSED${NC}"

if [[ $SUITES_FAILED -gt 0 ]]; then
  echo -e "${RED}Suites failed:   $SUITES_FAILED${NC}"
  echo ""
  echo "Failed suites:"
  for suite in "${FAILED_SUITES[@]}"; do
    echo -e "  ${RED}• $suite${NC}"
  done
  echo ""
  echo -e "${RED}❌ TEST SUITE FAILED${NC}"
  exit 1
else
  echo "Suites failed:   0"
  echo ""
  echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
  exit 0
fi
