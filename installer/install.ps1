# Claude Code Windows Installation Script
# This script installs Claude Code CLI with proper conflict detection and resolution
# for systems where Claude Desktop/Cowork may also be installed.
#
# Usage: irm https://claude.ai/install.ps1 | iex
#        Or: .\install.ps1 [-Target <version>] [-Force] [-SkipConflictCheck]

param(
    [Parameter(Position=0)]
    [ValidatePattern('^(stable|latest|\d+\.\d+\.\d+(-[^\s]+)?)$')]
    [string]$Target = "latest",

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$SkipConflictCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# ============================================================================
# Configuration
# ============================================================================

$GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
$DOWNLOAD_DIR = "$env:USERPROFILE\.claude\downloads"
$INSTALL_DIR = "$env:USERPROFILE\.local\bin"
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
# Pre-Installation Checks
# ============================================================================

function Test-Is64Bit {
    if (-not [Environment]::Is64BitProcess) {
        Write-Err "Claude Code does not support 32-bit Windows. Please use a 64-bit version of Windows."
        exit 1
    }
}

function Get-ClaudeDesktopInfo {
    <#
    .SYNOPSIS
    Detects if Claude Desktop/Cowork is installed and returns information about it.
    #>
    $info = @{
        Installed = $false
        AppPathsEntry = $null
        InstallLocation = $null
        IsMSIX = $false
        BinaryPath = $null
    }

    # Check App Paths registry (takes precedence on Windows)
    $appPathsKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe"
    if (Test-Path $appPathsKey) {
        $appPathsValue = Get-ItemProperty -Path $appPathsKey -ErrorAction SilentlyContinue
        if ($appPathsValue -and $appPathsValue."(default)") {
            $info.AppPathsEntry = $appPathsValue."(default)"
            $info.Installed = $true
        }
    }

    # Check common Claude Desktop installation locations
    $desktopPaths = @(
        "$env:LOCALAPPDATA\AnthropicClaude",
        "$env:LOCALAPPDATA\Programs\Claude",
        "$env:PROGRAMFILES\Claude"
    )

    foreach ($path in $desktopPaths) {
        if (Test-Path $path) {
            $info.InstallLocation = $path
            $info.Installed = $true

            # Find the actual executable
            $exePaths = Get-ChildItem -Path $path -Recurse -Filter "claude.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exePaths) {
                $info.BinaryPath = $exePaths.FullName
            }
            break
        }
    }

    # Check for MSIX/Store installation
    $msixPackagePath = "$env:LOCALAPPDATA\Packages\Claude_*"
    if (Test-Path $msixPackagePath) {
        $info.IsMSIX = $true
        $info.Installed = $true
    }

    return $info
}

function Get-ExistingClaudeCodeInfo {
    <#
    .SYNOPSIS
    Detects if Claude Code CLI is already installed.
    #>
    $info = @{
        Installed = $false
        BinaryPath = $null
        Version = $null
    }

    $cliPath = Join-Path $INSTALL_DIR $CLI_BINARY_NAME
    if (Test-Path $cliPath) {
        $info.Installed = $true
        $info.BinaryPath = $cliPath

        # Try to get version
        try {
            $versionOutput = & $cliPath --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $info.Version = $versionOutput -replace "claude-code\s+", "" | Select-Object -First 1
            }
        }
        catch {
            # Ignore version detection failures
        }
    }

    return $info
}

function Show-ConflictWarning {
    param(
        [hashtable]$DesktopInfo
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor $script:ColorWarning
    Write-Host " Claude Desktop/Cowork Detected" -ForegroundColor $script:ColorWarning
    Write-Host "============================================================" -ForegroundColor $script:ColorWarning
    Write-Host ""
    Write-Host "Claude Desktop is installed on this system. Both Claude Desktop"
    Write-Host "and Claude Code CLI use the 'claude' command, which can cause conflicts."
    Write-Host ""

    if ($DesktopInfo.AppPathsEntry) {
        Write-Host "  App Paths registry entry: $($DesktopInfo.AppPathsEntry)" -ForegroundColor Gray
    }
    if ($DesktopInfo.InstallLocation) {
        Write-Host "  Desktop location: $($DesktopInfo.InstallLocation)" -ForegroundColor Gray
    }
    if ($DesktopInfo.IsMSIX) {
        Write-Host "  Installed via: Microsoft Store (MSIX)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "To avoid conflicts, Claude Code CLI will be installed with an" -ForegroundColor $script:ColorInfo
    Write-Host "additional 'claude-code' command alias that you can use when" -ForegroundColor $script:ColorInfo
    Write-Host "the 'claude' command opens Desktop instead of CLI." -ForegroundColor $script:ColorInfo
    Write-Host ""
    Write-Host "After installation, you can use either:" -ForegroundColor White
    Write-Host "  - 'claude-code' (always opens CLI)" -ForegroundColor Green
    Write-Host "  - 'claude' (may open Desktop if it takes precedence)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor $script:ColorWarning
    Write-Host ""
}

function Test-CommandExists {
    param([string]$Command)

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        if (Get-Command $Command) { return $true }
    }
    catch { }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    return $false
}

# ============================================================================
# Installation Functions
# ============================================================================

function Get-LatestVersion {
    try {
        $version = Invoke-RestMethod -Uri "$GCS_BUCKET/latest" -ErrorAction Stop
        return $version.Trim()
    }
    catch {
        Write-Err "Failed to get latest version: $_"
        exit 1
    }
}

function Get-Manifest {
    param([string]$Version)

    try {
        $manifest = Invoke-RestMethod -Uri "$GCS_BUCKET/$Version/manifest.json" -ErrorAction Stop
        return $manifest
    }
    catch {
        Write-Err "Failed to get manifest: $_"
        exit 1
    }
}

function Install-ClaudeCodeBinary {
    param(
        [string]$Version,
        [hashtable]$Manifest,
        [bool]$CreateAlias
    )

    # Always use x64 for Windows (ARM64 Windows can run x64 through emulation)
    $platform = "win32-x64"
    $checksum = $Manifest.platforms.$platform.checksum

    if (-not $checksum) {
        Write-Err "Platform $platform not found in manifest"
        exit 1
    }

    # Create download directory
    New-Item -ItemType Directory -Force -Path $DOWNLOAD_DIR | Out-Null

    # Download binary
    $binaryPath = "$DOWNLOAD_DIR\claude-$Version-$platform.exe"
    Write-Info "Downloading Claude Code $Version..."

    try {
        Invoke-WebRequest -Uri "$GCS_BUCKET/$Version/$platform/claude.exe" -OutFile $binaryPath -ErrorAction Stop
    }
    catch {
        Write-Err "Failed to download binary: $_"
        if (Test-Path $binaryPath) {
            Remove-Item -Force $binaryPath
        }
        exit 1
    }

    # Verify checksum
    Write-Info "Verifying download..."
    $actualChecksum = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()

    if ($actualChecksum -ne $checksum) {
        Write-Err "Checksum verification failed"
        Write-Err "  Expected: $checksum"
        Write-Err "  Got: $actualChecksum"
        Remove-Item -Force $binaryPath
        exit 1
    }

    # Run the internal installer
    Write-Info "Setting up Claude Code..."
    try {
        if ($Target -and $Target -ne "latest") {
            & $binaryPath install $Target
        }
        else {
            & $binaryPath install
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Err "Installation failed with exit code $LASTEXITCODE"
            exit 1
        }
    }
    catch {
        Write-Err "Installation failed: $_"
        exit 1
    }
    finally {
        # Clean up downloaded file
        Start-Sleep -Seconds 1
        try {
            Remove-Item -Force $binaryPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warn "Could not remove temporary file: $binaryPath"
        }
    }

    # Create claude-code alias if needed
    if ($CreateAlias) {
        $cliPath = Join-Path $INSTALL_DIR $CLI_BINARY_NAME
        $aliasPath = Join-Path $INSTALL_DIR $CLI_ALIAS_NAME

        if (Test-Path $cliPath) {
            Write-Info "Creating 'claude-code' command alias..."
            try {
                # Create a copy of the binary as claude-code.exe
                Copy-Item -Path $cliPath -Destination $aliasPath -Force
                Write-Success "Created 'claude-code' alias at: $aliasPath"
            }
            catch {
                Write-Warn "Could not create 'claude-code' alias: $_"
                Write-Warn "You can still use the full path: $cliPath"
            }
        }
    }
}

function Update-PathPriority {
    <#
    .SYNOPSIS
    Ensures Claude Code's install directory is at the beginning of the user PATH.
    #>

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne "" }

    # Check if our install dir is already in PATH
    $installDirNormalized = $INSTALL_DIR.ToLower().TrimEnd('\')
    $existingIndex = -1

    for ($i = 0; $i -lt $pathEntries.Count; $i++) {
        if ($pathEntries[$i].ToLower().TrimEnd('\') -eq $installDirNormalized) {
            $existingIndex = $i
            break
        }
    }

    if ($existingIndex -eq 0) {
        # Already at the beginning, nothing to do
        return
    }

    if ($existingIndex -gt 0) {
        # Remove from current position
        $pathEntries = @($pathEntries[0..($existingIndex-1)]) + @($pathEntries[($existingIndex+1)..($pathEntries.Count-1)])
    }

    # Add to beginning
    $newPath = "$INSTALL_DIR;" + ($pathEntries -join ';')

    try {
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Info "Updated PATH to prioritize Claude Code CLI"
    }
    catch {
        Write-Warn "Could not update PATH priority: $_"
    }
}

function Show-PostInstallInfo {
    param(
        [bool]$HasConflict,
        [bool]$AliasCreated
    )

    Write-Host ""
    Write-Success "$([char]0x2705) Installation complete!"
    Write-Host ""

    if ($HasConflict) {
        Write-Host "Since Claude Desktop is also installed, we recommend using:" -ForegroundColor $script:ColorInfo
        Write-Host ""
        Write-Host "  claude-code    - Always launches Claude Code CLI" -ForegroundColor Green
        Write-Host ""
        Write-Host "The 'claude' command may open Claude Desktop due to Windows" -ForegroundColor Gray
        Write-Host "App Paths registry taking precedence over PATH entries." -ForegroundColor Gray
        Write-Host ""
        Write-Host "To make 'claude' always open CLI, see:" -ForegroundColor Gray
        Write-Host "https://code.claude.com/docs/en/troubleshooting#windows-claude-desktop-conflict" -ForegroundColor Cyan
    }
    else {
        Write-Host "Run 'claude' to get started!" -ForegroundColor $script:ColorInfo
    }

    Write-Host ""
    Write-Host "NOTE: You may need to restart your terminal for PATH changes to take effect." -ForegroundColor $script:ColorWarning
    Write-Host ""
}

# ============================================================================
# Main Installation Flow
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "Claude Code CLI Installer" -ForegroundColor $script:ColorInfo
    Write-Host "=========================" -ForegroundColor $script:ColorInfo
    Write-Host ""

    # Check system requirements
    Test-Is64Bit

    # Check for existing installations
    $desktopInfo = @{ Installed = $false }
    $hasConflict = $false
    $createAlias = $false

    if (-not $SkipConflictCheck) {
        $desktopInfo = Get-ClaudeDesktopInfo

        if ($desktopInfo.Installed) {
            $hasConflict = $true
            $createAlias = $true
            Show-ConflictWarning -DesktopInfo $desktopInfo

            if (-not $Force) {
                Write-Host "Press Enter to continue installation, or Ctrl+C to cancel..." -ForegroundColor $script:ColorWarning
                $null = Read-Host
            }
        }
    }

    # Check for existing Claude Code installation
    $existingCli = Get-ExistingClaudeCodeInfo
    if ($existingCli.Installed -and -not $Force) {
        Write-Info "Claude Code CLI is already installed at: $($existingCli.BinaryPath)"
        if ($existingCli.Version) {
            Write-Info "Current version: $($existingCli.Version)"
        }
        Write-Host ""
        Write-Host "Use -Force to reinstall, or run 'claude update' to update." -ForegroundColor $script:ColorInfo
        Write-Host ""

        # Still create alias if there's a conflict and it doesn't exist
        if ($hasConflict) {
            $aliasPath = Join-Path $INSTALL_DIR $CLI_ALIAS_NAME
            if (-not (Test-Path $aliasPath)) {
                Write-Info "Creating 'claude-code' alias for conflict resolution..."
                try {
                    Copy-Item -Path $existingCli.BinaryPath -Destination $aliasPath -Force
                    Write-Success "Created 'claude-code' alias"
                }
                catch {
                    Write-Warn "Could not create alias: $_"
                }
            }
        }

        return
    }

    # Get version info
    $version = Get-LatestVersion
    Write-Info "Latest version: $version"

    # Get manifest
    $manifest = Get-Manifest -Version $version

    # Install
    Install-ClaudeCodeBinary -Version $version -Manifest $manifest -CreateAlias $createAlias

    # Update PATH priority if there's a conflict
    if ($hasConflict) {
        Update-PathPriority
    }

    # Show completion message
    Show-PostInstallInfo -HasConflict $hasConflict -AliasCreated $createAlias
}

# Run main installation
Main
