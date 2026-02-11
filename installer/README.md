# Claude Code Windows Installer

This directory contains the Windows installation scripts for Claude Code CLI.

## Installation

**Recommended method:**
```powershell
irm https://claude.ai/install.ps1 | iex
```

**With specific version:**
```powershell
.\install.ps1 -Target 1.2.3
```

**Force reinstall:**
```powershell
.\install.ps1 -Force
```

## Features

### Conflict Detection with Claude Desktop

The installer automatically detects if Claude Desktop/Cowork is installed on the system. When detected:

1. **Warning displayed**: Users are notified about the potential conflict
2. **Alias created**: A `claude-code` command alias is created alongside `claude`
3. **PATH optimization**: Claude Code's install directory is moved to the front of the user PATH

This ensures users can always invoke Claude Code CLI using:
```powershell
claude-code
```

Even when Windows' App Paths registry gives Claude Desktop precedence over PATH entries.

### Detection Methods

The installer checks for Claude Desktop via:
- Windows App Paths registry (`HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe`)
- Common installation directories (`%LOCALAPPDATA%\AnthropicClaude`, etc.)
- MSIX package presence (`%LOCALAPPDATA%\Packages\Claude_*`)

### Installation Paths

```
%USERPROFILE%\.local\bin\claude.exe       # Main binary
%USERPROFILE%\.local\bin\claude-code.exe  # Alias (created if conflict detected)
%USERPROFILE%\.local\share\claude\        # Version and update files
%USERPROFILE%\.claude\                    # Configuration directory
%USERPROFILE%\.claude\downloads\          # Temporary download location
```

## Uninstallation

**Full removal:**
```powershell
.\uninstall.ps1
```

**Keep configuration:**
```powershell
.\uninstall.ps1 -KeepConfig
```

**Non-interactive:**
```powershell
.\uninstall.ps1 -Force
```

## Parameters

### install.ps1

| Parameter | Description |
|-----------|-------------|
| `-Target <version>` | Version to install (`latest`, `stable`, or semver like `1.2.3`) |
| `-Force` | Reinstall even if already installed, skip confirmation prompts |
| `-SkipConflictCheck` | Skip Claude Desktop detection |

### uninstall.ps1

| Parameter | Description |
|-----------|-------------|
| `-KeepConfig` | Preserve configuration files and state |
| `-Force` | Skip confirmation prompt |

## Windows PATH Conflict Background

On Windows, the App Paths registry takes precedence over PATH environment variable when resolving commands. When Claude Desktop is installed, it registers itself at:

```
HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe
```

This means running `claude` will launch Claude Desktop regardless of PATH ordering.

The `claude-code` alias provides a reliable way to invoke Claude Code CLI in this scenario.

For more details, see the Windows PATH Conflict Investigation document in the repository.
