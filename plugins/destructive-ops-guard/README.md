# Destructive Operations Guard

A Claude Code plugin that ensures destructive operations always prompt for user confirmation, **even when "Accept Edits" mode is enabled**.

## Problem

When "Accept Edits" mode is ON, Claude Code auto-approves tool calls for convenience. However, this can be dangerous for irreversible operations that could cause data loss. Users might accidentally execute destructive commands without realizing the consequences.

## Solution

This plugin intercepts Bash commands before execution and checks for destructive operation patterns. When a destructive command is detected, the plugin returns an `ask` permission decision that **overrides the Accept Edits auto-approval**, forcing the user to explicitly confirm the operation.

## Protected Operations

The plugin detects and prompts for confirmation on:

### File/Directory Deletion
- `rm` - File deletion
- `rmdir` - Directory removal
- `unlink` - File unlinking

### Disk Operations
- `dd` - Low-level disk/file copy (when using `if=`)
- `mkfs` - Filesystem creation/formatting
- `fdisk` - Partition management
- `parted` - Partition management

### Secure Deletion
- `shred` - Secure file deletion
- `wipe` - Secure data wiping
- `srm` - Secure rm

### SQL Destructive Operations
- `DROP TABLE/DATABASE/SCHEMA/...` - Drops database objects
- `DELETE FROM` - Deletes rows from tables
- `TRUNCATE TABLE` - Removes all rows from tables

### Git Destructive Operations
- `git push --force` / `git push -f` - Force push (overwrites remote history)
- `git reset --hard` - Discards all uncommitted changes
- `git clean -f` - Removes untracked files

### Docker Operations
- `docker rm` - Remove containers
- `docker rmi` - Remove images
- `docker system prune` - Remove unused data
- `docker volume rm` - Remove volumes

### Kubernetes Operations
- `kubectl delete` - Delete resources

## Installation

This plugin is included in the claude-code plugins directory. To enable it, add it to your Claude Code plugin configuration.

## How It Works

1. The plugin registers a `PreToolUse` hook that matches `Bash` commands
2. When a Bash command is about to execute, the hook receives the command
3. The command is checked against regex patterns for destructive operations
4. If a match is found:
   - Returns `permissionDecision: "ask"` to force user confirmation
   - Shows a warning message describing the operation and its risks
5. If no match, the command proceeds normally (auto-approved if Accept Edits is on)

## Example Warning

When you run `rm -rf /tmp/test` with Accept Edits enabled, instead of auto-executing, you'll see:

```
**Destructive Operation Detected: rm command (file deletion)**

This command deletes files. Deleted files may not be recoverable.

This operation requires explicit confirmation even in Accept Edits mode.
```

## Customization

To add additional patterns, edit `hooks/destructive_ops_guard.py` and add entries to the `DESTRUCTIVE_PATTERNS` list:

```python
DESTRUCTIVE_PATTERNS = [
    # ... existing patterns ...
    (
        r'\byour-pattern-here\b',
        "Pattern description",
        "Warning message for the user"
    ),
]
```

## Technical Details

- **Hook Type:** PreToolUse (runs before tool execution)
- **Tool Matcher:** Bash
- **Permission Decision:** Returns `ask` to override auto-approval
- **Exit Codes:** Always exits 0 (hook errors should not block operations)
