---
name: check-binary
description: Check which Claude binary (CLI vs Desktop) is being used and diagnose potential conflicts
---

# Claude Binary Check

You are helping the user diagnose which Claude product is being invoked when they run the `claude` command.

## Task

Run the check-version script to analyze the user's Claude binary configuration and provide a clear report.

## Steps

1. Run the binary check script:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks-handlers/check-version.sh"
```

2. Analyze the output and summarize the findings:
   - Which Claude product is currently being used (CLI vs Desktop)
   - Whether there are any conflicts detected
   - What actions (if any) the user should take

3. If the user is running Claude Desktop when they expected Claude Code CLI, provide step-by-step instructions for resolution based on their operating system.

## Key Points to Check

- **Binary Path**: Where is the `claude` command resolving to?
- **Version Output**: Does `claude --version` show `@anthropic-ai/claude-code`?
- **Multiple Installations**: Are both products installed?
- **PATH Order**: Is the correct binary first in PATH?

## Common Resolutions

### Windows
- Reorder PATH to put npm bin directory before Claude Desktop
- Use `npx @anthropic-ai/claude-code` as an alternative
- Create a separate alias for Claude Code CLI

### macOS/Linux
- Ensure npm global bin is in PATH
- Check shell profile (.bashrc, .zshrc) for correct PATH order
- Use `npx @anthropic-ai/claude-code` as an alternative
