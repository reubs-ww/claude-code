# Claude Code Windows Uninstallation Script
# This script removes Claude Code CLI and cleans up related files.
#
# Usage: .\uninstall.ps1 [-KeepConfig] [-Force]

param(
    [Parameter()]
    [switch]$KeepConfig,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration
# ============================================================================

$INSTALL_DIR = "$env:USERPROFILE\.local\bin"
$DATA_DIR = "$env:USERPROFILE\.local\share\claude"
$CONFIG_DIR = "$env:USERPROFILE\.claude"
$STATE_FILE = "$env:USERPROFILE\.claude.json"
$DOWNLOAD_DIR = "$env:USERPROFILE\.claude\downloads"

$CLI_BINARY_NAME = "claude.exe"
$CLI_ALIAS_NAME = "claude-code.exe"

# Colors for output
$script:ColorInfo = "Cyan"
$script:ColorSuccess = "Green"
$script:ColorWarning = "Yellow"
$script:ColorError = "Red"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor $script:ColorInfo
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor $script:ColorSuccess
}

function Write-Warn {
    param([string]$Message)
    Write-Host "WARNING: $Message" -ForegroundColor $script:ColorWarning
}

function Write-Err {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor $script:ColorError
}

# ============================================================================
# Uninstallation Functions
# ============================================================================

function Remove-ClaudeCodeBinaries {
    $removed = @()

    # Remove main binary
    $mainBinary = Join-Path $INSTALL_DIR $CLI_BINARY_NAME
    if (Test-Path $mainBinary) {
        try {
            Remove-Item -Path $mainBinary -Force
            $removed += $mainBinary
            Write-Info "Removed: $mainBinary"
        }
        catch {
            Write-Warn "Could not remove $mainBinary : $_"
        }
    }

    # Remove alias binary
    $aliasBinary = Join-Path $INSTALL_DIR $CLI_ALIAS_NAME
    if (Test-Path $aliasBinary) {
        try {
            Remove-Item -Path $aliasBinary -Force
            $removed += $aliasBinary
            Write-Info "Removed: $aliasBinary"
        }
        catch {
            Write-Warn "Could not remove $aliasBinary : $_"
        }
    }

    return $removed
}

function Remove-ClaudeCodeData {
    $removed = @()

    # Remove data directory
    if (Test-Path $DATA_DIR) {
        try {
            Remove-Item -Path $DATA_DIR -Recurse -Force
            $removed += $DATA_DIR
            Write-Info "Removed: $DATA_DIR"
        }
        catch {
            Write-Warn "Could not remove $DATA_DIR : $_"
        }
    }

    # Remove downloads directory
    if (Test-Path $DOWNLOAD_DIR) {
        try {
            Remove-Item -Path $DOWNLOAD_DIR -Recurse -Force
            $removed += $DOWNLOAD_DIR
            Write-Info "Removed: $DOWNLOAD_DIR"
        }
        catch {
            Write-Warn "Could not remove $DOWNLOAD_DIR : $_"
        }
    }

    return $removed
}

function Remove-ClaudeCodeConfig {
    $removed = @()

    # Remove config directory
    if (Test-Path $CONFIG_DIR) {
        try {
            Remove-Item -Path $CONFIG_DIR -Recurse -Force
            $removed += $CONFIG_DIR
            Write-Info "Removed: $CONFIG_DIR"
        }
        catch {
            Write-Warn "Could not remove $CONFIG_DIR : $_"
        }
    }

    # Remove state file
    if (Test-Path $STATE_FILE) {
        try {
            Remove-Item -Path $STATE_FILE -Force
            $removed += $STATE_FILE
            Write-Info "Removed: $STATE_FILE"
        }
        catch {
            Write-Warn "Could not remove $STATE_FILE : $_"
        }
    }

    return $removed
}

function Remove-PathEntry {
    <#
    .SYNOPSIS
    Removes Claude Code install directory from the user PATH.
    #>

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne "" }

    $installDirNormalized = $INSTALL_DIR.ToLower().TrimEnd('\')
    $newEntries = $pathEntries | Where-Object {
        $_.ToLower().TrimEnd('\') -ne $installDirNormalized
    }

    if ($newEntries.Count -lt $pathEntries.Count) {
        $newPath = $newEntries -join ';'
        try {
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Info "Removed $INSTALL_DIR from PATH"
            return $true
        }
        catch {
            Write-Warn "Could not update PATH: $_"
            return $false
        }
    }

    return $false
}

function Test-ClaudeCodeInstalled {
    $mainBinary = Join-Path $INSTALL_DIR $CLI_BINARY_NAME
    $aliasBinary = Join-Path $INSTALL_DIR $CLI_ALIAS_NAME

    return (Test-Path $mainBinary) -or (Test-Path $aliasBinary) -or (Test-Path $DATA_DIR)
}

# ============================================================================
# Main Uninstallation Flow
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "Claude Code CLI Uninstaller" -ForegroundColor $script:ColorInfo
    Write-Host "===========================" -ForegroundColor $script:ColorInfo
    Write-Host ""

    # Check if Claude Code is installed
    if (-not (Test-ClaudeCodeInstalled)) {
        Write-Info "Claude Code CLI does not appear to be installed."
        Write-Host ""
        return
    }

    # Confirm uninstallation
    if (-not $Force) {
        Write-Host "This will remove Claude Code CLI from your system." -ForegroundColor $script:ColorWarning
        if (-not $KeepConfig) {
            Write-Host "All configuration and data will be deleted." -ForegroundColor $script:ColorWarning
        }
        else {
            Write-Host "Configuration files will be preserved." -ForegroundColor $script:ColorInfo
        }
        Write-Host ""
        Write-Host "Press Enter to continue, or Ctrl+C to cancel..." -ForegroundColor $script:ColorWarning
        $null = Read-Host
    }

    $totalRemoved = @()

    # Remove binaries
    Write-Host ""
    Write-Info "Removing binaries..."
    $totalRemoved += Remove-ClaudeCodeBinaries

    # Remove data
    Write-Host ""
    Write-Info "Removing data..."
    $totalRemoved += Remove-ClaudeCodeData

    # Remove config if not keeping
    if (-not $KeepConfig) {
        Write-Host ""
        Write-Info "Removing configuration..."
        $totalRemoved += Remove-ClaudeCodeConfig
    }
    else {
        Write-Host ""
        Write-Info "Keeping configuration files at: $CONFIG_DIR"
    }

    # Update PATH
    Write-Host ""
    Write-Info "Cleaning up PATH..."
    Remove-PathEntry | Out-Null

    # Summary
    Write-Host ""
    if ($totalRemoved.Count -gt 0) {
        Write-Success "$([char]0x2705) Claude Code CLI has been uninstalled."
        Write-Host ""
        Write-Host "Removed $($totalRemoved.Count) item(s)." -ForegroundColor Gray
    }
    else {
        Write-Info "No files were removed."
    }

    if ($KeepConfig) {
        Write-Host ""
        Write-Host "Configuration preserved at:" -ForegroundColor $script:ColorInfo
        Write-Host "  $CONFIG_DIR" -ForegroundColor Gray
        Write-Host "  $STATE_FILE" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "NOTE: You may need to restart your terminal for changes to take effect." -ForegroundColor $script:ColorWarning
    Write-Host ""
}

# Run main uninstallation
Main
