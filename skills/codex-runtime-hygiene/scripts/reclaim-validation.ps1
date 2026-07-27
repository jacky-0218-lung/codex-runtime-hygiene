Set-StrictMode -Version 2.0

function Get-PlanFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath (Resolve-Path -LiteralPath $Path).Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-SameCreationTime {
    param([AllowNull()][string]$Expected, [AllowNull()][string]$Actual)
    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Actual)) {
        return $false
    }
    try {
        $a = [datetime]::Parse($Expected).ToUniversalTime()
        $b = [datetime]::Parse($Actual).ToUniversalTime()
        return [math]::Abs(($a - $b).TotalSeconds) -lt 1
    }
    catch {
        return $false
    }
}

function Test-SameText {
    param([AllowNull()][string]$Expected, [AllowNull()][string]$Actual)
    if ([string]::IsNullOrWhiteSpace($Expected) -or [string]::IsNullOrWhiteSpace($Actual)) {
        return $false
    }
    return [string]::Equals($Expected, $Actual, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ReclaimPlanAgainstFreshPlan {
    param(
        [Parameter(Mandatory = $true)]$ApprovedPlan,
        [Parameter(Mandatory = $true)]$FreshPlan
    )

    $errors = @()
    if ([string]$ApprovedPlan.schemaVersion -ne "2.0") {
        $errors += "Approved plan schema must be 2.0."
    }
    if (-not [bool]$ApprovedPlan.applySupported) {
        $errors += "Approved plan does not support apply."
    }
    if (-not [bool]$ApprovedPlan.approvalRequired) {
        $errors += "Approved plan does not require approval."
    }
    if ([string]$FreshPlan.schemaVersion -ne "2.0") {
        $errors += "Fresh plan schema must be 2.0."
    }
    if (-not [bool]$FreshPlan.applySupported) {
        $errors += "Fresh plan does not support apply."
    }

    $approvedTargets = @($ApprovedPlan.exactApprovalTargets)
    if ($approvedTargets.Count -eq 0) {
        $errors += "Approved plan contains no reclaim targets."
    }

    $freshTargetsByPid = @{}
    foreach ($target in @($FreshPlan.exactApprovalTargets)) {
        $pidValue = [int]$target.pid
        if ($freshTargetsByPid.ContainsKey($pidValue)) {
            $errors += "Fresh plan contains duplicate PID $pidValue."
        }
        else {
            $freshTargetsByPid[$pidValue] = $target
        }
    }

    $approvedPids = New-Object "System.Collections.Generic.HashSet[int]"
    $validated = @()
    foreach ($expected in $approvedTargets) {
        $pidValue = [int]$expected.pid
        if (-not $approvedPids.Add($pidValue)) {
            $errors += "Approved plan contains duplicate PID $pidValue."
            continue
        }
        if (-not $freshTargetsByPid.ContainsKey($pidValue)) {
            $errors += "PID $pidValue is missing or no longer a reclaim candidate."
            continue
        }

        $actual = $freshTargetsByPid[$pidValue]
        $targetErrors = @()
        if ([int]$expected.parentPid -ne [int]$actual.parentPid) {
            $targetErrors += "parent PID"
        }
        if (-not (Test-SameCreationTime ([string]$expected.creationTimeUtc) ([string]$actual.creationTimeUtc))) {
            $targetErrors += "creation time"
        }
        if (-not (Test-SameText ([string]$expected.executablePath) ([string]$actual.executablePath))) {
            $targetErrors += "executable path"
        }
        if (-not (Test-SameText ([string]$expected.commandLineFingerprint) ([string]$actual.commandLineFingerprint))) {
            $targetErrors += "command-line fingerprint"
        }
        if ($targetErrors.Count -gt 0) {
            $errors += "PID $pidValue identity drift: $($targetErrors -join ', ')."
            continue
        }
        $validated += $actual
    }

    foreach ($freshPid in @($freshTargetsByPid.Keys)) {
        if (-not $approvedPids.Contains([int]$freshPid)) {
            $errors += "Fresh plan contains unexpected reclaim candidate PID $freshPid."
        }
    }

    return [pscustomobject]@{
        valid = ($errors.Count -eq 0)
        errors = @($errors)
        validatedTargets = @($validated)
    }
}

function Get-ProcessTreeDepth {
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)]$Processes
    )
    $byPid = @{}
    foreach ($process in @($Processes)) {
        $byPid[[int]$process.pid] = $process
    }
    $depth = 0
    $cursor = $ProcessId
    $seen = New-Object "System.Collections.Generic.HashSet[int]"
    while ($byPid.ContainsKey($cursor) -and $seen.Add($cursor)) {
        $parent = [int]$byPid[$cursor].parentPid
        if ($parent -eq 0 -or -not $byPid.ContainsKey($parent)) {
            break
        }
        $depth += 1
        $cursor = $parent
    }
    return $depth
}
