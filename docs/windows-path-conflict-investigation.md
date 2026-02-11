# Windows PATH and Binary Registration Conflict Investigation

**Issue:** When Claude Desktop/Cowork is installed on Windows, running `claude` in PowerShell opens Claude Desktop instead of Claude Code CLI, accompanied by a deprecation warning.

**Related GitHub Issues:**
- [#24855](https://github.com/anthropics/claude-code/issues/24855) - Claude Desktop opening when running "claude" in Powershell (Windows)
- [#24749](https://github.com/anthropics/claude-code/issues/24749) - Chrome MCP: intermittent Native Messaging connection failure when Desktop + CLI coexist (Windows)
- [#24859](https://github.com/anthropics/claude-code/issues/24859) - Claude Cowork for Windows, plugin skills searched at wrong location

## Executive Summary

The conflict occurs because **Claude Desktop/Cowork registers its own `claude` command** that takes precedence over Claude Code CLI due to PATH ordering on Windows. This is compounded by the fact that both applications:

1. Register binaries with the same name (`claude`)
2. Create Native Messaging Host entries for the same Chrome extension
3. Use different underlying runtimes (Electron/Node.js vs standalone binary)

## Installation Paths

### Claude Code CLI (Native Installation)

**Installation Script:** `https://claude.ai/install.ps1`

The bootstrap script:
1. Downloads `claude.exe` to `$env:USERPROFILE\.claude\downloads\`
2. Runs `claude install` which:
   - Installs the binary to `%USERPROFILE%\.local\bin\claude.exe`
   - Stores version files in `%USERPROFILE%\.local\share\claude\`
   - Adds `%USERPROFILE%\.local\bin` to the user PATH

**Key paths:**
```
%USERPROFILE%\.local\bin\claude.exe          # Main binary
%USERPROFILE%\.local\share\claude\           # Version and update files
%USERPROFILE%\.claude\                       # Configuration directory
%USERPROFILE%\.claude.json                   # Global state file
```

### Claude Desktop/Cowork

Claude Desktop (also known as Cowork on Windows) is an Electron-based application installed via:
- Microsoft Store (MSIX package)
- Direct download installer

**Key paths:**
```
%LOCALAPPDATA%\AnthropicClaude\app-X.X.XXXX\    # Application directory
%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\   # MSIX package data (if Store installed)
%APPDATA%\Claude\                               # Configuration and native host manifests
```

**Windows Registry entries:**
- App Paths: `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe`
- Native Messaging Hosts: `HKCU\SOFTWARE\Google\Chrome\NativeMessagingHosts\`

## Root Cause Analysis

### Primary Issue: PATH/App Paths Conflict

When Claude Desktop is installed, it registers itself in multiple ways:

1. **App Paths Registry Key**: Windows' App Paths feature (`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe`) allows applications to be found without being in PATH. This takes precedence over PATH entries in PowerShell and CMD.

2. **MSIX Virtual Registry**: When installed from the Microsoft Store, Claude Desktop runs in an MSIX container with virtualized registry entries that map the `claude` command to the Desktop app.

3. **PATH Order**: Even if both entries are in PATH, the Desktop installation may come first.

### fs.Stats Deprecation Warning

The deprecation warning:
```
(node:11048) [DEP0180] DeprecationWarning: fs.Stats constructor is deprecated.
```

**Origin:** This warning comes from Claude Desktop's Electron process (which embeds Node.js). The warning is triggered when:
- The Desktop app starts its Node.js runtime
- Code within Electron or its dependencies uses the deprecated `fs.Stats` constructor directly
- This was deprecated in Node.js v22.0.0 (runtime deprecation) and v20.13.0 (documentation deprecation)

**Key insight:** This warning appears when Claude **Desktop** starts, not Claude Code CLI. This confirms that running `claude` is launching the Desktop app instead of the CLI.

### Native Messaging Host Conflict (Related Issue)

Both applications register Chrome Native Messaging Hosts:

| Application | Registry Path | Host Name |
|------------|---------------|-----------|
| Claude Desktop | `%APPDATA%\Claude\ChromeNativeHost\` | `com.anthropic.claude_browser_extension` |
| Claude Code CLI | `%APPDATA%\Claude Code\ChromeNativeHost\` | `com.anthropic.claude_code_browser_extension` |

Both claim to handle the same Chrome extension ID (`fcoeoabgfenejglbffodgkkbkcdhcgfn`), causing intermittent connection failures.

## Conflict Scenarios

### Scenario 1: Fresh Claude Desktop Install After CLI

1. User has Claude Code CLI installed at `%USERPROFILE%\.local\bin\claude.exe`
2. User installs Claude Desktop
3. Desktop installation adds App Paths registry entry
4. Running `claude` now finds Desktop first via App Paths lookup
5. Desktop launches with Node.js deprecation warning
6. CLI is shadowed/unreachable via simple `claude` command

### Scenario 2: MSIX Store Installation

1. MSIX package creates virtualized app entries
2. Windows shell integration maps `claude` to the packaged app
3. This bypasses traditional PATH entirely
4. User PATH modifications have no effect

## Proposed Solutions

### Short-term Workarounds

**For users experiencing this issue:**

1. **Use full path to CLI:**
   ```powershell
   & "$env:USERPROFILE\.local\bin\claude.exe"
   ```

2. **Create an alias in PowerShell profile:**
   ```powershell
   # Add to $PROFILE
   Set-Alias -Name claude-code -Value "$env:USERPROFILE\.local\bin\claude.exe"
   ```

3. **Remove Desktop's App Paths entry:**
   ```powershell
   # WARNING: May break Desktop launch from Run dialog
   Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe" -Name "(Default)" -ErrorAction SilentlyContinue
   ```

### Long-term Fixes (Recommendations)

#### Option A: Different Binary Names (Recommended)

Rename one of the binaries to avoid collision:
- Claude Code CLI: `claude` or `claude-code`
- Claude Desktop: `claude-desktop` or `claudedesktop`

**Pros:**
- Eliminates ambiguity completely
- Users can have both installed without conflict
- Clear distinction between CLI and GUI applications

**Cons:**
- Requires updating documentation and user habits
- Breaking change for existing users

#### Option B: Unified Dispatcher

Create a single `claude` command that:
1. Detects the calling context (terminal vs GUI launch)
2. Routes to appropriate application
3. Provides `--cli` / `--desktop` flags for explicit selection

**Pros:**
- Single entry point
- Context-aware behavior

**Cons:**
- Additional complexity
- Potential for confusion about which app will launch

#### Option C: Installer Conflict Detection

Modify both installers to:
1. Detect if the other application is installed
2. Warn user about potential conflicts
3. Offer to configure alternative command names or aliases

**Pros:**
- Preserves current naming
- Gives user control

**Cons:**
- Requires coordination between teams
- Doesn't solve existing installations

#### Option D: Fix PATH Priority in CLI Installer

Modify Claude Code CLI's Windows installer to:
1. Check for Claude Desktop App Paths entry
2. Either remove/rename it, or add CLI path with higher priority
3. Document the conflict in installation output

### Additional Recommendations

1. **Fix fs.Stats deprecation in Desktop:**
   Update Electron or dependencies to avoid deprecated `fs.Stats` constructor usage.

2. **Document coexistence:**
   Add Windows-specific documentation about running both applications.

3. **Native Messaging Host isolation:**
   Use different extension IDs or implement proper host routing to prevent MCP connection conflicts.

## Testing Verification

To reproduce and verify the issue:

```powershell
# Check what 'claude' resolves to
Get-Command claude

# Check App Paths registry
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe" -ErrorAction SilentlyContinue

# Check PATH order
$env:PATH -split ';' | Where-Object { $_ -like "*claude*" -or $_ -like "*Anthropic*" }

# Check which binary runs
& claude --version  # Should show CLI version if correct
claude doctor       # CLI diagnostic command
```

## Conclusion

The root cause is a **naming collision** between Claude Code CLI and Claude Desktop, where both register the `claude` command. The Windows App Paths feature and MSIX virtualization give Desktop priority over the CLI's PATH entry.

The recommended fix is **Option A: Different Binary Names** - renaming one of the applications to eliminate ambiguity. This provides the cleanest user experience and allows both applications to coexist without conflict.

The fs.Stats deprecation warning is a secondary issue within Claude Desktop's Electron runtime that should be addressed separately by updating to a version of Node.js/Electron that doesn't trigger this warning.
