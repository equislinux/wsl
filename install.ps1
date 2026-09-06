<#
.SYNOPSIS
    Imports the X Linux for WSL rootfs on Windows and prepares the host.

.DESCRIPTION
    Installs the tarball produced by build-rootfs.sh as a WSL 2 distribution:

      1. Verifies that WSL (Microsoft Store build) is installed and current.
      2. Imports the rootfs with:  wsl --import <Name> <InstallDir> <Rootfs> --version 2
      3. Makes the distribution the default (wsl --set-default), optional.
      4. Prints guidance for the host-side .wslconfig file (never overwrites it).
      5. Prints the next steps to finish the setup with xlnux/wsl-scripts.

    The distribution must not already be registered under the same name.

    Reference:
      - Install WSL:            https://learn.microsoft.com/en-us/windows/wsl/install
      - Basic commands:         https://learn.microsoft.com/en-us/windows/wsl/basic-commands
      - Advanced configuration: https://learn.microsoft.com/en-us/windows/wsl/wsl-config

    NOTE: this script is part of the repository documentation and is written
    to be read and reviewed on a Windows host; PowerShell syntax cannot be
    exercised in the Linux build environment of this repository. Keep it
    simple and review it on a Windows machine before first use.

.PARAMETER Rootfs
    Path to the rootfs tarball (x-wsl-rootfs.tar.gz). Required.

.PARAMETER Name
    Name of the WSL distribution to register. Default: x.

.PARAMETER InstallDir
    Windows folder that will hold the distribution VHD.
    Default: %LOCALAPPDATA%\WSL\<Name> (no administrator rights needed).

.PARAMETER NoDefault
    Do not run 'wsl --set-default' after the import.

.PARAMETER CreateWslConfig
    Create a starter %UserProfile%\.wslconfig from templates/.wslconfig when
    the file does not exist yet. Never overwrites an existing file.

.EXAMPLE
    .\install.ps1 -Rootfs .\x-wsl-rootfs.tar.gz

.EXAMPLE
    .\install.ps1 -Rootfs .\x-wsl-rootfs.tar.gz -Name x -InstallDir C:\WSL\x
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Rootfs,

    [Parameter(Position = 1)]
    [string]$Name = 'x',

    [Parameter(Position = 2)]
    [string]$InstallDir = "$env:LOCALAPPDATA\WSL\$Name",

    [switch]$NoDefault,

    [switch]$CreateWslConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Minimum WSL (Store) version that supports systemd in /etc/wsl.conf.
$MinWslVersion = [version]'0.67.6'

# ---------------------------------------------------------------------------
# Output helpers. Plain ASCII text, consistent prefixes, no emojis.
# ---------------------------------------------------------------------------
function Write-Step  { Write-Host ("[x-wsl] " + $args) -ForegroundColor Green }
function Write-Warn  { Write-Host ("[x-wsl] warning: " + $args) -ForegroundColor Yellow }
function Write-ErrorX{ Write-Host ("[x-wsl] error: " + $args) -ForegroundColor Red }
function Write-Info  { Write-Host ("[x-wsl] " + $args) -ForegroundColor Cyan }

# Run a native wsl.exe command and return its output. Throws when the exit
# code is non-zero. Arguments must be a plain string array so paths with
# spaces are passed through untouched.
function Invoke-Wsl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )
    $output = & wsl.exe @ArgumentList 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $joined = $output -join "`n"
        throw "wsl.exe $($ArgumentList -join ' ') failed with exit code $code.`n$joined"
    }
    return $output
}

# ---------------------------------------------------------------------------
# Banner and rootfs validation.
# ---------------------------------------------------------------------------
Write-Step "X Linux for WSL - Windows import"
Write-Info  "This script imports the rootfs and prepares the host."

if (-not (Test-Path -LiteralPath $Rootfs -PathType Leaf)) {
    throw "Rootfs file not found: $Rootfs"
}
$Rootfs = (Resolve-Path -LiteralPath $Rootfs).Path
Write-Info  "Rootfs   : $Rootfs"
Write-Info  "Name     : $Name"
Write-Info  "Install  : $InstallDir"

# ---------------------------------------------------------------------------
# 1. WSL availability.
# ---------------------------------------------------------------------------
Write-Step "Checking WSL"

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-ErrorX "wsl.exe was not found on this system."
    Write-Info  "Install WSL from an elevated PowerShell prompt, then reboot and run this script again:"
    Write-Info  "    wsl --install --no-distribution"
    throw "WSL is not installed."
}

# 'wsl --status' returns general configuration information; a failure here
# usually means the optional WSL component is missing or a reboot is pending.
$null = & wsl.exe --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ErrorX "'wsl --status' failed. WSL may be only partially installed."
    Write-Info  "Run from an elevated PowerShell prompt:  wsl --install --no-distribution"
    Write-Info  "Reboot if prompted, then re-run this script."
    throw "WSL is not ready."
}

# 'wsl --version' is only provided by the Microsoft Store build of WSL.
# Inbox versions do not recognize it (see "systemd support" in the official
# docs), so a failure here means the Store build must be installed first.
$wslVersionOutput = & wsl.exe --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-ErrorX "This looks like the inbox (non-Store) version of WSL, which cannot run systemd."
    Write-Info  "Update to the Microsoft Store build:"
    Write-Info  "    wsl --update"
    Write-Info  "If that fails, install it from https://apps.microsoft.com/detail/9P9TQF7MRM4R"
    throw "WSL Store build is required."
}

# Parse "WSL version: 2.x.y.z" from the version output.
$wslVersion = $null
foreach ($line in $wslVersionOutput) {
    if ($line -match 'WSL version:\s*(\d+(\.\d+)*)') {
        try { $wslVersion = [version]$Matches[1] } catch { $wslVersion = $null }
        if ($wslVersion) { break }
    }
}
if ($wslVersion) {
    if ($wslVersion -lt $MinWslVersion) {
        Write-Warn "WSL $wslVersion is older than $MinWslVersion (systemd support). Update with:"
        Write-Warn "    wsl --update"
    } else {
        Write-Info  "WSL version: $wslVersion"
    }
} else {
    Write-Warn "Could not parse the WSL version; continuing, but systemd may be unavailable."
}

# systemd and the [boot] section of wsl.conf need Windows 11 / Server 2022.
$winBuild = [System.Environment]::OSVersion.Version.Build
if ($winBuild -lt 22000) {
    Write-Warn "Windows build $winBuild detected. systemd under WSL needs Windows 11 or Server 2022;"
    Write-Warn "the distribution will import and boot, but /etc/wsl.conf [boot] systemd will not apply."
} else {
    Write-Info  "Windows build $winBuild (systemd-capable)."
}

# ---------------------------------------------------------------------------
# 2. Distribution name availability.
# ---------------------------------------------------------------------------
$registered = @()
$listOutput = & wsl.exe --list --quiet 2>$null
if ($LASTEXITCODE -eq 0) {
    $registered = @($listOutput | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
}
if ($registered -contains $Name) {
    Write-ErrorX "A distribution named '$Name' is already registered."
    Write-Info  "Pick another name (-Name) or remove the existing distribution first:"
    Write-Info  "    wsl --unregister $Name"
    throw "Distribution name '$Name' is already in use."
}

# ---------------------------------------------------------------------------
# 3. Import as WSL 2.
# ---------------------------------------------------------------------------
Write-Step "Importing $Name (WSL 2)"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
if (Test-Path -LiteralPath (Join-Path $InstallDir 'ext4.vhdx')) {
    Write-Warn "The install folder already contains an ext4.vhdx; a previous import may have left it."
}

$importArgs = @('--import', $Name, $InstallDir, $Rootfs, '--version', '2')
Write-Info  "Running: wsl --import $Name <InstallDir> <rootfs.tar.gz> --version 2"
$null = Invoke-Wsl -ArgumentList $importArgs
Write-Step "Import finished."

# Confirm the distribution shows up in the registry.
$listOutput = & wsl.exe --list --quiet 2>$null
$registered = @($listOutput | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
if ($registered -notcontains $Name) {
    throw "Import reported success but '$Name' is not listed by 'wsl --list --quiet'."
}

# ---------------------------------------------------------------------------
# 4. Optional: make it the default distribution.
# ---------------------------------------------------------------------------
if (-not $NoDefault) {
    Write-Step "Setting $Name as the default distribution"
    $null = Invoke-Wsl -ArgumentList @('--set-default', $Name)
    Write-Info  "Default distribution: $Name (disable with -NoDefault)"
} else {
    Write-Info  "Default distribution left unchanged (-NoDefault)."
}

# ---------------------------------------------------------------------------
# 5. Host-side .wslconfig guidance (never overwrite an existing file).
# ---------------------------------------------------------------------------
Write-Step "Host configuration (.wslconfig)"
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'

if (Test-Path -LiteralPath $wslConfigPath) {
    Write-Info  "Found an existing .wslconfig (not modified):"
    Write-Info  "    $wslConfigPath"
    Write-Info  "Review the commented template in templates/.wslconfig of this repository and merge"
    Write-Info  "the options you want, then run 'wsl --shutdown' so they apply."
} else {
    $templatePath = Join-Path $PSScriptRoot 'templates\.wslconfig'
    if ($CreateWslConfig -and (Test-Path -LiteralPath $templatePath)) {
        Copy-Item -LiteralPath $templatePath -Destination $wslConfigPath
        Write-Info  "Created a starter .wslconfig from templates/.wslconfig:"
        Write-Info  "    $wslConfigPath"
        Write-Info  "Edit it to match your hardware, then run 'wsl --shutdown'."
    } else {
        Write-Info  "No .wslconfig exists yet; creating one is optional. Recommended content for a"
        Write-Info  "headless X Linux distribution (save it as $wslConfigPath):"
        Write-Host  ""
        Write-Host  "    [wsl2]"
        Write-Host  "    # guiApplications=false  # X Linux for WSL ships no GUI (WSLg off)"
        Write-Host  "    [experimental]"
        Write-Host  "    autoMemoryReclaim=dropCache"
        Write-Host  "    sparseVhd=true"
        Write-Host  ""
        Write-Info  "Apply host changes with 'wsl --shutdown'. To have the importer create the file"
        Write-Info  "for you from templates/.wslconfig on a fresh machine, re-run with -CreateWslConfig."
    }
}

# ---------------------------------------------------------------------------
# 6. Next steps.
# ---------------------------------------------------------------------------
Write-Step "Next steps"
Write-Host  @"

  1. Launch the distribution (it boots as root, the WSL default for imports):

         wsl -d $Name

     Check that systemd is running as PID 1:

         systemctl is-system-running

  2. Install the setup scripts where both root and your future user can read
     them, for example /opt/x-wsl-scripts, and run the system stage (the
     session is root, so no sudo is needed):

         git clone https://github.com/xlnux/wsl-scripts /opt/x-wsl-scripts
         cd /opt/x-wsl-scripts
         ./install.sh

     This configures locale, keymap, timezone, the sudo user and pins that
     user as the WSL default in /etc/wsl.conf.

  3. Exit the session, then relaunch so WSL applies the new default user:

         wsl --terminate $Name
         wsl -d $Name

  4. As your new user, run the user stage once more:

         cd /opt/x-wsl-scripts
         ./install.sh

     This configures your shell prompt, environment and project folders.

  Import documentation: docs/en/import.md in this repository.
"@

Write-Step "Done."
