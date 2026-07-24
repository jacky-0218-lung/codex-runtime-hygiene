[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$builder = Join-Path $root "skills\codex-runtime-hygiene\scripts\build-reclaim-plan.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("crh-tests-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $tempRoot)

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message. Expected: $Expected; actual: $Actual"
    }
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
    Assert-Equal $false ([bool]$kernels.applySupported) "v0.1 plan must not support apply"

    $skillScriptRoot = Join-Path $root "skills\codex-runtime-hygiene\scripts"
    if (Test-Path -LiteralPath (Join-Path $skillScriptRoot "apply-reclaim-plan.ps1")) {
        throw "v0.1 must not contain an apply script"
    }

    Write-Output "runtime hygiene tests: 18 assertions passed"
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("crh-tests-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}
