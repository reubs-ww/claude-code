#!/bin/bash

# Integration tests for stop-hook.sh
# Tests full hook execution with mock inputs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Path to the stop-hook.sh script
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/stop-hook.sh"

# ============================================================================
# Integration Test Helpers
# ============================================================================

# Create a mock state file
create_mock_state() {
  local filepath="$1"
  local iteration="${2:-1}"
  local max_iterations="${3:-10}"
  local completion_promise="${4:-null}"
  local prompt="${5:-Continue working on the task}"

  mkdir -p "$(dirname "$filepath")"

  cat > "$filepath" << EOF
---
iteration: $iteration
max_iterations: $max_iterations
completion_promise: $completion_promise
---
$prompt
EOF
}

# Create a mock transcript file
create_mock_transcript() {
  local filepath="$1"
  local assistant_text="$2"

  mkdir -p "$(dirname "$filepath")"

  cat > "$filepath" << EOF
{"role":"user","message":{"content":[{"type":"text","text":"User input"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"$assistant_text"}]}}
EOF
}

# Create hook input JSON
create_hook_input() {
  local transcript_path="$1"
  echo "{\"transcript_path\":\"$transcript_path\"}"
}

# ============================================================================
# Integration Tests
# ============================================================================

run_integration_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  Integration Tests                                                   ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  local temp_dir
  temp_dir=$(create_temp_dir)
  local original_dir
  original_dir=$(pwd)

  # Create a subdirectory to act as the project root
  local project_root="$temp_dir/project"
  mkdir -p "$project_root"
  cd "$project_root"

  # Cleanup on exit
  cleanup() {
    cd "$original_dir"
    cleanup_temp_dir "$temp_dir"
  }
  trap cleanup RETURN

  # Test: Exit with 0 when no state file exists
  start_test "no_state_file_allows_exit"
  local hook_input
  hook_input=$(create_hook_input "/nonexistent/transcript.jsonl")
  local exit_code
  echo "$hook_input" | "$HOOK_SCRIPT" > /dev/null 2>&1 || true
  exit_code=$?
  if assert_equals "0" "$exit_code"; then
    pass_test
  fi

  # Test: Block exit and continue loop
  start_test "block_exit_continue_loop"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" "Work on the task"
  create_mock_transcript "$temp_dir/transcript.jsonl" "I am working on it"
  hook_input=$(create_hook_input "$temp_dir/transcript.jsonl")
  local output
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  if assert_valid_json "$output"; then
    if assert_json_field "$output" ".decision" "block"; then
      if assert_json_field "$output" ".reason" "Work on the task"; then
        pass_test
      fi
    fi
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: Update iteration count
  start_test "update_iteration_count"
  create_mock_state ".claude/ralph-loop.local.md" 3 10 "null" "Continue"
  create_mock_transcript "$temp_dir/transcript2.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript2.jsonl")
  echo "$hook_input" | "$HOOK_SCRIPT" > /dev/null 2>&1
  local new_iteration
  new_iteration=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' ".claude/ralph-loop.local.md" | grep '^iteration:' | sed 's/iteration: *//')
  if assert_equals "4" "$new_iteration"; then
    pass_test
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: Stop when max iterations reached
  start_test "stop_at_max_iterations"
  create_mock_state ".claude/ralph-loop.local.md" 10 10 "null" "Continue"
  create_mock_transcript "$temp_dir/transcript3.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript3.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1)
  if assert_file_not_exists ".claude/ralph-loop.local.md" "State file should be deleted at max iterations"; then
    if assert_contains "$output" "Max iterations"; then
      pass_test
    fi
  fi

  # Test: Stop when completion promise detected
  start_test "stop_on_completion_promise"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 '"task_complete"' "Work on task"
  create_mock_transcript "$temp_dir/transcript4.jsonl" "I finished! <promise>task_complete</promise>"
  hook_input=$(create_hook_input "$temp_dir/transcript4.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1)
  if assert_file_not_exists ".claude/ralph-loop.local.md" "State file should be deleted when promise matched"; then
    if assert_contains "$output" "Detected"; then
      pass_test
    fi
  fi

  # Test: Continue when promise doesn't match
  start_test "continue_when_promise_no_match"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 '"done"' "Work on task"
  create_mock_transcript "$temp_dir/transcript5.jsonl" "Still working <promise>not_done</promise>"
  hook_input=$(create_hook_input "$temp_dir/transcript5.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  if assert_file_exists ".claude/ralph-loop.local.md" "State file should still exist"; then
    if assert_valid_json "$output"; then
      if assert_json_field "$output" ".decision" "block"; then
        pass_test
      fi
    fi
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: Handle missing transcript file
  start_test "handle_missing_transcript"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" "Work"
  hook_input=$(create_hook_input "/nonexistent/file.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1) || true
  if assert_file_not_exists ".claude/ralph-loop.local.md" "State file should be deleted on error"; then
    if assert_contains "$output" "Transcript file not found"; then
      pass_test
    fi
  fi

  # Test: Handle corrupted iteration (non-numeric)
  start_test "handle_corrupted_iteration"
  mkdir -p ".claude"
  cat > ".claude/ralph-loop.local.md" << 'EOF'
---
iteration: abc
max_iterations: 10
completion_promise: null
---
Work
EOF
  create_mock_transcript "$temp_dir/transcript6.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript6.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1) || true
  if assert_file_not_exists ".claude/ralph-loop.local.md" "State file should be deleted on corruption"; then
    if assert_contains "$output" "corrupted"; then
      pass_test
    fi
  fi

  # Test: Handle empty assistant response
  start_test "handle_empty_assistant_response"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" "Work"
  # Create transcript with empty content
  cat > "$temp_dir/transcript7.jsonl" << 'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"Input"}]}}
{"role":"assistant","message":{"content":[]}}
EOF
  hook_input=$(create_hook_input "$temp_dir/transcript7.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1) || true
  if assert_file_not_exists ".claude/ralph-loop.local.md"; then
    if assert_contains "$output" "no text content"; then
      pass_test
    fi
  fi

  # Test: Handle no assistant messages
  start_test "handle_no_assistant_messages"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" "Work"
  cat > "$temp_dir/transcript8.jsonl" << 'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"Input"}]}}
EOF
  hook_input=$(create_hook_input "$temp_dir/transcript8.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1) || true
  if assert_file_not_exists ".claude/ralph-loop.local.md"; then
    if assert_contains "$output" "No assistant messages"; then
      pass_test
    fi
  fi

  # Test: System message includes iteration count
  start_test "system_message_includes_iteration"
  create_mock_state ".claude/ralph-loop.local.md" 5 10 "null" "Work"
  create_mock_transcript "$temp_dir/transcript9.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript9.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  local sys_msg
  sys_msg=$(echo "$output" | jq -r '.systemMessage')
  if assert_contains "$sys_msg" "iteration 6"; then
    pass_test
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: System message includes completion promise
  start_test "system_message_includes_promise"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 '"all_done"' "Work"
  create_mock_transcript "$temp_dir/transcript10.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript10.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  local sys_msg2
  sys_msg2=$(echo "$output" | jq -r '.systemMessage')
  if assert_contains "$sys_msg2" "all_done"; then
    pass_test
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: Preserve multiline prompt
  start_test "preserve_multiline_prompt"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" $'Line 1\nLine 2\nLine 3'
  create_mock_transcript "$temp_dir/transcript11.jsonl" "Working"
  hook_input=$(create_hook_input "$temp_dir/transcript11.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  if assert_contains "$reason" "Line 1"; then
    if assert_contains "$reason" "Line 2"; then
      if assert_contains "$reason" "Line 3"; then
        pass_test
      fi
    fi
  fi
  rm -f ".claude/ralph-loop.local.md"

  # Test: Handle transcript with only tool_use content
  start_test "handle_tool_use_only"
  create_mock_state ".claude/ralph-loop.local.md" 1 10 "null" "Work"
  cat > "$temp_dir/transcript12.jsonl" << 'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"Input"}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","id":"123","name":"read","input":{}}]}}
EOF
  hook_input=$(create_hook_input "$temp_dir/transcript12.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>&1) || true
  if assert_file_not_exists ".claude/ralph-loop.local.md"; then
    if assert_contains "$output" "no text content"; then
      pass_test
    fi
  fi

  # Test: Infinite loop mode (max_iterations=0)
  start_test "infinite_loop_mode"
  create_mock_state ".claude/ralph-loop.local.md" 100 0 "null" "Work forever"
  create_mock_transcript "$temp_dir/transcript13.jsonl" "Still going"
  hook_input=$(create_hook_input "$temp_dir/transcript13.jsonl")
  output=$(echo "$hook_input" | "$HOOK_SCRIPT" 2>/dev/null)
  if assert_file_exists ".claude/ralph-loop.local.md"; then
    if assert_json_field "$output" ".decision" "block"; then
      local sys_msg3
      sys_msg3=$(echo "$output" | jq -r '.systemMessage')
      if assert_contains "$sys_msg3" "infinitely"; then
        pass_test
      fi
    fi
  fi
  rm -f ".claude/ralph-loop.local.md"

  print_summary "Integration Tests"
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║                  stop-hook.sh Integration Tests                      ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"

  run_integration_tests

  echo ""
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All integration tests passed!"
    exit 0
  else
    echo "❌ $TESTS_FAILED integration test(s) failed!"
    exit 1
  fi
}

main "$@"
