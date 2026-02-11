# File Reference Validation Plugin

A Claude Code plugin that helps prevent accidental file deletion when users reference files contextually (e.g., "delete the file I mentioned before", "rm that file", "remove it").

## Problem Statement

When users ask Claude to perform destructive operations on files using contextual references like "the file I mentioned" or "that file", there's a risk of targeting the wrong file if:

- Multiple files were discussed in the conversation
- The file reference is ambiguous
- Claude picks up the wrong file from conversation history
- The files were in different directories

This plugin adds validation layers to ensure Claude explicitly identifies and confirms the target file before performing destructive operations.

## Features

### 1. Session Start Guidance

Injects guidance at session start that instructs Claude to:

- Always identify the most recently mentioned file
- Explicitly state the target file path before destructive operations
- Wait for confirmation when the file path was inferred from context
- Warn when multiple files could match a reference

### 2. Destructive Command Validation Hook

A PreToolUse hook for Bash commands that:

- Detects destructive commands (`rm`, `rmdir`, `unlink`, `shred`, `del`, `trash`)
- Extracts file paths from the command
- Blocks the first attempt with a validation reminder
- Allows the command on retry (after Claude has presumably verified)

## Installation

1. Copy this plugin directory to your plugins location
2. Enable the plugin in your Claude Code settings:

```json
{
  "plugins": ["file-reference-validation"]
}
```

Or install from a marketplace that includes this plugin.

## Configuration

### Disable Validation

To disable the PreToolUse validation hook (while keeping session guidance), set the environment variable:

```bash
export DISABLE_FILE_REFERENCE_VALIDATION=1
```

## How It Works

### Flow for Destructive Commands

1. User says: "delete the file I mentioned before"
2. Claude attempts: `rm /path/to/file.ext`
3. Hook blocks the command and shows validation reminder
4. Claude sees the warning and either:
   - Confirms with user if the path is correct
   - Re-runs the command if confident
5. On retry, the command is allowed

### Key Patterns Detected

The hook watches for phrases like:
- "delete the file I mentioned"
- "remove that file"
- "rm it"
- "delete the one we discussed"
- "get rid of that"
- Any destructive command with pronoun/demonstrative references

## Files

```
file-reference-validation/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── hooks/
│   └── hooks.json               # Hook definitions
├── hooks-handlers/
│   ├── session-start.sh         # Injects guidance at session start
│   └── destructive_command_validator.py  # Validates destructive commands
└── README.md                    # This documentation
```

## Debug Logs

The hook writes debug logs to `/tmp/file-reference-validation-log.txt` for troubleshooting.

## Related Safety Features

This plugin complements other Claude Code safety features:

- **security-guidance**: Warns about security vulnerabilities in code
- **Permission system**: Controls which tools Claude can use
- **Sandbox mode**: Restricts file system access

## Contributing

When improving this plugin:

1. Test with various destructive command patterns
2. Ensure the hook doesn't block legitimate operations
3. Keep the validation reminder concise but informative
4. Consider edge cases like piped commands and xargs
