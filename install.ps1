# ----------------------------------------------------------------------
#  Zilliz CLI Installer (Windows PowerShell)
#
#  Usage:
#    irm https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.ps1 | iex
#
#   Note: Windows ARM64 runs the x86_64 standalone build via Windows x64 emulation.
#
#  Options (via environment variables):
#    $env:ZILLIZ_VERSION = "v2.0.1"          Install a specific version (default: latest)
#    $env:ZILLIZ_INSTALL_DIR = "C:\mypath"   Override install directory
#    $env:ZILLIZ_NO_MODIFY_PATH = "1"        Skip user PATH modification
#    $env:ZILLIZ_RELEASE_BASE_URL            Override release asset base URL
#    $env:ZILLIZ_SKIP_CHECKSUM = "1"         Skip SHA-256 verification (legacy pre-2.0 releases only)
# ----------------------------------------------------------------------

$ErrorActionPreference = "Stop"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$PackageName       = "zilliz-cli"
$BinName           = "zilliz"
$Repo              = "zilliztech/zilliz-cli"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "Programs\Zilliz"
$LegacyInstallDir1 = Join-Path $env:LOCALAPPDATA "zilliz-cli\bin"
$LegacyInstallDir2 = Join-Path $HOME ".zilliz\bin"

$InstallDir        = if ($env:ZILLIZ_INSTALL_DIR) { $env:ZILLIZ_INSTALL_DIR } else { $DefaultInstallDir }
$RequestedVersion  = if ($env:ZILLIZ_VERSION) { $env:ZILLIZ_VERSION } else { "latest" }

function Write-Info    { param($Msg) Write-Host "==> " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Success { param($Msg) Write-Host "==> " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "Warning: " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Stop-WithError { param($Msg) throw "Error: $Msg" }

function Test-Command { param($Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Get-HostArchitecture {
    $rawArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($rawArch) {
        "AMD64" { return "x86_64" }
        "ARM64" { return "x86_64" }
        default { Stop-WithError "Unsupported architecture: $rawArch" }
    }
}

function Resolve-LatestTag {
    $resolved = $null
    try {
        $req = [System.Net.HttpWebRequest]::Create("https://github.com/$Repo/releases/latest")
        $req.Method = "HEAD"
        $req.AllowAutoRedirect = $false
        $req.UserAgent = "zilliz-installer"
        $resp = $req.GetResponse()
        $loc = $resp.Headers["Location"]
        $resp.Close()
        if ($loc -and ($loc -match '/releases/tag/([^/?#]+)')) {
            $resolved = $Matches[1]
        }
    } catch {
        if ($_.Exception.Response) {
            $loc = $_.Exception.Response.Headers["Location"]
            if ($loc -and ($loc -match '/releases/tag/([^/?#]+)')) {
                $resolved = $Matches[1]
            }
        }
    }

    if (-not $resolved) {
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "zilliz-installer" }
            $resolved = $release.tag_name
        } catch {}
    }

    if (-not $resolved) {
        Stop-WithError "Failed to determine latest version from GitHub Releases. Set `$env:ZILLIZ_VERSION = 'v2.0.1' explicitly to bypass version lookup."
    }
    return $resolved
}

function Remove-LegacyZillizBins {
    foreach ($legacyDir in @($LegacyInstallDir1, $LegacyInstallDir2)) {
        if ($legacyDir -and ($legacyDir -ne $InstallDir) -and (Test-Path -LiteralPath $legacyDir)) {
            foreach ($exe in @("zilliz.exe", "zz.exe")) {
                $p = Join-Path $legacyDir $exe
                if (Test-Path -LiteralPath $p) {
                    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                    Write-Info "Removed legacy binary at $p"
                }
            }
        }
    }
}

function Install-StagedBundle {
    param([string]$ExtractDir, [string]$TargetDir)

    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    $suffix = "$PID-$([guid]::NewGuid().ToString('N').Substring(0, 6))"

    $newInternal = Join-Path $ExtractDir "_internal"
    $destInternal = Join-Path $TargetDir "_internal"
    $stagingInternal = Join-Path $TargetDir "_internal.new-$suffix"
    $oldInternalBackup = Join-Path $TargetDir "_internal.old-$suffix"

    if (Test-Path -LiteralPath $newInternal) {
        Copy-Item -LiteralPath $newInternal -Destination $stagingInternal -Recurse -Force
    }

    if (Test-Path -LiteralPath $destInternal) {
        Move-Item -LiteralPath $destInternal -Destination $oldInternalBackup -Force
    }
    if (Test-Path -LiteralPath $stagingInternal) {
        Move-Item -LiteralPath $stagingInternal -Destination $destInternal -Force
    }

    foreach ($exeName in @("${BinName}.exe", "zz.exe")) {
        $srcExe = Join-Path $ExtractDir $exeName
        if (-not (Test-Path -LiteralPath $srcExe)) {
            $srcExe = Join-Path $ExtractDir "${BinName}.exe"
        }
        $dstExe = Join-Path $TargetDir $exeName
        $bakExe = Join-Path $TargetDir "${exeName}.old-$suffix"
        if (Test-Path -LiteralPath $dstExe) {
            try {
                Remove-Item -LiteralPath $dstExe -Force -ErrorAction Stop
            } catch {
                Move-Item -LiteralPath $dstExe -Destination $bakExe -Force
            }
        }
        Copy-Item -LiteralPath $srcExe -Destination $dstExe -Force
        if (Test-Path -LiteralPath $bakExe) {
            Remove-Item -LiteralPath $bakExe -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path -LiteralPath $oldInternalBackup) {
        Remove-Item -LiteralPath $oldInternalBackup -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ViaArchive {
    if (-not $InstallDir -or $InstallDir -eq "\" -or $InstallDir -eq $HOME) {
        Stop-WithError "Unsafe ZILLIZ_INSTALL_DIR path: '$InstallDir'."
    }
    $arch = Get-HostArchitecture

    $tag = $RequestedVersion
    if ($tag -eq "latest") {
        if ($env:ZILLIZ_RELEASE_BASE_URL) {
            Stop-WithError "ZILLIZ_VERSION must be set explicitly when ZILLIZ_RELEASE_BASE_URL is used."
        }
        Write-Info "Fetching latest release..."
        $tag = Resolve-LatestTag
    }

    $version = $tag -replace '^zilliz-v', '' -replace '^v', ''
    if ($version -notmatch '^[0-9A-Za-z._-]+$') {
        Stop-WithError "Invalid version string: '$version'"
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
            Stop-WithError "ZILLIZ_RELEASE_BASE_URL must use https:// (or file:// for local testing)."
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
                Stop-WithError "Failed to download $checksumsUrl; refusing unverified installation (set ZILLIZ_SKIP_CHECKSUM=1 only for legacy pre-2.0 releases without sha256sums.txt)."
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
                Stop-WithError "Archive $archive is missing from sha256sums.txt; refusing unverified installation."
            }
            if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
                Stop-WithError "Malformed SHA-256 entry '$expectedHash' in sha256sums.txt for $archive."
            }

            $actualHash = (Get-FileHash -Path (Join-Path $tmpDir $archive) -Algorithm SHA256).Hash.ToLower()
            if ($actualHash -ne $expectedHash) {
                Stop-WithError "Checksum verification failed! Expected: $expectedHash, Got: $actualHash"
            }
            Write-Info "Checksum verified ($actualHash)."
        }

        Write-Info "Extracting to $InstallDir..."
        Expand-Archive -Path (Join-Path $tmpDir $archive) -DestinationPath $extractDir -Force
        Install-StagedBundle -ExtractDir $extractDir -TargetDir $InstallDir
        Remove-LegacyZillizBins

        Write-Success "Installed $BinName $version to $InstallDir"
    }
    finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-Path {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if (-not $userPath) { $userPath = "" }

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

    $internalDir = Join-Path $InstallDir "_internal"
    $isOwnedBundle = Test-Path -LiteralPath $internalDir

    if ($isOwnedBundle) {
        foreach ($exe in @("${BinName}.exe", "zz.exe")) {
            $p = Join-Path $InstallDir $exe
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Force
                Write-Info "Removed $p"
            }
        }
        Remove-Item -LiteralPath $internalDir -Recurse -Force
        Write-Info "Removed $internalDir"
    }

    if ((Test-Path -LiteralPath $InstallDir) -and (@(Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue).Count -eq 0)) {
        Remove-Item -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath) {
            $newPath = ($userPath -split ";" | Where-Object { $_ -and ($_ -ne $InstallDir) }) -join ";"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Info "Cleaned up PATH."
        }
    }

    Write-Success "Uninstalled $PackageName"
    return
}

function Main {
    param([string[]]$Arguments)

    if ($Arguments -contains "--uninstall" -or $Arguments -contains "uninstall") {
        Invoke-Uninstall
        return
    }

    Write-Host ""
    Write-Host "  Zilliz CLI Installer" -ForegroundColor White
    Write-Host "  Manage Zilliz Cloud from your terminal"
    Write-Host ""

    Write-Info "Detected platform: windows/$($env:PROCESSOR_ARCHITECTURE.ToLower())"

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
