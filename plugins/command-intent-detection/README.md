# Command Intent Detection Plugin

This plugin helps Claude distinguish between user requests to **display** commands (show as text) vs **execute** them (run via Bash tool).

## Problem

When a user says "give me the command to X", they typically want the command **displayed** so they can review it, not executed immediately. However, without explicit guidance, Claude may interpret this as "execute the command that would X", which is the opposite of user intent.

## Solution

This plugin injects guidance at session start that teaches Claude to recognize display-intent phrases and respond appropriately:

- **Display intent** (show command as code block): "give me the command", "show me the command", "what's the command", "what command would", "how would I..."
- **Execute intent** (use Bash tool): "run", "execute", "do", "perform", explicit action requests

## Installation

This plugin is included in the Claude Code repository. To use it in your projects:

1. Enable the plugin in your project's `.claude/settings.json`:
```json
{
  "plugins": ["command-intent-detection"]
}
```

2. Or install it via the `/plugin` command in Claude Code.

## How It Works

The plugin uses a `SessionStart` hook to inject additional context that guides Claude's interpretation of user requests involving commands:

1. When the session starts, the hook provides guidance on recognizing display vs execute intent
2. Claude uses this guidance to determine whether to show commands as text or execute them
3. When intent is ambiguous, Claude defaults to displaying the command and asking if execution is desired

## Examples

| User Request | Intent | Claude Response |
|-------------|--------|-----------------|
| "give me the command to delete node_modules" | Display | Shows: `rm -rf node_modules` |
| "run the tests" | Execute | Runs: `npm test` via Bash tool |
| "what's the command to restart the server" | Display | Shows: `npm run dev` |
| "show me how to check git status" | Display | Shows: `git status` |
| "please build the project" | Execute | Runs: `npm run build` via Bash tool |

## Plugin Structure

```
command-intent-detection/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── hooks/
│   └── hooks.json           # SessionStart hook configuration
├── hooks-handlers/
│   └── session-start.sh     # Injects intent detection guidance
└── README.md                # This file
```

## Configuration

The plugin is enabled by default when installed. No additional configuration is required.

## Related Plugins

- [security-guidance](../security-guidance/) - Warns about potential security issues when editing files
- [hookify](../hookify/) - Create custom hooks to prevent unwanted behaviors
