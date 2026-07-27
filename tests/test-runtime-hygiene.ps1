[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$builder = Join-Path $root "skills\codex-runtime-hygiene\scripts\build-reclaim-plan.ps1"
$validator = Join-Path $root "skills\codex-runtime-hygiene\scripts\reclaim-validation.ps1"
$apply = Join-Path $root "skills\codex-runtime-hygiene\scripts\apply-reclaim-plan.ps1"
. $validator
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("crh-tests-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $tempRoot)

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message. Expected: $Expected; actual: $Actual"
    }
}

function Assert-Contains {
    param([string]$Expected, $Actual, [string]$Message)
    if (-not ((@($Actual) -join " ") -like ("*" + $Expected + "*"))) {
        throw "$Message. Expected to contain: $Expected; actual: $(@($Actual) -join ' ')"
    }
}

function Copy-JsonObject {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Invoke-Fixture {
    param([string]$Name)
    $inputPath = Join-Path $root ("tests\fixtures\" + $Name + ".json")
    $outputPath = Join-Path $tempRoot ($Name + ".plan.json")
    & $builder -InputPath $inputPath -OutputPath $outputPath | Out-Null
    return Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
}

try {
    $active = Invoke-Fixture "active-task"
    Assert-Equal 1 $active.summary.counts.protected "Active task must be protected"
    Assert-Equal 0 $active.summary.counts.reclaim_candidate "Active task must not be a candidate"

    $activity = Invoke-Fixture "recent-activity"
    Assert-Equal 1 $activity.summary.counts.protected "Recent CPU activity must be protected"

    $reuse = Invoke-Fixture "pid-reuse"
    Assert-Equal 1 $reuse.summary.counts.ambiguous_identity "PID reuse must be ambiguous"
    Assert-Equal 0 $reuse.summary.counts.reclaim_candidate "PID reuse must block a candidate"

    $overlap = Invoke-Fixture "overlapping-generations"
    Assert-Equal 1 $overlap.summary.counts.protected "Current app generation must be protected"
    Assert-Equal 1 $overlap.summary.counts.reclaim_candidate "Old ended generation may enter the approval plan"

    $incomplete = Invoke-Fixture "ownership-incomplete"
    Assert-Equal 1 $incomplete.summary.counts.suspected_excess "Incomplete ownership must cap classification"
    Assert-Equal 0 $incomplete.summary.counts.reclaim_candidate "Incomplete ownership must block candidates"

    $fallback = Invoke-Fixture "fallback-collector"
    Assert-Equal 1 $fallback.summary.counts.suspected_excess "Reduced collector evidence must remain suspected"
    Assert-Equal 0 $fallback.summary.counts.reclaim_candidate "Missing I/O or fingerprint must block candidates"

    $kernels = Invoke-Fixture "seventeen-kernels"
    Assert-Equal 17 @($kernels.processes).Count "17-kernel fixture must contain 17 classified processes"
    Assert-Equal 2 $kernels.summary.counts.protected "Two active kernels must be protected"
    Assert-Equal 15 $kernels.summary.counts.reclaim_candidate "Only the 15 ended kernels may become candidates"
    Assert-Equal 1572864000 $kernels.summary.estimatedReclaimableWorkingSetBytes "Estimated reclaimable memory must sum candidates only"
    Assert-Equal "2.0" ([string]$kernels.schemaVersion) "v0.2 plan schema must be used"
    Assert-Equal $true ([bool]$kernels.applySupported) "v0.2 plan must support approval-bound apply"
    Assert-Equal "APPROVE <64-character-plan-sha256>" ([string]$kernels.approval.requiredResponseFormat) "Plan must state the exact approval format"

    $skillScriptRoot = Join-Path $root "skills\codex-runtime-hygiene\scripts"
    Assert-Equal $true (Test-Path -LiteralPath (Join-Path $skillScriptRoot "apply-reclaim-plan.ps1")) "v0.2 must contain the guarded apply script"

    $samePlan = Test-ReclaimPlanAgainstFreshPlan $overlap $overlap
    Assert-Equal $true ([bool]$samePlan.valid) "An unchanged fresh plan must validate"
    Assert-Equal 1 @($samePlan.validatedTargets).Count "The unchanged target must remain validated"

    $respawn = Invoke-Fixture "respawn-drift"
    $respawnValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $respawn
    Assert-Equal $false ([bool]$respawnValidation.valid) "A newly respawned reclaim target must block the whole approved plan"
    Assert-Contains "unexpected reclaim candidate" $respawnValidation.errors "Respawn drift must be explained"

    $pidReuseDrift = Copy-JsonObject $overlap
    $pidReuseDrift.exactApprovalTargets[0].creationTimeUtc = "2026-07-25T00:00:00Z"
    $reuseValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $pidReuseDrift
    Assert-Equal $false ([bool]$reuseValidation.valid) "Creation-time drift must block the whole plan"
    Assert-Contains "creation time" $reuseValidation.errors "Creation-time drift must be explained"

    $pathDrift = Copy-JsonObject $overlap
    $pathDrift.exactApprovalTargets[0].executablePath = "C:\different\node.exe"
    $pathValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $pathDrift
    Assert-Equal $false ([bool]$pathValidation.valid) "Executable-path drift must block the whole plan"
    Assert-Contains "executable path" $pathValidation.errors "Path drift must be explained"

    $fingerprintDrift = Copy-JsonObject $overlap
    $fingerprintDrift.exactApprovalTargets[0].commandLineFingerprint = ("f" * 64)
    $fingerprintValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $fingerprintDrift
    Assert-Equal $false ([bool]$fingerprintValidation.valid) "Command-line drift must block the whole plan"
    Assert-Contains "command-line fingerprint" $fingerprintValidation.errors "Fingerprint drift must be explained"

    $demotedPlan = Copy-JsonObject $overlap
    $demotedPlan.exactApprovalTargets = @()
    $demotedValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $demotedPlan
    Assert-Equal $false ([bool]$demotedValidation.valid) "A demoted candidate must block the whole plan"
    Assert-Contains "no longer a reclaim candidate" $demotedValidation.errors "Candidate demotion must be explained"

    $nonApplyFreshPlan = Copy-JsonObject $overlap
    $nonApplyFreshPlan.applySupported = $false
    $nonApplyValidation = Test-ReclaimPlanAgainstFreshPlan $overlap $nonApplyFreshPlan
    Assert-Equal $false ([bool]$nonApplyValidation.valid) "A non-apply fresh plan must block the whole plan"
    Assert-Contains "Fresh plan does not support apply" $nonApplyValidation.errors "Fresh plan capability failure must be explained"

    $planFile = Join-Path $tempRoot "digest-plan.json"
    $overlap | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $planFile -Encoding UTF8
    $digestBefore = Get-PlanFileSha256 $planFile
    Assert-Equal 64 $digestBefore.Length "Plan SHA-256 must contain 64 hexadecimal characters"
    Add-Content -LiteralPath $planFile -Value " " -Encoding UTF8
    $digestAfter = Get-PlanFileSha256 $planFile
    Assert-Equal $false ($digestBefore -eq $digestAfter) "Any plan-byte change must invalidate the approved digest"

    $treeFixture = @(
        [pscustomobject]@{ pid = 9000; parentPid = 0 },
        [pscustomobject]@{ pid = 9001; parentPid = 9000 }
    )
    Assert-Equal 1 (Get-ProcessTreeDepth -ProcessId 9001 -Processes $treeFixture) "Tree depth must place the descendant after its parent"

    $ownershipPath = Join-Path $tempRoot "fresh-ownership.json"
    [ordered]@{
        schemaVersion = "1.0"
        capturedAtUtc = [datetime]::UtcNow.ToString("o")
        source = "synthetic-test"
        complete = $true
        activeProcessIdentities = @()
        endedProcessIdentities = @(
            [ordered]@{
                pid = 4400
                creationTimeUtc = "2026-07-23T08:00:00Z"
                reason = "synthetic completed task"
            }
        )
        activeWorkspaces = @()
        endedWorkspaces = @()
        loadedThreadIds = @()
        activeTaskIds = @()
        backgroundTerminalIds = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ownershipPath -Encoding UTF8

    $overlapPlanPath = Join-Path $tempRoot "overlapping-generations.plan.json"
    $applyReceiptPath = Join-Path $tempRoot "blocked-apply-receipt.json"
    $applyBlocked = $false
    try {
        & $apply `
            -PlanPath $overlapPlanPath `
            -ApprovedPlanSha256 (Get-PlanFileSha256 $overlapPlanPath) `
            -OwnershipSnapshotPath $ownershipPath `
            -ValidateOnly `
            -SampleIntervalSeconds 5 `
            -ReceiptOutputPath $applyReceiptPath | Out-Null
    }
    catch {
        $applyBlocked = $true
    }
    Assert-Equal $true $applyBlocked "Synthetic stale targets must be blocked by live preflight"
    Assert-Equal $true (Test-Path -LiteralPath $applyReceiptPath) "Blocked preflight must write a receipt"
    $blockedReceipt = Get-Content -LiteralPath $applyReceiptPath -Raw | ConvertFrom-Json
    Assert-Equal $false ([bool]$blockedReceipt.preflightValid) "Blocked preflight receipt must remain invalid"
    Assert-Equal 0 @($blockedReceipt.actions).Count "Blocked preflight must perform no process actions"

    Write-Output "runtime hygiene tests: 42 assertions passed"
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("crh-tests-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
