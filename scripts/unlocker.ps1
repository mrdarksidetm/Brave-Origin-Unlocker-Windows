# ==============================================================================
# Download Brave Origin & Unlock Directly via Native PowerShell
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Brave Origin Setup Unlocker" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$tempWorkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $tempWorkDir) { $tempWorkDir = "C:\Windows\Temp" }
if (-not (Test-Path $tempWorkDir)) {
    New-Item -ItemType Directory -Path $tempWorkDir -Force | Out-Null
}

# ------------------------------------------------------------------------------
# Step 1: Download and Install Brave Origin
# ------------------------------------------------------------------------------
$braveInstallerUrl = "https://laptop-updates.brave.com/latest/origin/winx64/release"
$braveInstallerPath = Join-Path $tempWorkDir "BraveOriginSetup.exe"

Write-Host "`n[1/2] Downloading Brave Origin installer..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Invoke-WebRequest -Uri $braveInstallerUrl -OutFile $braveInstallerPath -UseBasicParsing
    Write-Host "Brave Origin installer downloaded to: $braveInstallerPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to download Brave Origin installer: $_"
    exit 1
}

Write-Host "Launching Brave Origin installer (please accept UAC prompt if displayed)..." -ForegroundColor Yellow
$installerProcess = Start-Process -FilePath $braveInstallerPath -Wait -PassThru
Write-Host "Brave Origin installer process completed with exit code: $($installerProcess.ExitCode)" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Step 2: Native PowerShell Equivalent of unlock.ts
# Modifies 'Local State' for Brave-Origin, Brave-Origin-Beta, Brave-Origin-Nightly
# ------------------------------------------------------------------------------
Write-Host "`n[2/2] Applying Brave Origin unlock patch natively..." -ForegroundColor Yellow

$localAppData = $env:LOCALAPPDATA
if (-not $localAppData) {
    Write-Error "Error: LOCALAPPDATA environment variable not found."
    exit 1
}

# Close any running Brave instances to avoid file lock on 'Local State'
Get-Process -Name "brave" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$versions = @("Brave-Origin", "Brave-Origin-Beta", "Brave-Origin-Nightly")
$unlockedCount = 0

foreach ($version in $versions) {
    $userDataDir = Join-Path $localAppData "BraveSoftware\$version\User Data"
    $localStatePath = Join-Path $userDataDir "Local State"

    if (-not (Test-Path $userDataDir)) {
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    }

    # Load existing Local State JSON if present, otherwise initialize PSCustomObject
    $localState = $null
    if (Test-Path $localStatePath) {
        try {
            $rawContent = Get-Content -Path $localStatePath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($rawContent)) {
                $localState = $rawContent | ConvertFrom-Json
            }
        } catch {
            Write-Warning "Could not parse existing $localStatePath. Initializing fresh state."
        }
    }

    if ($null -eq $localState) {
        $localState = [PSCustomObject]@{}
    }

    # 1. Inject: localState.brave.origin = { purchase_validated: true }
    $originObj = [PSCustomObject]@{ purchase_validated = $true }
    if ($null -eq $localState.PSObject.Properties['brave']) {
        $localState | Add-Member -MemberType NoteProperty -Name 'brave' -Value ([PSCustomObject]@{ origin = $originObj }) -Force
    } else {
        if ($null -eq $localState.brave) {
            $localState.brave = [PSCustomObject]@{ origin = $originObj }
        } else {
            $localState.brave | Add-Member -MemberType NoteProperty -Name 'origin' -Value $originObj -Force
        }
    }

    # 2. Inject: localState.skus.state["67"] = JSON.stringify({ credentials: { items: { "6": "7" } } })
    $skuItemJson = '{"credentials":{"items":{"6":"7"}}}'
    $stateObj = [PSCustomObject]@{ "67" = $skuItemJson }
    $skusObj = [PSCustomObject]@{ state = $stateObj }

    if ($null -eq $localState.PSObject.Properties['skus']) {
        $localState | Add-Member -MemberType NoteProperty -Name 'skus' -Value $skusObj -Force
    } else {
        $localState.skus = $skusObj
    }

    # 3. Write back to Local State formatted as JSON
    $jsonOutput = $localState | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($localStatePath, $jsonOutput, [System.Text.Encoding]::UTF8)

    $displayName = $version -replace "-", " "
    Write-Host "$displayName unlocked successfully!" -ForegroundColor Green
    $unlockedCount++
}

Write-Host "`n[SUCCESS] Native unlock completed for $unlockedCount browser configurations!" -ForegroundColor Green
Write-Host "You can now launch Brave Origin without purchase prompts." -ForegroundColor Cyan
