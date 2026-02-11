#!/usr/bin/env bash
#
# Startup Detection Hook for Claude Code
#
# This script detects potential conflicts when the 'claude' command might be
# invoking Claude Desktop instead of Claude Code CLI, particularly on Windows
# where both products may be installed.
#
# Detection signals:
# 1. Check the invocation path of the current claude process
# 2. Look for Claude Desktop environment variables or processes
# 3. Check for known Claude Desktop installation paths in PATH
# 4. Identify fs.Stats deprecation warning source (DEP0180)

set -euo pipefail

# Output structure for SessionStart hook
output_context() {
    local message="$1"
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$message"
  }
}
EOF
}

output_warning() {
    local message="$1"
    # Escape special characters for JSON
    message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ')
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$message"
  }
}
EOF
}

# Detect the operating system
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            echo "windows"
            ;;
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Check if running on Windows (including Git Bash, MSYS2, etc.)
is_windows() {
    local os
    os=$(detect_os)
    [[ "$os" == "windows" ]] || [[ -n "${WINDIR:-}" ]] || [[ -n "${SYSTEMROOT:-}" ]]
}

# Get the path to the claude binary being used
get_claude_binary_path() {
    if command -v claude &>/dev/null; then
        command -v claude
    else
        echo ""
    fi
}

# Check for Claude Desktop installation paths (Windows-specific)
check_claude_desktop_paths() {
    local warnings=""

    if is_windows; then
        # Common Claude Desktop installation paths on Windows
        local desktop_paths=(
            "${LOCALAPPDATA:-}/Programs/Claude/claude.exe"
            "${APPDATA:-}/Claude/claude.exe"
            "${PROGRAMFILES:-}/Claude/claude.exe"
            "${PROGRAMFILES(X86):-}/Claude/claude.exe"
            "${USERPROFILE:-}/AppData/Local/Programs/Claude/claude.exe"
        )

        for path in "${desktop_paths[@]}"; do
            if [[ -f "$path" ]]; then
                warnings="${warnings}Found Claude Desktop at: $path\\n"
            fi
        done
    fi

    echo "$warnings"
}

# Check if Claude Desktop process is running
check_claude_desktop_process() {
    if is_windows; then
        # Windows: Check for Claude Desktop process
        if tasklist.exe 2>/dev/null | grep -qi "Claude.exe"; then
            echo "true"
            return
        fi
    elif [[ "$(detect_os)" == "macos" ]]; then
        # macOS: Check for Claude Desktop app
        if pgrep -x "Claude" &>/dev/null; then
            echo "true"
            return
        fi
    fi
    echo "false"
}

# Check PATH for potential conflicts
check_path_conflicts() {
    local claude_path
    claude_path=$(get_claude_binary_path)
    local warnings=""

    if [[ -n "$claude_path" ]]; then
        # Check if the path contains indicators of Claude Desktop
        if [[ "$claude_path" == *"Programs/Claude"* ]] || \
           [[ "$claude_path" == *"AppData/Local/Programs/Claude"* ]] || \
           [[ "$claude_path" == *"Claude Desktop"* ]]; then
            warnings="WARNING: The 'claude' command appears to be resolving to Claude Desktop.\\n"
            warnings="${warnings}Current path: $claude_path\\n"
            warnings="${warnings}\\nTo use Claude Code CLI, you may need to:\\n"
            warnings="${warnings}1. Install Claude Code CLI: npm install -g @anthropic-ai/claude-code\\n"
            warnings="${warnings}2. Ensure the npm global bin directory comes before Claude Desktop in your PATH\\n"
            warnings="${warnings}3. Or use the full path to Claude Code CLI\\n"
        fi

        # Check if it's the expected Claude Code CLI path (no action needed)
        if [[ "$claude_path" == *"npm"* ]] || \
           [[ "$claude_path" == *"node_modules"* ]] || \
           [[ "$claude_path" == *".claude"* ]] || \
           [[ "$claude_path" == *".nvm"* ]]; then
            # This looks like Claude Code CLI - good
            :
        fi
    fi

    echo "$warnings"
}

# Check for environment variables that might indicate Claude Desktop context
check_environment_indicators() {
    local warnings=""

    # Check for Claude Desktop specific environment variables
    if [[ -n "${CLAUDE_DESKTOP:-}" ]]; then
        warnings="${warnings}NOTE: CLAUDE_DESKTOP environment variable is set.\\n"
    fi

    # Check for Electron indicators (Claude Desktop is an Electron app)
    if [[ -n "${ELECTRON_RUN_AS_NODE:-}" ]]; then
        warnings="${warnings}NOTE: Running in Electron context (ELECTRON_RUN_AS_NODE is set).\\n"
    fi

    echo "$warnings"
}

# Main detection logic
main() {
    local os
    os=$(detect_os)
    local all_warnings=""
    local is_conflict_detected="false"

    # Run all detection checks
    local path_warnings
    path_warnings=$(check_path_conflicts)
    if [[ -n "$path_warnings" ]]; then
        all_warnings="${all_warnings}${path_warnings}\\n"
        is_conflict_detected="true"
    fi

    local env_warnings
    env_warnings=$(check_environment_indicators)
    if [[ -n "$env_warnings" ]]; then
        all_warnings="${all_warnings}${env_warnings}"
    fi

    # Only check for Claude Desktop process/paths on Windows (main conflict scenario)
    if is_windows; then
        local desktop_process
        desktop_process=$(check_claude_desktop_process)
        if [[ "$desktop_process" == "true" ]]; then
            all_warnings="${all_warnings}NOTE: Claude Desktop is currently running.\\n"
        fi

        local desktop_paths
        desktop_paths=$(check_claude_desktop_paths)
        if [[ -n "$desktop_paths" ]]; then
            all_warnings="${all_warnings}${desktop_paths}"
        fi
    fi

    # Output results
    if [[ "$is_conflict_detected" == "true" ]]; then
        # Output warning context for Claude to see
        local resolution_steps="\\n--- BINARY CONFLICT DETECTED ---\\n${all_warnings}\\nResolution steps:\\n1. Check which 'claude' is in your PATH: 'which claude' or 'where claude'\\n2. For Claude Code CLI, ensure npm global bin is in PATH: npm prefix -g\\n3. You can also run Claude Code directly: npx @anthropic-ai/claude-code\\n4. On Windows, you may need to reorder PATH entries\\n\\nTo verify you're running Claude Code CLI, check for these indicators:\\n- The command 'claude --version' shows 'Claude Code'\\n- The binary path contains 'npm', 'node_modules', '.nvm', or similar\\n---"
        output_warning "$resolution_steps"
    else
        # No issues detected - output minimal context
        output_context "Claude Code CLI startup detection completed. No binary conflicts detected."
    fi

    exit 0
}

main
