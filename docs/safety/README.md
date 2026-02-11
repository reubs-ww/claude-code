# Safety Features Documentation

This directory contains documentation for Claude Code's safety features, which help protect against accidental execution of destructive commands.

## Quick Links

- [User Guide](./user-guide.md) - Understanding and using safety features
- [Developer Guide](./developer-guide.md) - Implementing and extending safety features

## Overview

Claude Code includes several layers of safety to prevent accidental data loss:

### 1. Intent Recognition

Claude distinguishes between requests to *see* a command versus *run* a command:

```
"Show me the command to delete files"  → Displays code, doesn't execute
"Run the command to delete files"      → Executes (with confirmation)
```

### 2. Destructive Command Detection

Potentially dangerous commands trigger confirmation before execution:

- File deletion (`rm`, `rm -rf`)
- Disk operations (`dd`, `mkfs`, `format`)
- System changes (`chmod 777`, `kill -9`, `reboot`)
- Database operations (`DROP DATABASE`, `DELETE FROM`)

### 3. Accept Edits Override

Even with "Accept Edits" mode enabled (auto-approve), destructive commands still require explicit confirmation. Safe read-only commands auto-approve, but dangerous operations always prompt.

### 4. File Reference Handling

When referring to files contextually ("delete that file"), Claude:
- States the full file path explicitly before proceeding
- Asks for clarification if multiple files were discussed
- Requests explicit paths for ambiguous references

## Using Hookify for Custom Safety Rules

The [hookify plugin](../../plugins/hookify/) allows you to create custom safety rules without coding:

```markdown
---
name: block-production-db
enabled: true
event: bash
pattern: DROP.*production
action: block
---

Production database operations are blocked for safety.
```

See the [hookify README](../../plugins/hookify/README.md) for detailed usage.

## Related Plugins

- **[hookify](../../plugins/hookify/)** - Create custom hook rules
- **[security-guidance](../../plugins/security-guidance/)** - Security pattern warnings

## Testing

Safety feature tests are located in `tests/safety/`:

```bash
# Run all safety tests
pytest tests/safety/ -v

# Run specific test category
pytest tests/safety/test_destructive_commands.py -v
```
