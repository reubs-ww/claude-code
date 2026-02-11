# WinGet Package Manifest for Claude Code

This directory contains the WinGet (Windows Package Manager) manifest files for the `Anthropic.ClaudeCode` package.

## Directory Structure

```
winget/
├── README.md                              # This file
└── manifests/
    └── a/
        └── Anthropic/
            └── ClaudeCode/
                ├── Anthropic.ClaudeCode.yaml              # Version manifest
                ├── Anthropic.ClaudeCode.installer.yaml    # Installer manifest
                └── Anthropic.ClaudeCode.locale.en-US.yaml # Locale manifest
```

## Manifest Files

### Version Manifest (`.yaml`)
Contains the package version and references other manifests.

### Installer Manifest (`.installer.yaml`)
Contains installer-specific information:
- Download URLs for each architecture
- SHA256 checksums
- Installation switches
- Dependencies
- Product codes

### Locale Manifest (`.locale.en-US.yaml`)
Contains user-facing metadata:
- Package description
- Publisher information
- Documentation links
- Installation notes

## Coexistence with Claude Desktop

Claude Code (CLI tool) is designed to coexist with Claude Desktop (GUI application). Key design decisions:

1. **Separate Package Identifiers**:
   - Claude Code: `Anthropic.ClaudeCode`
   - Claude Desktop: `Anthropic.Claude` or `Anthropic.ClaudeDesktop`

2. **Unique Product Codes**: Each package has distinct product codes to prevent Windows Installer conflicts.

3. **User-Scope Installation**: Claude Code installs per-user by default, reducing conflicts and avoiding admin requirements.

4. **PATH Considerations**: Both packages may provide a `claude` command. Users can:
   - Use the full executable path
   - Configure PATH priority
   - Create shell aliases

5. **Installation Notes**: The locale manifest includes guidance for users who have both packages installed.

## Updating for New Releases

When releasing a new version of Claude Code:

1. **Update Version Number** in all three manifest files:
   ```yaml
   PackageVersion: "X.Y.Z"
   ```

2. **Update Installer URLs** in the installer manifest:
   ```yaml
   InstallerUrl: https://github.com/anthropics/claude-code/releases/download/vX.Y.Z/claude-code-win-x64.exe
   ```

3. **Calculate SHA256 Checksums** for each installer:
   ```powershell
   Get-FileHash -Algorithm SHA256 claude-code-win-x64.exe
   ```

4. **Update SHA256** in the installer manifest:
   ```yaml
   InstallerSha256: <calculated-hash>
   ```

5. **Update Release Notes URL** if needed in the locale manifest.

## Submitting to winget-pkgs

To publish updates to the official WinGet repository:

1. Fork [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)

2. Copy the updated manifest files to:
   ```
   manifests/a/Anthropic/ClaudeCode/<version>/
   ```

3. Validate the manifest:
   ```powershell
   winget validate manifests/a/Anthropic/ClaudeCode/<version>/
   ```

4. Test the installation:
   ```powershell
   winget install --manifest manifests/a/Anthropic/ClaudeCode/<version>/
   ```

5. Submit a pull request to `microsoft/winget-pkgs`

## Validation

Before submitting, validate the manifest locally:

```powershell
# Validate manifest structure
winget validate .\winget\manifests\a\Anthropic\ClaudeCode\

# Test installation from local manifest
winget install --manifest .\winget\manifests\a\Anthropic\ClaudeCode\
```

## References

- [WinGet Manifest Schema](https://github.com/microsoft/winget-cli/blob/master/doc/ManifestSpecv1.9.md)
- [Creating a Package Manifest](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest)
- [winget-pkgs Contributing Guide](https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md)
