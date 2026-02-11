---
name: default-destructive-command-protection
enabled: true
event: bash
pattern: \brm\s+(-[rfivd]+\s+)*|rm\s+--|rmdir\b|\bdd\s+if=|\bmkfs\b|\bshred\b|:>|>\s*[/~]|\btruncate\b|chmod\s+777
action: ask
priority: high
isDefault: true
---

⚠️ **Potentially destructive command detected!**

This command may cause irreversible data loss or system changes:
- `rm` - Remove files/directories
- `rmdir` - Remove directories
- `dd if=` - Direct disk write (can destroy data)
- `mkfs` - Format filesystem
- `shred` - Secure delete (unrecoverable)
- `truncate` / `:>` - Empty file contents
- `chmod 777` - Insecure permissions
- `> /path` - Redirect that may overwrite system files

Please confirm you want to execute this operation.

**To disable this safety prompt:**
Add to your settings (`~/.claude.json` or `.claude/settings.json`):
```json
{
  "hookify": {
    "disableDefaultHooks": true
  }
}
```
