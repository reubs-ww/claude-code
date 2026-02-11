#!/usr/bin/env python3
"""
File Reference Validation Hook for Claude Code

This hook validates destructive bash commands (rm, rmdir, etc.) to ensure
Claude is explicit about which files are being targeted. It helps prevent
accidental deletion of wrong files when contextual references are used.

The hook checks for destructive commands and reminds Claude to:
1. Explicitly state the file path being targeted
2. Verify the path matches recent conversation context
3. Confirm before proceeding with deletion

Exit codes:
- 0: Allow command to proceed
- 2: Block command and show stderr to Claude (for guidance)
"""

import json
import os
import re
import sys
from datetime import datetime

# Debug log file
DEBUG_LOG_FILE = "/tmp/file-reference-validation-log.txt"

# Destructive commands that warrant validation
DESTRUCTIVE_COMMANDS = [
    "rm",
    "rmdir",
    "unlink",
    "shred",
    "del",
    "trash",
    "trash-put",
]

# Pattern to match destructive commands at the start of a command or after pipe/semicolon/&&/||
DESTRUCTIVE_PATTERN = re.compile(
    r"(?:^|[;&|]\s*|&&\s*|\|\|\s*|\|\s*(?:xargs\s+)?)"
    r"(?:sudo\s+)?"
    r"(" + "|".join(re.escape(cmd) for cmd in DESTRUCTIVE_COMMANDS) + r")"
    r"\b"
)


def debug_log(message: str) -> None:
    """Append debug message to log file with timestamp."""
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        with open(DEBUG_LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception:
        pass


def is_destructive_command(command: str) -> tuple[bool, list[str]]:
    """
    Check if the command contains destructive operations.

    Returns:
        Tuple of (is_destructive, list of matched destructive commands)
    """
    matches = DESTRUCTIVE_PATTERN.findall(command.lower())
    return bool(matches), matches


def extract_file_paths(command: str) -> list[str]:
    """
    Extract potential file paths from a command.

    This is a best-effort extraction that looks for:
    - Quoted strings (single or double)
    - Paths starting with / or ./ or ../
    - Arguments that look like file paths
    """
    paths = []

    # Match quoted paths
    quoted = re.findall(r'["\']([^"\']+)["\']', command)
    paths.extend(quoted)

    # Match unquoted paths (simple heuristic)
    # Look for arguments after rm/rmdir/etc that look like paths
    parts = command.split()
    for i, part in enumerate(parts):
        # Skip flags
        if part.startswith("-"):
            continue
        # Skip the command itself
        if part.lower() in DESTRUCTIVE_COMMANDS or part == "sudo":
            continue
        # Check if it looks like a path
        if part.startswith("/") or part.startswith("./") or part.startswith("../"):
            if part not in paths:
                paths.append(part)
        # Also include paths with extensions or that contain /
        elif "/" in part or re.search(r"\.\w+$", part):
            if part not in paths:
                paths.append(part)

    return paths


def get_state_file(session_id: str) -> str:
    """Get session-specific state file path."""
    return os.path.expanduser(
        f"~/.claude/file_reference_validation_state_{session_id}.json"
    )


def load_warned_commands(session_id: str) -> set:
    """Load the set of commands we've already warned about."""
    state_file = get_state_file(session_id)
    if os.path.exists(state_file):
        try:
            with open(state_file, "r") as f:
                return set(json.load(f))
        except (json.JSONDecodeError, IOError):
            return set()
    return set()


def save_warned_commands(session_id: str, warned: set) -> None:
    """Save the set of commands we've warned about."""
    state_file = get_state_file(session_id)
    try:
        os.makedirs(os.path.dirname(state_file), exist_ok=True)
        with open(state_file, "w") as f:
            json.dump(list(warned), f)
    except IOError:
        pass


def generate_warning(command: str, matched_commands: list[str], paths: list[str]) -> str:
    """Generate a warning message for the destructive command."""
    cmd_str = ", ".join(set(matched_commands))

    warning = f"""⚠️ DESTRUCTIVE COMMAND DETECTED: {cmd_str}

Before proceeding, verify file reference accuracy:

"""

    if paths:
        warning += "Files that will be affected:\n"
        for path in paths:
            warning += f"  - {path}\n"
        warning += "\n"

    warning += """REQUIRED VALIDATION:
1. Is this the file the user explicitly mentioned in their MOST RECENT message?
2. If the user said "the file", "that file", or similar, confirm the path matches the most recently discussed file
3. If uncertain which file was meant, ASK the user to specify the exact path

If the file path was NOT explicitly stated by the user in their last message,
you should confirm with them before running this command.

To proceed: Re-run this command only after confirming the correct file is targeted."""

    return warning


def main() -> None:
    """Main hook function."""
    # Check if validation is enabled (can be disabled via env var)
    if os.environ.get("DISABLE_FILE_REFERENCE_VALIDATION", "0") == "1":
        sys.exit(0)

    # Read input from stdin
    try:
        raw_input = sys.stdin.read()
        input_data = json.loads(raw_input)
    except json.JSONDecodeError as e:
        debug_log(f"JSON decode error: {e}")
        sys.exit(0)  # Allow command to proceed if we can't parse input

    # Extract session ID and tool information
    session_id = input_data.get("session_id", "default")
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only process Bash tool
    if tool_name != "Bash":
        sys.exit(0)

    command = tool_input.get("command", "")
    if not command:
        sys.exit(0)

    # Check if this is a destructive command
    is_destructive, matched_commands = is_destructive_command(command)

    if not is_destructive:
        sys.exit(0)

    # Extract file paths from the command
    paths = extract_file_paths(command)

    # Create a unique key for this command
    command_key = f"{command}"

    # Load previously warned commands for this session
    warned = load_warned_commands(session_id)

    # If we've already warned about this exact command, allow it
    # (Claude has presumably verified the path after seeing the warning)
    if command_key in warned:
        debug_log(f"Command already warned, allowing: {command}")
        sys.exit(0)

    # Mark this command as warned
    warned.add(command_key)
    save_warned_commands(session_id, warned)

    # Generate and output warning
    warning = generate_warning(command, matched_commands, paths)
    debug_log(f"Blocking destructive command: {command}")
    print(warning, file=sys.stderr)

    # Block the command (exit code 2 shows stderr to Claude)
    sys.exit(2)


if __name__ == "__main__":
    main()
