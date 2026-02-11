# Safety Features User Guide

This guide explains how Claude Code's safety features protect you from accidental data loss and how to work with them effectively.

## Table of Contents

1. [Understanding Confirmation Prompts](#understanding-confirmation-prompts)
2. [What Triggers Confirmations](#what-triggers-confirmations)
3. [Accept Edits Mode and Safety](#accept-edits-mode-and-safety)
4. [File Reference Safety](#file-reference-safety)
5. [Overriding When Needed](#overriding-when-needed)
6. [Best Practices](#best-practices)

## Understanding Confirmation Prompts

When you ask Claude to run a potentially destructive command, you'll see a confirmation prompt:

```
⚠️ This command could be destructive:
   rm -rf ./old_backups/

Do you want to proceed? [y/N]
```

This happens because:
1. The command matches a known destructive pattern
2. Claude wants to ensure you intended this action
3. Once files are deleted, they may be unrecoverable

**Confirmation is good!** It's a safety net that has prevented countless accidental deletions.

## What Triggers Confirmations

### File Deletion Commands

| Command | Triggers | Reason |
|---------|----------|--------|
| `rm file.txt` | Yes | Deletes files |
| `rm -rf dir/` | Yes | Recursive deletion |
| `rm -rf /` | Yes (Critical) | Would delete everything |
| `unlink file` | Yes | Alternative to rm |
| `shred file` | Yes | Secure deletion |

### Disk Operations

| Command | Triggers | Reason |
|---------|----------|--------|
| `dd if=/dev/zero of=/dev/sda` | Yes (Critical) | Overwrites disk |
| `mkfs.ext4 /dev/sda1` | Yes (Critical) | Formats partition |
| `fdisk /dev/sda` | Yes | Partition editing |

### System Commands

| Command | Triggers | Reason |
|---------|----------|--------|
| `chmod 777 file` | Yes | Dangerous permissions |
| `kill -9 PID` | Yes | Force kills process |
| `reboot` | Yes | System restart |
| `shutdown now` | Yes | System shutdown |
| `sudo rm -rf` | Yes (Critical) | Admin deletion |

### Database Operations

| Command | Triggers | Reason |
|---------|----------|--------|
| `DROP DATABASE db` | Yes (Critical) | Deletes database |
| `DROP TABLE users` | Yes (Critical) | Deletes table |
| `TRUNCATE TABLE` | Yes | Removes all rows |
| `DELETE FROM users` (no WHERE) | Yes | Mass deletion |

### Commands That DON'T Trigger Confirmation

These read-only commands are safe and don't prompt:

- `ls`, `cat`, `head`, `tail` - Reading files
- `grep`, `find`, `wc` - Searching/counting
- `pwd`, `whoami`, `date` - System info
- `echo` (without redirection) - Printing text
- `diff`, `stat`, `file` - File analysis

## Accept Edits Mode and Safety

"Accept Edits" mode auto-approves most operations, but **destructive commands still prompt**.

### How It Works

| Mode | Safe Command (`ls`) | Destructive Command (`rm`) |
|------|---------------------|---------------------------|
| Ask (default) | Prompts | Prompts |
| Accept Edits | Auto-approves | **Still prompts** |
| Deny | Blocks | Blocks |

This means you can use Accept Edits for fast iteration while still being protected from accidental destruction.

### Example

With Accept Edits enabled:
```
You: "List the files in /tmp"
Claude: [Runs ls /tmp automatically]

You: "Delete old_backup.tar.gz"
Claude: ⚠️ Confirm: rm old_backup.tar.gz? [y/N]
```

## File Reference Safety

Claude is careful about file references in destructive operations.

### Explicit Paths

When you provide an explicit path, Claude uses it directly:
```
You: "Delete /tmp/cache/old_data.json"
Claude: [Confirms with exact path shown]
```

### Contextual References

When you say "that file" or "the file", Claude:

1. **States the file explicitly:**
   ```
   You: "Delete that file"
   Claude: "I'll delete the file we discussed: /tmp/test.txt
            Are you sure? [y/N]"
   ```

2. **Asks for clarification if ambiguous:**
   ```
   You: "Delete that file"
   Claude: "We discussed several files:
            - /tmp/file1.txt
            - /tmp/file2.txt
            Which one would you like to delete?"
   ```

### Why This Matters

Consider this scenario:
1. You discuss `/tmp/backup.tar.gz`
2. Later, you discuss `/home/user/important.doc`
3. You say "delete that file"

Without file reference safety, Claude might delete the wrong file. With it, Claude confirms exactly which file will be deleted.

## Overriding When Needed

Sometimes you need to run destructive commands without prompts. Here are your options:

### Option 1: Confirm Each Time

The safest approach - just type `y` when prompted.

### Option 2: Use Custom Hookify Rules

Create a rule to allow specific patterns:

```markdown
<!-- .claude/hookify.allow-tmp-cleanup.local.md -->
---
name: allow-tmp-cleanup
enabled: true
event: bash
pattern: rm\s+/tmp/cache/
action: warn  # warn instead of block
---

Note: Cleaning /tmp/cache/ directory.
```

### Option 3: Disable Specific Checks (Not Recommended)

You can disable rules by setting `enabled: false` in the rule file. This is not recommended for destructive command checks.

## Best Practices

### 1. Trust the Prompts

Confirmation prompts exist because the command could cause damage. Take a moment to verify:
- Is this the right file/directory?
- Do you have a backup if needed?
- Is this what you actually intended?

### 2. Be Specific

Instead of:
```
"Delete the old files"
```

Be explicit:
```
"Delete /tmp/cache/*.log files older than 7 days"
```

### 3. Use Dry-Run First

For complex cleanup operations, ask Claude to show you what would be deleted:
```
"Show me which files would be deleted by rm -rf ./old_*"
```

Then confirm:
```
"Okay, go ahead and delete those files"
```

### 4. Review Before Critical Operations

For operations on production data or important files:
1. Ask Claude to explain what the command will do
2. Review the exact command
3. Consider if you have backups
4. Then confirm

### 5. Use Version Control

When working in code repositories:
```
"Delete the unused test fixtures, but first show me git status"
```

This lets you verify changes before they're permanent.

## Troubleshooting

### "My command was blocked but I need to run it"

1. Check if the block is from a hookify rule (`/hookify:list`)
2. If needed, disable the specific rule
3. Or add an exception for your use case

### "I'm getting too many prompts"

1. Consider using Accept Edits mode for safe commands
2. Create hookify rules for common safe patterns
3. Be more explicit in your requests to reduce ambiguity

### "Claude deleted the wrong file"

1. Check if you were explicit about which file
2. Review your conversation for ambiguous references
3. Consider enabling stricter file reference confirmation

## Getting Help

- Use `/bug` to report safety feature issues
- Check the [Developer Guide](./developer-guide.md) for technical details
- See [hookify documentation](../../plugins/hookify/README.md) for custom rules
