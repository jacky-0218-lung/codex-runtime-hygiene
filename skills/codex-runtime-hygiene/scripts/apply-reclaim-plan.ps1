[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)]
    [string]$PlanPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Fa-f0-9]{64}$")]
    [string]$ApprovedPlanSha256,
    [Parameter(Mandatory = $true)]
    [string]$OwnershipSnapshotPath,
    [switch]$Execute,
    [switch]$ValidateOnly,
    [ValidateRange(5, 300)]
    [int]$SampleIntervalSeconds = 5,
    [ValidateRange(30, 120)]
    [int]$MaximumOwnershipSnapshotAgeSeconds = 120,
    [string]$PostAuditOutputPath = (Join-Path (Get-Location) "codex-runtime-post-apply-audit.json"),
    [string]$PostPlanOutputPath = (Join-Path (Get-Location) "codex-runtime-post-apply-plan.json"),
    [string]$ReceiptOutputPath = (Join-Path (Get-Location) "codex-runtime-apply-receipt.json")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

if ([bool]$Execute -eq [bool]$ValidateOnly) {
    throw "Specify exactly one of -Execute or -ValidateOnly."
}

$scriptRoot = $PSScriptRoot
. (Join-Path $scriptRoot "reclaim-validation.ps1")
$auditScript = Join-Path $scriptRoot "audit-runtime.ps1"
$builderScript = Join-Path $scriptRoot "build-reclaim-plan.ps1"

function Get-Sha256Text {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Convert-ToUtcText {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString("o")
    }
    return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToUniversalTime().ToString("o")
}

function Write-Receipt {
    param($Value)
    $parent = Split-Path -Parent $ReceiptOutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Force -Path $parent)
    }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReceiptOutputPath -Encoding UTF8
}

$resolvedPlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
$resolvedOwnershipPath = (Resolve-Path -LiteralPath $OwnershipSnapshotPath).Path
$planBytes = [System.IO.File]::ReadAllBytes($resolvedPlanPath)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $actualPlanSha256 = ([System.BitConverter]::ToString($sha256.ComputeHash($planBytes))).Replace("-", "").ToLowerInvariant()
}
finally {
    $sha256.Dispose()
}
if (-not [string]::Equals($actualPlanSha256, $ApprovedPlanSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Approved plan SHA-256 does not match the exact plan file bytes."
}

$planText = [System.Text.Encoding]::UTF8.GetString($planBytes).TrimStart([char]0xFEFF)
$approvedPlan = $planText | ConvertFrom-Json
if ([string]$approvedPlan.schemaVersion -ne "2.0" -or -not [bool]$approvedPlan.applySupported) {
    throw "Only an apply-supported schema 2.0 plan can be used."
}
if ([int]$approvedPlan.thresholds.minimumAgeMinutes -lt 60 -or
    [double]$approvedPlan.thresholds.recentCpuThresholdMs -gt 50 -or
    [long]$approvedPlan.thresholds.recentIoThresholdBytes -gt 4096) {
    throw "The plan weakens the minimum v0.2 protection thresholds."
}

$ownershipBytes = [System.IO.File]::ReadAllBytes($resolvedOwnershipPath)
$ownershipText = [System.Text.Encoding]::UTF8.GetString($ownershipBytes).TrimStart([char]0xFEFF)
$ownership = $ownershipText | ConvertFrom-Json
if (-not [bool]$ownership.complete) {
    throw "The ownership snapshot is incomplete. Apply is blocked."
}
if ([string]::IsNullOrWhiteSpace([string]$ownership.capturedAtUtc)) {
    throw "The ownership snapshot has no capturedAtUtc timestamp."
}
$ownershipCapturedAt = [datetime]::Parse([string]$ownership.capturedAtUtc).ToUniversalTime()
$ownershipAgeSeconds = ([datetime]::UtcNow - $ownershipCapturedAt).TotalSeconds
if ($ownershipAgeSeconds -lt -30 -or $ownershipAgeSeconds -gt $MaximumOwnershipSnapshotAgeSeconds) {
    throw "The ownership snapshot is stale or has an invalid future timestamp."
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("crh-apply-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $tempRoot)
$frozenOwnershipPath = Join-Path $tempRoot "ownership-snapshot.json"
[System.IO.File]::WriteAllBytes($frozenOwnershipPath, $ownershipBytes)
$preflightAuditPath = Join-Path $tempRoot "preflight-audit.json"
$preflightPlanPath = Join-Path $tempRoot "preflight-plan.json"
$processHandles = @()
$actions = @()
$receipt = [ordered]@{
    schemaVersion = "1.0"
    generatedAtUtc = [datetime]::UtcNow.ToString("o")
    mode = if ($ValidateOnly) { "validate-only" } else { "execute" }
    approvedPlanPath = $resolvedPlanPath
    approvedPlanSha256 = $actualPlanSha256
    ownershipSnapshotPath = $resolvedOwnershipPath
    preflightValid = $false
    requestedTargetCount = @($approvedPlan.exactApprovalTargets).Count
    actions = @()
    postAuditPath = $null
    postPlanPath = $null
    status = "preflight"
}

try {
    & $auditScript `
        -OwnershipSnapshotPath $frozenOwnershipPath `
        -SampleIntervalSeconds $SampleIntervalSeconds `
        -OutputPath $preflightAuditPath | Out-Null

    & $builderScript `
        -InputPath $preflightAuditPath `
        -OutputPath $preflightPlanPath `
        -MinimumAgeMinutes ([int]$approvedPlan.thresholds.minimumAgeMinutes) `
        -RecentCpuThresholdMs ([double]$approvedPlan.thresholds.recentCpuThresholdMs) `
        -RecentIoThresholdBytes ([long]$approvedPlan.thresholds.recentIoThresholdBytes) | Out-Null

    $freshPlan = Get-Content -LiteralPath $preflightPlanPath -Raw | ConvertFrom-Json
    $validation = Test-ReclaimPlanAgainstFreshPlan $approvedPlan $freshPlan
    if (-not $validation.valid) {
        $receipt.status = "blocked-drift"
        $receipt.actions = @()
        $receipt["validationErrors"] = @($validation.errors)
        Write-Receipt $receipt
        throw "Whole-plan preflight failed: $($validation.errors -join ' ')"
    }

    foreach ($target in @($validation.validatedTargets)) {
        $pidValue = [int]$target.pid
        $cimItems = @(Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = {0}" -f $pidValue) -ErrorAction Stop)
        if ($cimItems.Count -ne 1) {
            throw "PID $pidValue disappeared before process handles were acquired."
        }
        $cim = $cimItems[0]
        $liveCreationTime = Convert-ToUtcText $cim.CreationDate
        $livePath = [string]$cim.ExecutablePath
        $liveFingerprint = Get-Sha256Text ([string]$cim.CommandLine)
        if ([int]$cim.ParentProcessId -ne [int]$target.parentPid -or
            -not (Test-SameCreationTime ([string]$target.creationTimeUtc) $liveCreationTime) -or
            -not (Test-SameText ([string]$target.executablePath) $livePath) -or
            -not (Test-SameText ([string]$target.commandLineFingerprint) $liveFingerprint)) {
            throw "PID $pidValue changed during immediate identity validation."
        }

        $handle = [System.Diagnostics.Process]::GetProcessById($pidValue)
        $handleCreationTime = $handle.StartTime.ToUniversalTime().ToString("o")
        if (-not (Test-SameCreationTime ([string]$target.creationTimeUtc) $handleCreationTime)) {
            $handle.Dispose()
            throw "PID $pidValue changed while its process handle was acquired."
        }
        $processHandles += [pscustomobject]@{
            pid = $pidValue
            depth = Get-ProcessTreeDepth -ProcessId $pidValue -Processes $freshPlan.processes
            target = $target
            process = $handle
        }
    }

    $receipt.preflightValid = $true
    if ($ValidateOnly) {
        $receipt.status = "validated-no-action"
        $receipt.actions = @($processHandles | ForEach-Object {
            [ordered]@{ pid = $_.pid; status = "validated"; depth = $_.depth }
        })
        Write-Receipt $receipt
        Write-Output ("Plan validated without termination: {0}" -f $ReceiptOutputPath)
        return
    }

    $actionLabel = "Terminate {0} exactly validated Codex runtime process(es)" -f $processHandles.Count
    if (-not $PSCmdlet.ShouldProcess($actualPlanSha256, $actionLabel)) {
        $receipt.status = "cancelled"
        Write-Receipt $receipt
        return
    }

    foreach ($entry in @($processHandles | Sort-Object -Property depth -Descending)) {
        try {
            if ($entry.process.HasExited) {
                throw "Process exited after preflight and before termination."
            }
            $entry.process.Kill()
            [void]$entry.process.WaitForExit(10000)
            if (-not $entry.process.HasExited) {
                throw "PID $($entry.pid) did not exit within 10 seconds."
            }
            $actions += [ordered]@{
                pid = [int]$entry.pid
                status = "terminated"
                depth = [int]$entry.depth
            }
        }
        catch {
            $actions += [ordered]@{
                pid = [int]$entry.pid
                status = "failed"
                error = $_.Exception.Message
                depth = [int]$entry.depth
            }
            throw
        }
    }

    & $auditScript `
        -OwnershipSnapshotPath $frozenOwnershipPath `
        -SampleIntervalSeconds $SampleIntervalSeconds `
        -OutputPath $PostAuditOutputPath | Out-Null
    & $builderScript `
        -InputPath $PostAuditOutputPath `
        -OutputPath $PostPlanOutputPath `
        -MinimumAgeMinutes ([int]$approvedPlan.thresholds.minimumAgeMinutes) `
        -RecentCpuThresholdMs ([double]$approvedPlan.thresholds.recentCpuThresholdMs) `
        -RecentIoThresholdBytes ([long]$approvedPlan.thresholds.recentIoThresholdBytes) | Out-Null

    $receipt.actions = @($actions)
    $receipt.postAuditPath = (Resolve-Path -LiteralPath $PostAuditOutputPath).Path
    $receipt.postPlanPath = (Resolve-Path -LiteralPath $PostPlanOutputPath).Path
    $receipt.status = "completed"
    Write-Receipt $receipt
    Write-Output ("Approved reclaim completed and re-audited: {0}" -f $ReceiptOutputPath)
}
catch {
    if ($receipt.status -eq "preflight") {
        $receipt.status = "failed-before-action"
    }
    elseif ($receipt.status -ne "blocked-drift") {
        $receipt.status = "failed"
    }
    $receipt.actions = @($actions)
    $receipt["error"] = $_.Exception.Message
    Write-Receipt $receipt
    throw
}
finally {
    foreach ($entry in @($processHandles)) {
        if ($null -ne $entry.process) {
            $entry.process.Dispose()
        }
    }
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("crh-apply-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
