# ----------------------------------------------------------------------
#  Zilliz CLI Installer (Windows PowerShell)
#
#  Usage:
#    irm https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.ps1 | iex
#
#  Options (via environment variables):
#    $env:ZILLIZ_VERSION = "v2.0.0"          Install a specific version (default: latest)
#    $env:ZILLIZ_INSTALL_DIR = "C:\mypath"   Override install directory
#    $env:ZILLIZ_NO_MODIFY_PATH = "1"        Skip user PATH modification
#    $env:ZILLIZ_RELEASE_BASE_URL            Override release asset base URL
# ----------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$PackageName       = "zilliz-cli"
$BinName           = "zilliz"
$Repo              = "zilliztech/zilliz-cli"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "Programs\Zilliz"
$LegacyInstallDir1 = Join-Path $env:LOCALAPPDATA "zilliz-cli\bin"
$LegacyInstallDir2 = Join-Path $HOME ".zilliz\bin"

$InstallDir = if ($env:ZILLIZ_INSTALL_DIR) {
    $env:ZILLIZ_INSTALL_DIR
} elseif ($env:INSTALL_DIR) {
    $env:INSTALL_DIR
} else {
    $DefaultInstallDir
}

$RequestedVersion = if ($env:ZILLIZ_VERSION) {
    $env:ZILLIZ_VERSION
} elseif ($env:VERSION) {
    $env:VERSION
} else {
    "latest"
}

function Write-Info    { param($Msg) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param($Msg) Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "Warning: " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param($Msg) Write-Host "Error: " -ForegroundColor Red -NoNewline; Write-Host $Msg; exit 1 }

function Test-Command { param($Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Remove-ConflictingInstalls {
    if ((Test-Command "pipx") -and ((& pipx list 2>$null) -match $PackageName)) {
        Write-Info "Found global pipx installation of $PackageName. Removing..."
        try { & pipx uninstall $PackageName 2>$null } catch {}
    }

    if ((Test-Command "uv") -and ((& uv tool list 2>$null) -match $PackageName)) {
        Write-Info "Found global uv tool installation of $PackageName. Removing..."
        try { & uv tool uninstall $PackageName 2>$null } catch {}
    }

    if (-not $env:VIRTUAL_ENV -and -not $env:CONDA_PREFIX) {
        foreach ($pipCmd in @("pip3", "pip")) {
            if (Test-Command $pipCmd) {
                try {
                    $showOutput = & $pipCmd show $PackageName 2>$null
                    if ($showOutput) {
                        Write-Info "Found global $pipCmd installation of $PackageName. Removing..."
                        & $pipCmd uninstall -y $PackageName 2>$null
                        break
                    }
                } catch {}
            }
        }
    }

    foreach ($legacyDir in @($LegacyInstallDir1, $LegacyInstallDir2)) {
        if ($legacyDir -and ($legacyDir -ne $InstallDir) -and (Test-Path $legacyDir)) {
            foreach ($exe in @("zilliz.exe", "zz.exe")) {
                $p = Join-Path $legacyDir $exe
                if (Test-Path $p) {
                    Remove-Item $p -Force -ErrorAction SilentlyContinue
                    Write-Info "Removed legacy binary at $p"
                }
            }
        }
    }
}

function Install-ViaArchive {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x86_64" }
        "ARM64" { "x86_64" }
        default { Write-Err "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
    }

    $tag = $RequestedVersion
    if ($tag -eq "latest") {
        if ($env:ZILLIZ_RELEASE_BASE_URL) {
            Write-Err "ZILLIZ_VERSION must be set explicitly when ZILLIZ_RELEASE_BASE_URL is used."
        }
        Write-Info "Fetching latest release..."
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "zilliz-installer" }
        $tag = $release.tag_name
        if (-not $tag) { Write-Err "Failed to determine latest version from GitHub Releases" }
    }

    $version = $tag -replace '^zilliz-v', '' -replace '^v', ''
    if ($version -notmatch '^[0-9A-Za-z._-]+$') {
        Write-Err "Invalid version string: '$version'"
    }
    if ($tag -notmatch '^zilliz-v') {
        $tag = "zilliz-v$version"
    }
    Write-Info "Version: $version"

    $target = "${arch}-pc-windows-msvc"
    $archive = "${BinName}-${version}-${target}.zip"
    $baseUrl = if ($env:ZILLIZ_RELEASE_BASE_URL) {
        $u = $env:ZILLIZ_RELEASE_BASE_URL.TrimEnd("/")
        if ($u -notmatch '^(https://|file://)') {
            Write-Err "ZILLIZ_RELEASE_BASE_URL must use https:// (or file:// for local testing)."
        }
        $u
    } else {
        "https://github.com/$Repo/releases/download/$tag"
    }
    $url = "$baseUrl/$archive"

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "zilliz-install-$([guid]::NewGuid())"
    $extractDir = Join-Path $tmpDir "extracted"
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    try {
        Write-Info "Downloading $url..."
        Invoke-WebRequest -Uri $url -OutFile (Join-Path $tmpDir $archive) -UseBasicParsing

        if ($env:ZILLIZ_SKIP_CHECKSUM -eq "1") {
            Write-Warn "Skipping checksum verification because ZILLIZ_SKIP_CHECKSUM=1."
        } else {
            $checksumsUrl = "$baseUrl/sha256sums.txt"
            Write-Info "Verifying checksum..."
            try {
                Invoke-WebRequest -Uri $checksumsUrl -OutFile (Join-Path $tmpDir "sha256sums.txt") -UseBasicParsing
            } catch {
                Write-Err "Failed to download $checksumsUrl; refusing unverified installation (set ZILLIZ_SKIP_CHECKSUM=1 only for legacy pre-2.0 releases without sha256sums.txt)."
            }

            $expectedHash = $null
            foreach ($line in (Get-Content (Join-Path $tmpDir "sha256sums.txt"))) {
                $trimmed = $line.Trim()
                if (-not $trimmed) { continue }
                $parts = $trimmed -split '\s+', 2
                if ($parts.Length -ge 2) {
                    $fname = $parts[1].Trim() -replace '^\*', ''
                    if ($fname -eq $archive) {
                        $expectedHash = $parts[0].ToLower()
                        break
                    }
                }
            }

            if (-not $expectedHash) {
                Write-Err "Archive $archive is missing from sha256sums.txt; refusing unverified installation."
            }
            if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
                Write-Err "Malformed SHA-256 entry '$expectedHash' in sha256sums.txt for $archive."
            }

            $actualHash = (Get-FileHash -Path (Join-Path $tmpDir $archive) -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -ne $expectedHash) {
                Write-Err "Checksum verification failed!`nExpected: $expectedHash`nGot:      $actualHash"
            }
            Write-Info "Checksum verified ($actualHash)."
        }

        Write-Info "Extracting to $InstallDir..."
        Expand-Archive -Path (Join-Path $tmpDir $archive) -DestinationPath $extractDir -Force

        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        $oldInternal = Join-Path $InstallDir "_internal"
        if (Test-Path $oldInternal) {
            Remove-Item -Path $oldInternal -Recurse -Force
        }

        Copy-Item -Path (Join-Path $extractDir "${BinName}.exe") -Destination (Join-Path $InstallDir "${BinName}.exe") -Force
        if (Test-Path (Join-Path $extractDir "zz.exe")) {
            Copy-Item -Path (Join-Path $extractDir "zz.exe") -Destination (Join-Path $InstallDir "zz.exe") -Force
        } else {
            Copy-Item -Path (Join-Path $InstallDir "${BinName}.exe") -Destination (Join-Path $InstallDir "zz.exe") -Force
        }

        $newInternal = Join-Path $extractDir "_internal"
        if (Test-Path $newInternal) {
            Copy-Item -Path $newInternal -Destination $oldInternal -Recurse -Force
        }

        Write-Success "Installed $BinName $version to $InstallDir"
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-Path {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath) { $userPath = "" }

    # Remove stale legacy install dirs if empty
    $parts = $userPath -split ";" | Where-Object { $_ -ne "" }
    $parts = $parts | Where-Object {
        ($_ -ne $LegacyInstallDir1 -or (Test-Path (Join-Path $LegacyInstallDir1 "zilliz.exe")))
    }

    if ($parts -contains $InstallDir) {
        $env:PATH = "$InstallDir;$env:PATH"
        return
    }

    if ($env:ZILLIZ_NO_MODIFY_PATH -eq "1") {
        Write-Warn "$InstallDir is not in your PATH."
        Write-Warn "Add it manually in System Settings > Environment Variables."
        return
    }

    $newPath = (@($InstallDir) + $parts) -join ";"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = "$InstallDir;$env:PATH"
    Write-Info "Added $InstallDir to your user PATH."
    Write-Info "Restart your terminal for it to take effect."
}

function Write-NextSteps {
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor White
    Write-Host ("  1. {0,-30} {1}" -f "$BinName login",             "Authenticate with Zilliz Cloud")
    Write-Host ("  2. {0,-30} {1}" -f "$BinName cluster list",      "See your clusters")
    Write-Host ("  3. {0,-30} {1}" -f "$BinName collection --help", "Manage collections")
    Write-Host ""
    Write-Host "Highlights:" -ForegroundColor White
    Write-Host ("  * {0,-14} - ``{1} cluster create`` / ``modify`` / ``suspend``" -f "Clusters", $BinName)
    Write-Host ("  * {0,-14} - bulk stage & load data with ``{1} volume`` / ``import``" -f "Data ingest", $BinName)
    Write-Host ("  * {0,-14} - ``{1} backup create`` / ``restore-cluster``"       -f "Backup", $BinName)
    Write-Host ("  * {0,-14} - ``{1} vector search`` / ``query`` / ``insert``"    -f "Vector ops", $BinName)
    Write-Host ("  * {0,-14} - ``{1} acl`` / ``{1} user`` / ``{1} role``"         -f "Access ctrl", $BinName)
    Write-Host ""
    Write-Host "Docs: https://docs.zilliz.com/reference/cli/overview"
    Write-Host ""
    Write-Host "Plugins:" -ForegroundColor White
    Write-Host ("  * {0,-22} {1}" -f "Zilliz Agent Plugin",  "https://github.com/zilliztech/zilliz-plugin")
    Write-Host ("  * {0,-22} {1}" -f "Gemini CLI Extension", "https://github.com/zilliztech/gemini-cli-extension")
    Write-Host ("  * {0,-22} {1}" -f "Zilliz Skill",         "https://github.com/zilliztech/zilliz-skill")
    Write-Host ("  * {0,-22} {1}" -f "Milvus Skill",         "https://github.com/zilliztech/milvus-skill")
}

function Invoke-Uninstall {
    Write-Info "Uninstalling $PackageName..."
    Remove-ConflictingInstalls

    foreach ($exe in @("${BinName}.exe", "zz.exe")) {
        $p = Join-Path $InstallDir $exe
        if (Test-Path $p) {
            Remove-Item $p -Force
            Write-Info "Removed $p"
        }
    }
    $internalDir = Join-Path $InstallDir "_internal"
    if (Test-Path $internalDir) {
        Remove-Item $internalDir -Recurse -Force
        Write-Info "Removed $internalDir"
    }

    if ((Test-Path $InstallDir) -and (Get-ChildItem $InstallDir | Measure-Object).Count -eq 0) {
        Remove-Item $InstallDir -Force -ErrorAction SilentlyContinue
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath) {
            $newPath = ($userPath -split ";" | Where-Object { $_ -and ($_ -ne $InstallDir) }) -join ";"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Info "Cleaned up PATH."
        }
    }

    Write-Success "Uninstalled $PackageName"
    exit 0
}

function Main {
    param([string[]]$Arguments)

    if ($Arguments -contains "--uninstall" -or $Arguments -contains "uninstall") {
        Invoke-Uninstall
    }

    Write-Host ""
    Write-Host "  Zilliz CLI Installer" -ForegroundColor White
    Write-Host "  Manage Zilliz Cloud from your terminal"
    Write-Host ""

    Write-Info "Detected platform: windows/$($env:PROCESSOR_ARCHITECTURE.ToLower())"

    Remove-ConflictingInstalls
    Install-ViaArchive
    Ensure-Path

    Write-Host ""
    if (Test-Command $BinName) {
        Write-Success "Installation complete!"
        Write-NextSteps
    } else {
        Write-Success "Installation complete!"
        Write-Warn "Restart your terminal, then run '$BinName --help' to get started."
        Write-NextSteps
    }
    Write-Host ""
}

Main $args
