# ──────────────────────────────────────────────────────────────────────
#  Zilliz CLI Installer (Windows PowerShell)
#
#  A unified CLI and TUI for managing Zilliz Cloud clusters
#  vector database operations.
#
#  Usage:
#    irm https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.ps1 | iex
#
#  Options (via environment variables):
#    $env:ZILLIZ_VERSION = "v0.1.0"          Install a specific version
#    $env:ZILLIZ_INSTALL_DIR = "C:\mypath"   Override install directory
#    $env:ZILLIZ_NO_MODIFY_PATH = "1"        Skip PATH modification
# ──────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ── Configuration ────────────────────────────────────────────────────
$PackageName      = "zilliz-cli"
$BinName          = "zilliz"
$Repo             = "zilliztech/zilliz-cli"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "zilliz-cli\bin"
$InstallDir       = if ($env:ZILLIZ_INSTALL_DIR) { $env:ZILLIZ_INSTALL_DIR } else { $DefaultInstallDir }
$RequestedVersion = if ($env:ZILLIZ_VERSION) { $env:ZILLIZ_VERSION } else { "latest" }

# ── Logging helpers ──────────────────────────────────────────────────
function Write-Info    { param($Msg) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param($Msg) Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "Warning: " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param($Msg) Write-Host "Error: " -ForegroundColor Red -NoNewline; Write-Host $Msg; exit 1 }

# ── Check if a command exists ────────────────────────────────────────
function Test-Command { param($Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ── Uninstall previous Python-based installation ────────────────────
function Uninstall-PythonVersion {
    $found = $false

    if ((Test-Command "pipx") -and ((& pipx list 2>$null) -match $PackageName)) {
        Write-Info "Found previous Python-based installation (pipx). Removing..."
        try { & pipx uninstall $PackageName 2>$null } catch {}
        $found = $true
    }

    if ((Test-Command "uv") -and ((& uv tool list 2>$null) -match $PackageName)) {
        Write-Info "Found previous Python-based installation (uv). Removing..."
        try { & uv tool uninstall $PackageName 2>$null } catch {}
        $found = $true
    }

    foreach ($pipCmd in @("pip3", "pip")) {
        if (Test-Command $pipCmd) {
            try {
                $showOutput = & $pipCmd show $PackageName 2>$null
                if ($showOutput) {
                    Write-Info "Found previous Python-based installation ($pipCmd). Removing..."
                    & $pipCmd uninstall -y $PackageName 2>$null
                    $found = $true
                    break
                }
            } catch {}
        }
    }

    if ($found) {
        Write-Success "Previous Python-based installation removed."
    }
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Binary (download from GitHub Releases)
# ══════════════════════════════════════════════════════════════════════
function Install-ViaBinary {
    # Detect architecture
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x86_64" }
        "ARM64" { "aarch64" }
        default { Write-Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }

    # Resolve version tag
    $tag = $RequestedVersion
    if ($tag -eq "latest") {
        Write-Info "Fetching latest release..."
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "zilliz-installer" }
        $tag = $release.tag_name
        if (-not $tag) { Write-Err "Failed to determine latest version" }
    }

    # Extract version number from tag (e.g. "zilliz-v1.0.1" -> "1.0.1")
    $version = $tag -replace '^zilliz-v', '' -replace '^v', ''
    Write-Info "Version: $version"

    # Build download URL
    $target = "${arch}-pc-windows-msvc"
    $archive = "${BinName}-${version}-${target}.zip"
    $url = "https://github.com/$Repo/releases/download/$tag/$archive"

    # Download
    $tmpDir = Join-Path $env:TEMP "zilliz-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        Write-Info "Downloading $url..."
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmpDir $archive) -UseBasicParsing

        # Checksum verification (optional)
        $checksumsUrl = "https://github.com/$Repo/releases/download/$tag/sha256sums.txt"
        try {
            Invoke-WebRequest -Uri $checksumsUrl -OutFile (Join-Path $tmpDir "sha256sums.txt") -UseBasicParsing
            $expectedHash = (Get-Content (Join-Path $tmpDir "sha256sums.txt") | Where-Object { $_ -match [regex]::Escape($archive) }) -split '\s+' | Select-Object -First 1
            $actualHash = (Get-FileHash -Path (Join-Path $tmpDir $archive) -Algorithm SHA256).Hash.ToLower()
            if ($expectedHash -and ($actualHash -ne $expectedHash)) {
                Write-Err "Checksum verification failed!`nExpected: $expectedHash`nGot:      $actualHash"
            }
            Write-Info "Checksum verified."
        } catch {
            Write-Warn "Checksum file not available, skipping verification."
        }

        # Extract
        Write-Info "Extracting to $InstallDir..."
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Expand-Archive -Path (Join-Path $tmpDir $archive) -DestinationPath $tmpDir -Force

        # Install binary
        Copy-Item -Path (Join-Path $tmpDir "${BinName}.exe") -Destination (Join-Path $InstallDir "${BinName}.exe") -Force

        # Create zz alias (short alias for zilliz)
        Copy-Item -Path (Join-Path $InstallDir "${BinName}.exe") -Destination (Join-Path $InstallDir "zz.exe") -Force

        Write-Success "Installed $BinName $version to $InstallDir"
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Ensure InstallDir is on PATH ─────────────────────────────────────
function Ensure-Path {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -split ";" | Where-Object { $_ -eq $InstallDir }) {
        return
    }

    if ($env:ZILLIZ_NO_MODIFY_PATH -eq "1") {
        Write-Warn "$InstallDir is not in your PATH."
        Write-Warn "Add it manually in System Settings > Environment Variables."
        return
    }

    $newPath = $InstallDir + ";" + $userPath
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = $InstallDir + ";" + $env:PATH
    Write-Info "Added $InstallDir to your user PATH."
    Write-Info "Restart your terminal for it to take effect."
}

# ── Post-install Next steps panel ────────────────────────────────────
# NOTE: the Plugins list below is mirrored in install.sh and README.md
# "Related Tools". When adding/removing an entry, update all three.
function Write-NextSteps {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host ("  1. {0,-30} {1}" -f "$BinName login",             "Authenticate with Zilliz Cloud")
    Write-Host ("  2. {0,-30} {1}" -f "$BinName cluster list",      "See your clusters")
    Write-Host ("  3. {0,-30} {1}" -f "$BinName collection --help", "Manage collections")
    Write-Host ""
    Write-Host "Highlights:" -ForegroundColor White
    Write-Host "  Cloud:"
    Write-Host ("    * {0,-14} - ``{1} cluster create`` / ``scale`` / ``suspend``" -f "Clusters", $BinName)
    Write-Host ("    * {0,-14} - bulk load data with ``{1} import``"               -f "Import jobs", $BinName)
    Write-Host ("    * {0,-14} - ``{1} backup create`` / ``restore``"              -f "Backup", $BinName)
    Write-Host "  Data:"
    Write-Host ("    * {0,-14} - ``{1} vector search`` / ``query`` / ``insert``"   -f "Vector ops", $BinName)
    Write-Host ("    * {0,-14} - ``{1} index create`` / ``list`` / ``describe``"   -f "Indexes", $BinName)
    Write-Host ("    * {0,-14} - ``{1} user`` / ``{1} role`` (Dedicated only)"     -f "Access ctrl", $BinName)
    Write-Host ""
    Write-Host "Docs: https://docs.zilliz.com/reference/cli/overview"
    Write-Host ""
    Write-Host "Plugins:" -ForegroundColor White
    Write-Host ("  * {0,-22} {1}" -f "Zilliz Claude Plugin", "https://github.com/zilliztech/zilliz-plugin")
    Write-Host ("  * {0,-22} {1}" -f "Gemini-cli Extension", "https://github.com/zilliztech/gemini-cli-extension")
    Write-Host ("  * {0,-22} {1}" -f "Zilliz Skill",         "https://github.com/zilliztech/zilliz-skill")
    Write-Host ("  * {0,-22} {1}" -f "Milvus Skill",         "https://github.com/zilliztech/milvus-skill")
    Write-Host ("  * {0,-22} {1}" -f "Zilliz Launchpad",     "https://github.com/zilliztech/zilliz-launchpad")
}

# ── Uninstall ────────────────────────────────────────────────────────
function Invoke-Uninstall {
    Write-Info "Uninstalling $PackageName..."

    # Remove Python-based installations
    Uninstall-PythonVersion

    # Remove binary install and zz alias
    $binPath = Join-Path $InstallDir "${BinName}.exe"
    if (Test-Path $binPath) {
        Remove-Item $binPath -Force
        Write-Info "Removed $binPath"
    }
    $zzPath = Join-Path $InstallDir "zz.exe"
    if (Test-Path $zzPath) {
        Remove-Item $zzPath -Force
        Write-Info "Removed $zzPath"
    }

    # Remove from PATH if empty
    if ((Test-Path $InstallDir) -and (Get-ChildItem $InstallDir | Measure-Object).Count -eq 0) {
        Remove-Item $InstallDir -Force -ErrorAction SilentlyContinue
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        $newPath = ($userPath -split ";" | Where-Object { $_ -ne $InstallDir }) -join ";"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Info "Cleaned up PATH."
    }

    Write-Success "Uninstalled $PackageName"
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────
function Main {
    param([string[]]$Arguments)

    # Handle --uninstall flag
    if ($Arguments -contains "--uninstall" -or $Arguments -contains "uninstall") {
        Invoke-Uninstall
    }

    Write-Host ""
    Write-Host "  Zilliz CLI Installer" -ForegroundColor White
    Write-Host "  Manage Zilliz Cloud from your terminal"
    Write-Host ""

    Write-Info "Detected platform: windows/$($env:PROCESSOR_ARCHITECTURE.ToLower())"

    # Remove previous Python-based installation if present
    Uninstall-PythonVersion

    # Install binary from GitHub Releases
    Install-ViaBinary

    Ensure-Path

    # Verify installation
    Write-Host ""
    if (Test-Command $BinName) {
        Write-Success "Installation complete!"
        Write-NextSteps
    }
    else {
        Write-Success "Installation complete!"
        Write-Warn "Restart your terminal, then run '$BinName --help' to get started."
        Write-NextSteps
    }

    Write-Host ""
}

Main $args
