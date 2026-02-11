#!/usr/bin/env python3
"""
Destructive Operations Guard Hook for Claude Code

This hook ensures that destructive operations always prompt for user confirmation,
even when "Accept Edits" mode is enabled. It intercepts Bash commands and returns
an 'ask' permission decision for potentially irreversible operations.

Destructive operations include:
- File deletion (rm, rmdir, unlink)
- Disk operations (dd, mkfs, format)
- Secure deletion (shred, wipe)
- Destructive SQL (DROP, DELETE, TRUNCATE)
- Force push (git push --force)
- System modifications that could cause data loss
"""

import json
import re
import sys
from typing import Optional, Tuple


# Patterns for destructive operations that should ALWAYS require confirmation
# Each pattern is a tuple of (regex, description, severity)
DESTRUCTIVE_PATTERNS = [
    # File/directory deletion
    (
        r'\brm\b(?:\s+|$)',
        "rm command (file deletion)",
        "This command deletes files. Deleted files may not be recoverable."
    ),
    (
        r'\brmdir\b',
        "rmdir command (directory removal)",
        "This command removes directories."
    ),
    (
        r'\bunlink\b',
        "unlink command (file removal)",
        "This command removes files by unlinking."
    ),

    # Disk and partition operations
    (
        r'\bdd\b\s+.*\bif=',
        "dd command (disk/file copy)",
        "The dd command can overwrite disks or files. This is a low-level operation that can cause data loss."
    ),
    (
        r'\bmkfs\b',
        "mkfs command (filesystem creation)",
        "This command formats a partition or disk, destroying all existing data."
    ),
    (
        r'\bfdisk\b',
        "fdisk command (partition management)",
        "This command modifies disk partitions and can cause data loss."
    ),
    (
        r'\bparted\b',
        "parted command (partition management)",
        "This command modifies disk partitions and can cause data loss."
    ),

    # Secure deletion
    (
        r'\bshred\b',
        "shred command (secure file deletion)",
        "This command securely deletes files by overwriting them. Data cannot be recovered."
    ),
    (
        r'\bwipe\b',
        "wipe command (secure deletion)",
        "This command securely wipes data. Data cannot be recovered."
    ),
    (
        r'\bsrm\b',
        "srm command (secure rm)",
        "This command securely deletes files. Data cannot be recovered."
    ),

    # SQL destructive operations
    (
        r'\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|TRIGGER|FUNCTION|PROCEDURE)\b',
        "SQL DROP statement",
        "This SQL command permanently removes database objects and their data."
    ),
    (
        r'\bDELETE\s+FROM\b',
        "SQL DELETE statement",
        "This SQL command deletes rows from a table."
    ),
    (
        r'\bTRUNCATE\s+(TABLE)?\b',
        "SQL TRUNCATE statement",
        "This SQL command removes all rows from a table."
    ),

    # Git destructive operations
    (
        r'\bgit\s+push\b.*--force\b|\bgit\s+push\b.*-f\b',
        "git push --force",
        "Force pushing can overwrite remote history and cause data loss for collaborators."
    ),
    (
        r'\bgit\s+reset\s+--hard\b',
        "git reset --hard",
        "This command discards all uncommitted changes permanently."
    ),
    (
        r'\bgit\s+clean\b.*-f',
        "git clean -f",
        "This command removes untracked files permanently."
    ),

    # Docker destructive operations
    (
        r'\bdocker\s+(rm|rmi|system\s+prune|volume\s+rm|network\s+rm)\b',
        "docker remove/prune command",
        "This command removes Docker resources which may cause data loss."
    ),

    # Kubernetes destructive operations
    (
        r'\bkubectl\s+delete\b',
        "kubectl delete command",
        "This command deletes Kubernetes resources."
    ),

    # System-level destructive operations
    (
        r'\bsystemctl\s+(disable|mask|stop)\b.*\b(network|sshd|docker)\b',
        "systemctl disabling critical services",
        "This command may disable critical system services."
    ),
]


def check_destructive_patterns(command: str) -> Optional[Tuple[str, str]]:
    """Check if command matches any destructive patterns.

    Args:
        command: The bash command to check

    Returns:
        Tuple of (pattern_name, warning_message) if destructive, None otherwise
    """
    for pattern, name, warning in DESTRUCTIVE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            return name, warning
    return None


def main():
    """Main hook function."""
    try:
        # Read input from stdin
        raw_input = sys.stdin.read()
        input_data = json.loads(raw_input)
    except json.JSONDecodeError:
        # If we can't parse input, allow the operation
        sys.exit(0)

    # Extract tool information
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only process Bash commands
    if tool_name != "Bash":
        sys.exit(0)

    # Get the command
    command = tool_input.get("command", "")
    if not command:
        sys.exit(0)

    # Check for destructive patterns
    result = check_destructive_patterns(command)

    if result:
        pattern_name, warning = result

        # Return 'ask' permission decision to force user confirmation
        # This overrides Accept Edits mode for destructive operations
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask"
            },
            "systemMessage": f"**Destructive Operation Detected: {pattern_name}**\n\n{warning}\n\nThis operation requires explicit confirmation even in Accept Edits mode."
        }
        print(json.dumps(output))
        # Exit 0 to let the hook system handle the 'ask' decision
        sys.exit(0)

    # No destructive patterns found, allow the operation
    sys.exit(0)


if __name__ == "__main__":
    main()
