# Startup Detection Plugin

This plugin helps detect and resolve binary invocation conflicts, particularly when both Claude Code CLI and Claude Desktop are installed on the same system.

## Problem

On Windows (and potentially other platforms), users may have both:
- **Claude Code CLI** - The command-line interface installed via npm (`npm install -g @anthropic-ai/claude-code`)
- **Claude Desktop** - The Electron-based desktop application

Both products may register a `claude` command, leading to confusion about which one is being invoked when the user types `claude` in their terminal.

## What This Plugin Does

At session start, this plugin checks for potential conflicts by:

1. **Checking the invocation path** - Determines if the `claude` command is resolving to Claude Desktop instead of Claude Code CLI
2. **Detecting Claude Desktop installation** - Looks for known Claude Desktop installation paths
3. **Checking environment indicators** - Identifies environment variables that might indicate running in the wrong context
4. **Detecting running processes** - Checks if Claude Desktop is currently running

## Resolution Steps

If a conflict is detected, the plugin provides guidance:

1. Check which `claude` is in your PATH:
   - Unix/macOS: `which claude`
   - Windows: `where claude`

2. For Claude Code CLI, ensure npm global bin is in PATH:
   ```bash
   npm bin -g
   ```

3. You can also run Claude Code directly:
   ```bash
   npx @anthropic-ai/claude-code
   ```

4. On Windows, you may need to reorder PATH entries to prioritize the npm bin directory

## Verifying Your Binary

To verify you're running Claude Code CLI:
- The command `claude --version` shows `@anthropic-ai/claude-code`
- The binary path contains `npm`, `node_modules`, or similar

## Installation

This plugin is included in the Claude Code repository. To use it in your own projects, copy the `plugins/startup-detection` directory to your project's plugins folder.

## Configuration

No configuration required. The plugin runs automatically at session start.

## Disabling

To disable this plugin, remove or rename the `plugins/startup-detection` directory, or remove the `hooks/hooks.json` file.

## fs.Stats Deprecation Warning (DEP0180)

If you see a deprecation warning about `fs.Stats` (DEP0180), this is a Node.js warning about using legacy methods on `fs.Stats` objects. The warning appears when code uses `.isFile()`, `.isDirectory()`, or similar methods on stats objects.

### Identifying the Source

The warning may come from:
1. The Claude Code CLI itself
2. A dependency of Claude Code CLI
3. Other Node.js tools in your environment

To identify the source:

```bash
# Run with --trace-deprecation to see the stack trace
node --trace-deprecation $(which claude) --version

# Or set the environment variable
NODE_OPTIONS="--trace-deprecation" claude --version
```

### Suppressing the Warning

To suppress deprecation warnings (not recommended for development):

```bash
# Run without deprecation warnings
node --no-deprecation $(which claude) [arguments]

# Or set environment variable
NODE_OPTIONS="--no-deprecation" claude [arguments]
```

### For Claude Code CLI Developers

If this warning originates from Claude Code CLI source code, the fix involves updating code that uses legacy `fs.Stats` methods. For example:

```javascript
// Legacy (triggers DEP0180)
const stats = fs.statSync(path);
if (stats.isFile()) { ... }

// Updated (no warning)
const stats = fs.statSync(path);
if (stats.mode & fs.constants.S_IFREG) { ... }

// Or use fs.promises with stat check
const stats = await fs.promises.stat(path);
// Then check stats.isFile() on the returned StatsBase
```

Note: As of Node.js 22+, the `Stats` class methods like `.isFile()` and `.isDirectory()` are deprecated. Use the `StatsBase` class methods or mode checks instead.

## Slash Command

This plugin provides a `/check-binary` command that can be invoked to manually check your binary configuration:

```
/check-binary
```

This runs a comprehensive diagnostic and provides recommendations.

## Files

- `hooks/hooks.json` - Hook configuration for SessionStart
- `hooks-handlers/detect-binary.sh` - Main detection script
- `hooks-handlers/check-version.sh` - Detailed version check utility
- `commands/check-binary.md` - Slash command for manual checks
