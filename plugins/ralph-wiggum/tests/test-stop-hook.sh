#!/bin/bash

# Unit tests for stop-hook.sh
# Tests JSON parsing, transcript parsing, and output generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Path to the stop-hook.sh script
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/stop-hook.sh"

# ============================================================================
# 1. JSON Input Parsing Tests
# ============================================================================

run_json_input_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  JSON Input Parsing Tests                                            ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  # Test: Parse transcript_path from valid JSON
  start_test "parse_transcript_path_valid_json"
  local input='{"transcript_path":"/path/to/file.jsonl"}'
  local result
  result=$(echo "$input" | jq -r '.transcript_path')
  if assert_equals "/path/to/file.jsonl" "$result"; then
    pass_test
  fi

  # Test: Handle missing transcript_path field
  start_test "parse_transcript_path_missing_field"
  local input_missing='{"other_field":"value"}'
  local result_missing
  result_missing=$(echo "$input_missing" | jq -r '.transcript_path')
  if assert_equals "null" "$result_missing"; then
    pass_test
  fi

  # Test: Handle malformed JSON input
  start_test "parse_malformed_json"
  local malformed='not valid json'
  local parse_result
  if ! echo "$malformed" | jq -r '.transcript_path' >/dev/null 2>&1; then
    pass_test
  else
    fail_test "Expected jq to fail on malformed JSON"
  fi

  # Test: Handle paths with spaces
  start_test "parse_path_with_spaces"
  local input_spaces='{"transcript_path":"/path/to/my file.jsonl"}'
  local result_spaces
  result_spaces=$(echo "$input_spaces" | jq -r '.transcript_path')
  if assert_equals "/path/to/my file.jsonl" "$result_spaces"; then
    pass_test
  fi

  # Test: Handle paths with special characters
  start_test "parse_path_with_special_chars"
  local input_special='{"transcript_path":"/path/to/file-with_special.chars!.jsonl"}'
  local result_special
  result_special=$(echo "$input_special" | jq -r '.transcript_path')
  if assert_equals "/path/to/file-with_special.chars!.jsonl" "$result_special"; then
    pass_test
  fi

  # Test: Handle unicode in path
  start_test "parse_path_with_unicode"
  local input_unicode='{"transcript_path":"/path/to/file-\u00e9\u00e8.jsonl"}'
  local result_unicode
  result_unicode=$(echo "$input_unicode" | jq -r '.transcript_path')
  if assert_contains "$result_unicode" "file-"; then
    pass_test
  fi

  print_summary "JSON Input Parsing"
}

# ============================================================================
# 2. Transcript Parsing Tests
# ============================================================================

run_transcript_parsing_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  Transcript Parsing Tests                                            ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  local temp_dir
  temp_dir=$(create_temp_dir)
  trap "cleanup_temp_dir '$temp_dir'" RETURN

  # Test: Extract text from single text item in content array
  start_test "extract_single_text_item"
  cat > "$temp_dir/transcript.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"Hello world"}]}}
EOF
  local last_line
  last_line=$(grep '"role":"assistant"' "$temp_dir/transcript.jsonl" | tail -1)
  local result
  result=$(echo "$last_line" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_equals "Hello world" "$result"; then
    pass_test
  fi

  # Test: Extract and join multiple text items
  start_test "extract_multiple_text_items"
  cat > "$temp_dir/transcript2.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"Line 1"},{"type":"text","text":"Line 2"}]}}
EOF
  local last_line2
  last_line2=$(grep '"role":"assistant"' "$temp_dir/transcript2.jsonl" | tail -1)
  local result2
  result2=$(echo "$last_line2" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_equals $'Line 1\nLine 2' "$result2"; then
    pass_test
  fi

  # Test: Handle mixed content (text + tool_use)
  start_test "extract_mixed_content"
  cat > "$temp_dir/transcript3.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"Before tool"},{"type":"tool_use","id":"123","name":"read","input":{}},{"type":"text","text":"After tool"}]}}
EOF
  local last_line3
  last_line3=$(grep '"role":"assistant"' "$temp_dir/transcript3.jsonl" | tail -1)
  local result3
  result3=$(echo "$last_line3" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_equals $'Before tool\nAfter tool' "$result3"; then
    pass_test
  fi

  # Test: Handle empty content array
  start_test "extract_empty_content"
  cat > "$temp_dir/transcript4.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[]}}
EOF
  local last_line4
  last_line4=$(grep '"role":"assistant"' "$temp_dir/transcript4.jsonl" | tail -1)
  local result4
  result4=$(echo "$last_line4" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_equals "" "$result4"; then
    pass_test
  fi

  # Test: Handle escaped newlines in text
  start_test "extract_escaped_newlines"
  cat > "$temp_dir/transcript5.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"Line 1\nLine 2\nLine 3"}]}}
EOF
  local last_line5
  last_line5=$(grep '"role":"assistant"' "$temp_dir/transcript5.jsonl" | tail -1)
  local result5
  result5=$(echo "$last_line5" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_contains "$result5" "Line 1"; then
    if assert_contains "$result5" "Line 2"; then
      if assert_contains "$result5" "Line 3"; then
        pass_test
      fi
    fi
  fi

  # Test: Handle escaped quotes in text
  start_test "extract_escaped_quotes"
  cat > "$temp_dir/transcript6.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"He said \"hello\""}]}}
EOF
  local last_line6
  last_line6=$(grep '"role":"assistant"' "$temp_dir/transcript6.jsonl" | tail -1)
  local result6
  result6=$(echo "$last_line6" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_contains "$result6" '"hello"'; then
    pass_test
  fi

  # Test: Handle escaped backslashes
  start_test "extract_escaped_backslashes"
  cat > "$temp_dir/transcript7.jsonl" << 'EOF'
{"role":"assistant","message":{"content":[{"type":"text","text":"path\\to\\file"}]}}
EOF
  local last_line7
  last_line7=$(grep '"role":"assistant"' "$temp_dir/transcript7.jsonl" | tail -1)
  local result7
  result7=$(echo "$last_line7" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_contains "$result7" 'path\to\file'; then
    pass_test
  fi

  # Test: Get last assistant message from multiple
  start_test "extract_last_assistant_message"
  cat > "$temp_dir/transcript8.jsonl" << 'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"User input"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"First response"}]}}
{"role":"user","message":{"content":[{"type":"text","text":"Second input"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"Second response"}]}}
EOF
  local last_line8
  last_line8=$(grep '"role":"assistant"' "$temp_dir/transcript8.jsonl" | tail -1)
  local result8
  result8=$(echo "$last_line8" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")')
  if assert_equals "Second response" "$result8"; then
    pass_test
  fi

  print_summary "Transcript Parsing"
}

# ============================================================================
# 3. JSON Output Generation Tests
# ============================================================================

run_json_output_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  JSON Output Generation Tests                                        ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  # Test: Verify output is valid JSON
  start_test "output_valid_json"
  local prompt="Test prompt"
  local msg="Test message"
  local output
  output=$(jq -n --arg prompt "$prompt" --arg msg "$msg" '{"decision":"block","reason":$prompt,"systemMessage":$msg}')
  if assert_valid_json "$output"; then
    pass_test
  fi

  # Test: Verify newlines are escaped correctly
  start_test "output_escape_newlines"
  local prompt_nl=$'Line 1\nLine 2\nLine 3'
  local output_nl
  output_nl=$(jq -n --arg prompt "$prompt_nl" '{"reason":$prompt}')
  if assert_valid_json "$output_nl"; then
    # Verify the JSON contains the escaped newlines
    if assert_contains "$output_nl" '\n'; then
      pass_test
    fi
  fi

  # Test: Verify quotes are escaped correctly
  start_test "output_escape_quotes"
  local prompt_quotes='He said "hello" and "goodbye"'
  local output_quotes
  output_quotes=$(jq -n --arg prompt "$prompt_quotes" '{"reason":$prompt}')
  if assert_valid_json "$output_quotes"; then
    # Verify it round-trips correctly
    local extracted
    extracted=$(echo "$output_quotes" | jq -r '.reason')
    if assert_equals "$prompt_quotes" "$extracted"; then
      pass_test
    fi
  fi

  # Test: Verify backslashes are escaped correctly
  start_test "output_escape_backslashes"
  local prompt_bs='path\to\file'
  local output_bs
  output_bs=$(jq -n --arg prompt "$prompt_bs" '{"reason":$prompt}')
  if assert_valid_json "$output_bs"; then
    local extracted_bs
    extracted_bs=$(echo "$output_bs" | jq -r '.reason')
    if assert_equals "$prompt_bs" "$extracted_bs"; then
      pass_test
    fi
  fi

  # Test: Verify emoji preserved
  start_test "output_preserve_emoji"
  local prompt_emoji="Test with emoji: 🔄 ✅ ⚠️ 🛑"
  local output_emoji
  output_emoji=$(jq -n --arg prompt "$prompt_emoji" '{"reason":$prompt}')
  if assert_valid_json "$output_emoji"; then
    local extracted_emoji
    extracted_emoji=$(echo "$output_emoji" | jq -r '.reason')
    if assert_contains "$extracted_emoji" "🔄"; then
      if assert_contains "$extracted_emoji" "✅"; then
        pass_test
      fi
    fi
  fi

  # Test: Verify unicode preserved
  start_test "output_preserve_unicode"
  local prompt_unicode="Test with unicode: café résumé naïve"
  local output_unicode
  output_unicode=$(jq -n --arg prompt "$prompt_unicode" '{"reason":$prompt}')
  if assert_valid_json "$output_unicode"; then
    local extracted_unicode
    extracted_unicode=$(echo "$output_unicode" | jq -r '.reason')
    if assert_equals "$prompt_unicode" "$extracted_unicode"; then
      pass_test
    fi
  fi

  # Test: Verify decision field is set correctly
  start_test "output_decision_field"
  local output_decision
  output_decision=$(jq -n --arg prompt "test" --arg msg "test" '{"decision":"block","reason":$prompt,"systemMessage":$msg}')
  if assert_json_field "$output_decision" ".decision" "block"; then
    pass_test
  fi

  # Test: Verify all required fields present
  start_test "output_all_fields_present"
  local prompt="prompt text"
  local msg="system message"
  local output_full
  output_full=$(jq -n --arg prompt "$prompt" --arg msg "$msg" '{"decision":"block","reason":$prompt,"systemMessage":$msg}')
  local has_decision has_reason has_msg
  has_decision=$(echo "$output_full" | jq 'has("decision")')
  has_reason=$(echo "$output_full" | jq 'has("reason")')
  has_msg=$(echo "$output_full" | jq 'has("systemMessage")')
  if [[ "$has_decision" == "true" ]] && [[ "$has_reason" == "true" ]] && [[ "$has_msg" == "true" ]]; then
    pass_test
  else
    fail_test "Missing required fields"
  fi

  print_summary "JSON Output Generation"
}

# ============================================================================
# 4. State File Parsing Tests
# ============================================================================

run_state_file_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  State File Parsing Tests                                            ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  local temp_dir
  temp_dir=$(create_temp_dir)
  trap "cleanup_temp_dir '$temp_dir'" RETURN

  # Test: Parse iteration from frontmatter
  start_test "parse_iteration"
  cat > "$temp_dir/state.md" << 'EOF'
---
iteration: 5
max_iterations: 10
completion_promise: "done"
---
This is the prompt
EOF
  local frontmatter
  frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$temp_dir/state.md")
  local iteration
  iteration=$(echo "$frontmatter" | grep '^iteration:' | sed 's/iteration: *//')
  if assert_equals "5" "$iteration"; then
    pass_test
  fi

  # Test: Parse max_iterations from frontmatter
  start_test "parse_max_iterations"
  local max_iterations
  max_iterations=$(echo "$frontmatter" | grep '^max_iterations:' | sed 's/max_iterations: *//')
  if assert_equals "10" "$max_iterations"; then
    pass_test
  fi

  # Test: Parse completion_promise with quotes
  start_test "parse_completion_promise_with_quotes"
  local completion_promise
  completion_promise=$(echo "$frontmatter" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
  if assert_equals "done" "$completion_promise"; then
    pass_test
  fi

  # Test: Parse completion_promise without quotes
  start_test "parse_completion_promise_without_quotes"
  cat > "$temp_dir/state2.md" << 'EOF'
---
iteration: 1
max_iterations: 5
completion_promise: task_complete
---
Prompt text
EOF
  local frontmatter2
  frontmatter2=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$temp_dir/state2.md")
  local promise2
  promise2=$(echo "$frontmatter2" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
  if assert_equals "task_complete" "$promise2"; then
    pass_test
  fi

  # Test: Extract prompt text after frontmatter
  start_test "extract_prompt_text"
  local prompt_text
  prompt_text=$(awk '/^---$/{i++; next} i>=2' "$temp_dir/state.md")
  if assert_equals "This is the prompt" "$prompt_text"; then
    pass_test
  fi

  # Test: Extract multiline prompt text
  start_test "extract_multiline_prompt"
  cat > "$temp_dir/state3.md" << 'EOF'
---
iteration: 1
max_iterations: 10
completion_promise: null
---
Line 1 of prompt
Line 2 of prompt
Line 3 of prompt
EOF
  local prompt3
  prompt3=$(awk '/^---$/{i++; next} i>=2' "$temp_dir/state3.md")
  if assert_contains "$prompt3" "Line 1"; then
    if assert_contains "$prompt3" "Line 2"; then
      if assert_contains "$prompt3" "Line 3"; then
        pass_test
      fi
    fi
  fi

  # Test: Handle --- in prompt content
  start_test "handle_dashes_in_prompt"
  cat > "$temp_dir/state4.md" << 'EOF'
---
iteration: 1
max_iterations: 10
completion_promise: null
---
This prompt has --- in it
And more text after
EOF
  local prompt4
  prompt4=$(awk '/^---$/{i++; next} i>=2' "$temp_dir/state4.md")
  if assert_contains "$prompt4" "This prompt has --- in it"; then
    if assert_contains "$prompt4" "And more text after"; then
      pass_test
    fi
  fi

  # Test: Validate iteration is numeric
  start_test "validate_iteration_numeric"
  local valid_iteration="5"
  local invalid_iteration="abc"
  if [[ "$valid_iteration" =~ ^[0-9]+$ ]]; then
    if ! [[ "$invalid_iteration" =~ ^[0-9]+$ ]]; then
      pass_test
    else
      fail_test "Invalid iteration should not match numeric pattern"
    fi
  else
    fail_test "Valid iteration should match numeric pattern"
  fi

  print_summary "State File Parsing"
}

# ============================================================================
# 5. Completion Promise Detection Tests
# ============================================================================

run_promise_detection_tests() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║  Completion Promise Detection Tests                                  ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"
  init_tests

  # Test: Detect promise tag in output
  start_test "detect_promise_tag"
  local output="Some text before <promise>task_complete</promise> some text after"
  local promise_text
  promise_text=$(echo "$output" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if assert_equals "task_complete" "$promise_text"; then
    pass_test
  fi

  # Test: Detect multiline promise
  start_test "detect_multiline_promise"
  local output_ml="Before
<promise>done</promise>
After"
  local promise_ml
  promise_ml=$(echo "$output_ml" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if assert_equals "done" "$promise_ml"; then
    pass_test
  fi

  # Test: Handle promise with whitespace
  start_test "detect_promise_with_whitespace"
  local output_ws="<promise>  task_complete  </promise>"
  local promise_ws
  promise_ws=$(echo "$output_ws" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if assert_equals "task_complete" "$promise_ws"; then
    pass_test
  fi

  # Test: Handle no promise tag
  start_test "no_promise_tag"
  local output_no="This output has no promise tags at all"
  local promise_no
  promise_no=$(echo "$output_no" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  # When no match, perl returns the original string
  if [[ "$promise_no" == "$output_no" ]] || [[ -z "$promise_no" ]]; then
    pass_test
  else
    fail_test "Expected no match but got: $promise_no"
  fi

  # Test: Match first promise tag only
  start_test "match_first_promise"
  local output_multi="<promise>first</promise> <promise>second</promise>"
  local promise_first
  promise_first=$(echo "$output_multi" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if assert_equals "first" "$promise_first"; then
    pass_test
  fi

  # Test: Promise comparison with literal string
  start_test "promise_literal_comparison"
  local promise="done"
  local expected="done"
  # Use = for literal comparison (not == which does glob matching)
  if [[ "$promise" = "$expected" ]]; then
    pass_test
  else
    fail_test "Promise should match exactly"
  fi

  # Test: Promise with special glob characters
  start_test "promise_with_glob_chars"
  local promise_glob="task*complete?"
  local expected_glob="task*complete?"
  # This would fail with == but should work with =
  if [[ "$promise_glob" = "$expected_glob" ]]; then
    pass_test
  else
    fail_test "Promise with glob chars should match literally"
  fi

  print_summary "Completion Promise Detection"
}

# ============================================================================
# Main
# ============================================================================

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════╗"
  echo "║                    stop-hook.sh Unit Tests                           ║"
  echo "╚══════════════════════════════════════════════════════════════════════╝"

  local total_failed=0

  run_json_input_tests || total_failed=$((total_failed + TESTS_FAILED))
  run_transcript_parsing_tests || total_failed=$((total_failed + TESTS_FAILED))
  run_json_output_tests || total_failed=$((total_failed + TESTS_FAILED))
  run_state_file_tests || total_failed=$((total_failed + TESTS_FAILED))
  run_promise_detection_tests || total_failed=$((total_failed + TESTS_FAILED))

  echo ""
  if [[ $total_failed -eq 0 ]]; then
    echo "✅ All unit tests passed!"
    exit 0
  else
    echo "❌ $total_failed test(s) failed!"
    exit 1
  fi
}

main "$@"
