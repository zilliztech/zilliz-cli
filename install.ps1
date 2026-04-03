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
$MinPythonVersion = [version]"3.8"

# ── Logging helpers ──────────────────────────────────────────────────
function Write-Info    { param($Msg) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param($Msg) Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "Warning: " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param($Msg) Write-Host "Error: " -ForegroundColor Red -NoNewline; Write-Host $Msg; exit 1 }

# ── Check if a command exists ────────────────────────────────────────
function Test-Command { param($Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ── Find a usable Python ────────────────────────────────────────────
function Find-Python {
    foreach ($cmd in @("python3", "python", "py")) {
        if (Test-Command $cmd) {
            try {
                $versionStr = & $cmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
                if ($versionStr -and ([version]$versionStr -ge $MinPythonVersion)) {
                    return $cmd
                }
            } catch { continue }
        }
    }
    return $null
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Python (current)
# ══════════════════════════════════════════════════════════════════════
function Install-ViaPython {
    $pythonCmd = Find-Python
    if (-not $pythonCmd) {
        Write-Err @"
Python $MinPythonVersion+ is required but not found.
Please install Python first:
  - Microsoft Store: search for 'Python 3'
  - https://www.python.org/downloads/
  - winget: winget install Python.Python.3.12
"@
    }

    $pythonVersion = & $pythonCmd --version 2>&1
    Write-Info "Found $pythonVersion"

    $pkg = $PackageName
    if ($RequestedVersion -ne "latest") {
        $pkg = "${PackageName}==${RequestedVersion}"
    }

    # Prefer pipx > uv > pip
    if (Test-Command "pipx") {
        Write-Info "Installing $PackageName via pipx..."
        & pipx install $pkg --force
    }
    elseif (Test-Command "uv") {
        Write-Info "Installing $PackageName via uv..."
        & uv tool install $pkg --force
    }
    else {
        Write-Info "Installing $PackageName via pip..."
        & $pythonCmd -m pip install --user --upgrade $pkg
    }
}

# ══════════════════════════════════════════════════════════════════════
#  Install Strategy: Binary (future — uncomment when Rust builds are
#  published to GitHub Releases)
# ══════════════════════════════════════════════════════════════════════
<#
function Install-ViaBinary {
    # Detect architecture
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x86_64" }
        "ARM64" { "aarch64" }
        default { Write-Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }

    # Resolve version
    $version = $RequestedVersion
    if ($version -eq "latest") {
        Write-Info "Fetching latest release..."
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "zilliz-installer" }
        $version = $release.tag_name
        if (-not $version) { Write-Err "Failed to determine latest version" }
    }
    Write-Info "Version: $version"

    # Build download URL
    $archive = "${BinName}-${version}-windows-${arch}.zip"
    $url = "https://github.com/$Repo/releases/download/$version/$archive"

    # Download
    $tmpDir = Join-Path $env:TEMP "zilliz-install-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    try {
        Write-Info "Downloading $url..."
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmpDir $archive) -UseBasicParsing

        # Checksum verification (optional)
        $checksumsUrl = "https://github.com/$Repo/releases/download/$version/sha256sums.txt"
        try {
            Invoke-WebRequest -Uri $checksumsUrl -OutFile (Join-Path $tmpDir "sha256sums.txt") -UseBasicParsing
            $expectedHash = (Get-Content (Join-Path $tmpDir "sha256sums.txt") | Where-Object { $_ -match $archive }) -split '\s+' | Select-Object -First 1
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

        # Install binaries
        Copy-Item -Path (Join-Path $tmpDir "${BinName}.exe") -Destination (Join-Path $InstallDir "${BinName}.exe") -Force
        Copy-Item -Path (Join-Path $InstallDir "${BinName}.exe") -Destination (Join-Path $InstallDir "${BinAlias}.exe") -Force

        Write-Success "Installed $BinName $version to $InstallDir"
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
#>

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

# ── Uninstall ────────────────────────────────────────────────────────
function Invoke-Uninstall {
    Write-Info "Uninstalling $PackageName..."

    if (Test-Command "pipx") {
        try { & pipx uninstall $PackageName 2>$null } catch {}
    }
    elseif (Test-Command "uv") {
        try { & uv tool uninstall $PackageName 2>$null } catch {}
    }
    elseif (Test-Command "pip3") {
        try { & pip3 uninstall -y $PackageName 2>$null } catch {}
    }
    elseif (Test-Command "pip") {
        try { & pip uninstall -y $PackageName 2>$null } catch {}
    }

    # Also clean up binary install (future-proof)
    foreach ($bin in @("${BinName}.exe", "${BinAlias}.exe")) {
        $binPath = Join-Path $InstallDir $bin
        if (Test-Path $binPath) {
            Remove-Item $binPath -Force
            Write-Info "Removed $binPath"
        }
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

    # ── Current: Python install ──────────────────────────────────────
    Install-ViaPython

    # ── Future: switch to binary install ─────────────────────────────
    # Install-ViaBinary

    Ensure-Path

    # Verify installation
    Write-Host ""
    if (Test-Command $BinName) {
        Write-Success "Installation complete!"
        Write-Info "Run '$BinName --help' to get started."
        Write-Info "Use '$BinName login' to authenticate with Zilliz Cloud."
    }
    else {
        Write-Success "Installation complete!"
        Write-Warn "Restart your terminal, then run '$BinName --help' to get started."
    }

    Write-Host ""
}

Main $args
