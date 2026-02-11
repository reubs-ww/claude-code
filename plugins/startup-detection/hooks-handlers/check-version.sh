#!/usr/bin/env bash
#
# Claude Binary Version Check Utility
#
# This script helps users identify which Claude product is running
# and provides clear version information.
#
# Usage: ./check-version.sh
#
# This can be invoked manually or called from the detection hook.

set -euo pipefail

# Colors for output (if terminal supports it)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Disable colors if not a terminal
if [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Claude Binary Detection Report${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_section() {
    echo -e "${YELLOW}--- $1 ---${NC}"
}

detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            echo "Windows"
            ;;
        Darwin*)
            echo "macOS"
            ;;
        Linux*)
            echo "Linux"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

is_windows() {
    [[ "$(detect_os)" == "Windows" ]] || [[ -n "${WINDIR:-}" ]] || [[ -n "${SYSTEMROOT:-}" ]]
}

main() {
    print_header

    # Operating System
    print_section "Operating System"
    echo "OS: $(detect_os)"
    echo "uname: $(uname -s)"
    echo ""

    # Claude binary path
    print_section "Claude Binary Location"
    if command -v claude &>/dev/null; then
        local claude_path
        claude_path=$(command -v claude)
        echo "Path: $claude_path"

        # Try to determine the type based on path
        if [[ "$claude_path" == *"npm"* ]] || \
           [[ "$claude_path" == *"node_modules"* ]] || \
           [[ "$claude_path" == *"@anthropic-ai/claude-code"* ]] || \
           [[ "$claude_path" == *".nvm"* ]] || \
           [[ "$claude_path" == *"/bin/claude"* && -f "$(dirname "$claude_path")/../lib/node_modules/@anthropic-ai/claude-code/package.json" ]]; then
            echo -e "Type: ${GREEN}Claude Code CLI (npm-installed)${NC}"
        elif [[ "$claude_path" == *"Programs/Claude"* ]] || \
             [[ "$claude_path" == *"AppData/Local/Programs/Claude"* ]] || \
             [[ "$claude_path" == *"Claude Desktop"* ]] || \
             [[ "$claude_path" == *"/Applications/Claude.app"* ]]; then
            echo -e "Type: ${YELLOW}Claude Desktop${NC}"
        else
            # Try version check to determine type
            local version_check
            if version_check=$(claude --version 2>&1); then
                if echo "$version_check" | grep -qi "Claude Code"; then
                    echo -e "Type: ${GREEN}Claude Code CLI (verified via version)${NC}"
                elif echo "$version_check" | grep -qi "desktop\|electron"; then
                    echo -e "Type: ${YELLOW}Claude Desktop${NC}"
                else
                    echo "Type: Unknown (manual verification recommended)"
                fi
            else
                echo "Type: Unknown (manual verification recommended)"
            fi
        fi
    else
        echo -e "${RED}No 'claude' command found in PATH${NC}"
    fi
    echo ""

    # Version information
    print_section "Version Information"
    if command -v claude &>/dev/null; then
        echo "Attempting to get version..."
        # Capture version output (may vary between products)
        local version_output
        if version_output=$(claude --version 2>&1); then
            echo "$version_output"

            # Check for Claude Code CLI signature
            if echo "$version_output" | grep -qi "Claude Code\|claude-code\|@anthropic-ai"; then
                echo -e "${GREEN}Confirmed: Claude Code CLI${NC}"
            elif echo "$version_output" | grep -qi "desktop\|electron"; then
                echo -e "${YELLOW}Confirmed: Claude Desktop${NC}"
            fi
        else
            echo "Could not retrieve version information"
        fi
    fi
    echo ""

    # PATH analysis
    print_section "PATH Analysis"
    echo "Checking for multiple claude binaries..."
    if is_windows; then
        # Windows: use 'where' command
        echo "Found locations:"
        where claude 2>/dev/null | while read -r path; do
            echo "  - $path"
        done || echo "  (none found via 'where' command)"
    else
        # Unix: use 'which -a' or 'type -a'
        echo "Found locations:"
        (which -a claude 2>/dev/null || type -a claude 2>/dev/null | grep -oP '(?<= is ).*') | while read -r path; do
            echo "  - $path"
        done || echo "  (none found)"
    fi
    echo ""

    # npm global bin directory
    print_section "npm Configuration"
    if command -v npm &>/dev/null; then
        # npm bin -g is deprecated in npm 9+, use npm prefix -g instead
        local npm_prefix
        npm_prefix=$(npm prefix -g 2>/dev/null || echo 'N/A')
        echo "npm prefix (global): $npm_prefix"
        if [[ "$npm_prefix" != "N/A" ]]; then
            echo "npm bin directory: $npm_prefix/bin"
        fi

        # Check if Claude Code CLI is installed via npm
        if npm list -g @anthropic-ai/claude-code &>/dev/null 2>&1; then
            echo -e "${GREEN}@anthropic-ai/claude-code is installed globally${NC}"
        else
            echo "@anthropic-ai/claude-code is NOT installed globally"
        fi
    else
        echo "npm not found in PATH"
    fi
    echo ""

    # Claude Desktop detection
    print_section "Claude Desktop Detection"
    if is_windows; then
        # Windows paths
        local desktop_locations=(
            "${LOCALAPPDATA:-}/Programs/Claude"
            "${APPDATA:-}/Claude"
            "${PROGRAMFILES:-}/Claude"
        )
        for loc in "${desktop_locations[@]}"; do
            if [[ -d "$loc" ]]; then
                echo -e "${YELLOW}Found: $loc${NC}"
            fi
        done

        # Check if running
        if tasklist.exe 2>/dev/null | grep -qi "Claude.exe"; then
            echo -e "${YELLOW}Claude Desktop is currently running${NC}"
        else
            echo "Claude Desktop is not running"
        fi
    elif [[ "$(detect_os)" == "macOS" ]]; then
        if [[ -d "/Applications/Claude.app" ]]; then
            echo -e "${YELLOW}Found: /Applications/Claude.app${NC}"
        fi
        if pgrep -x "Claude" &>/dev/null; then
            echo -e "${YELLOW}Claude Desktop is currently running${NC}"
        else
            echo "Claude Desktop is not running"
        fi
    else
        echo "Claude Desktop detection not implemented for this platform"
    fi
    echo ""

    # Recommendations
    print_section "Recommendations"
    if command -v claude &>/dev/null; then
        local claude_path
        claude_path=$(command -v claude)

        if [[ "$claude_path" == *"Programs/Claude"* ]] || \
           [[ "$claude_path" == *"Claude Desktop"* ]] || \
           [[ "$claude_path" == *"/Applications/Claude.app"* ]]; then
            echo -e "${YELLOW}Your 'claude' command is pointing to Claude Desktop.${NC}"
            echo ""
            echo "To use Claude Code CLI instead:"
            echo "1. Install: npm install -g @anthropic-ai/claude-code"
            echo "2. Ensure npm bin directory is in PATH before Claude Desktop"
            echo "3. Or use: npx @anthropic-ai/claude-code"
            echo ""
            if is_windows; then
                echo "On Windows, you may need to:"
                echo "  - Edit System Environment Variables"
                echo "  - Move npm bin directory above Claude Desktop in PATH"
            fi
        elif [[ "$claude_path" == *"npm"* ]] || \
             [[ "$claude_path" == *"node_modules"* ]] || \
             [[ "$claude_path" == *".nvm"* ]]; then
            echo -e "${GREEN}Your 'claude' command is pointing to Claude Code CLI.${NC}"
            echo "No action needed."
        else
            # Check version output for final determination
            local version_check
            if version_check=$(claude --version 2>&1); then
                if echo "$version_check" | grep -qi "Claude Code"; then
                    echo -e "${GREEN}Your 'claude' command is Claude Code CLI (verified via version).${NC}"
                    echo "No action needed."
                else
                    echo "Could not determine the type of 'claude' binary."
                    echo "Run 'claude --version' to verify which product you're using."
                fi
            else
                echo "Could not determine the type of 'claude' binary."
                echo "Run 'claude --version' to verify which product you're using."
            fi
        fi
    else
        echo "No 'claude' command found. To install Claude Code CLI:"
        echo "  npm install -g @anthropic-ai/claude-code"
    fi
    echo ""

    echo -e "${BLUE}========================================${NC}"
}

main "$@"
