[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [string]$OutputPath = (Join-Path (Get-Location) "codex-runtime-reclaim-plan.json"),
    [ValidateRange(1, 10080)]
    [int]$MinimumAgeMinutes = 60,
    [ValidateRange(0, 60000)]
    [double]$RecentCpuThresholdMs = 50,
    [ValidateRange(0, 1073741824)]
    [long]$RecentIoThresholdBytes = 4096
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$audit = Get-Content -LiteralPath (Resolve-Path -LiteralPath $InputPath).Path -Raw | ConvertFrom-Json
if ([string]$audit.schemaVersion -ne "1.0") {
    throw "Unsupported audit schema version: $($audit.schemaVersion)"
}

$ownershipComplete = [bool]$audit.ownership.complete
$minimumAgeSeconds = $MinimumAgeMinutes * 60
$classified = @()

foreach ($p in @($audit.processes)) {
    $reasons = @()
    $blockers = @()
    $class = "suspected_excess"
    $confidence = "low"

    if ([bool]$p.identityDrift -or [bool]$p.ownershipIdentityMismatch) {
        $class = "ambiguous_identity"
        $confidence = "high"
        $blockers += "PID or process identity changed or conflicts with the ownership snapshot."
    }
    elseif (@($p.activeOwnershipMatches).Count -gt 0) {
        $class = "protected"
        $confidence = "high"
        $reasons += "Exact active process identity match."
    }
    elseif (@($p.activeWorkspaceMatches).Count -gt 0) {
        $class = "protected"
        $confidence = "high"
        $reasons += "Process is linked to an active workspace."
    }
    elseif ($null -ne $p.cpuDeltaMs -and [double]$p.cpuDeltaMs -ge $RecentCpuThresholdMs) {
        $class = "protected"
        $confidence = "medium"
        $reasons += "Recent CPU activity exceeded the protection threshold."
    }
    elseif ($null -ne $p.ioDeltaBytes -and [long]$p.ioDeltaBytes -ge $RecentIoThresholdBytes) {
        $class = "protected"
        $confidence = "medium"
        $reasons += "Recent I/O activity exceeded the protection threshold."
    }
    elseif ($null -eq $p.ageSeconds -or [double]$p.ageSeconds -lt $minimumAgeSeconds) {
        $class = "protected"
        $confidence = "medium"
        $reasons += "Process is newer than the minimum-age protection window."
    }
    elseif (-not $ownershipComplete) {
        $class = "suspected_excess"
        $confidence = "low"
        $blockers += "Authoritative ownership snapshot is missing or incomplete."
    }
    elseif ((@($p.endedOwnershipMatches).Count + @($p.endedWorkspaceMatches).Count) -eq 0) {
        $class = "suspected_excess"
        $confidence = "medium"
        $blockers += "No exact ended-task or ended-workspace evidence matches this process."
    }
    elseif (-not [bool]$p.lineageCodexConnected) {
        $class = "suspected_excess"
        $confidence = "low"
        $blockers += "Codex process lineage is not established."
    }
    elseif ($null -eq $p.cpuDeltaMs -or $null -eq $p.ioDeltaBytes) {
        $class = "suspected_excess"
        $confidence = "medium"
        $blockers += "CPU and I/O activity sampling is incomplete."
    }
    elseif ([string]::IsNullOrWhiteSpace([string]$p.executablePath) -or
        [string]::IsNullOrWhiteSpace([string]$p.commandLineFingerprint)) {
        $class = "suspected_excess"
        $confidence = "medium"
        $blockers += "Executable path or command-line fingerprint is unavailable."
    }
    else {
        $class = "reclaim_candidate"
        $confidence = "high"
        $reasons += "Complete ownership snapshot and exact ended-task evidence."
        $reasons += "Old process with no meaningful activity across samples."
    }

    $classified += [pscustomobject]@{
        classification = $class
        confidence = $confidence
        pid = [int]$p.pid
        parentPid = [int]$p.parentPid
        creationTimeUtc = [string]$p.creationTimeUtc
        name = [string]$p.name
        executablePath = $p.executablePath
        commandLineFingerprint = $p.commandLineFingerprint
        workingSetBytes = [long]$p.workingSetBytes
        ageSeconds = $p.ageSeconds
        cpuDeltaMs = $p.cpuDeltaMs
        ioDeltaBytes = $p.ioDeltaBytes
        reasons = @($reasons)
        blockers = @($blockers)
    }
}

$byPid = @{}
foreach ($item in $classified) {
    $byPid[[int]$item.pid] = $item
}
foreach ($item in @($classified | Where-Object { $_.classification -eq "reclaim_candidate" })) {
    $blockedByTree = $false
    $ancestorPid = [int]$item.parentPid
    $seen = New-Object "System.Collections.Generic.HashSet[int]"
    while ($ancestorPid -ne 0 -and $byPid.ContainsKey($ancestorPid) -and $seen.Add($ancestorPid)) {
        $ancestor = $byPid[$ancestorPid]
        if ($ancestor.classification -in @("protected", "ambiguous_identity")) {
            $blockedByTree = $true
            break
        }
        $ancestorPid = [int]$ancestor.parentPid
    }
    if (-not $blockedByTree) {
        foreach ($possibleDescendant in $classified) {
            $cursor = [int]$possibleDescendant.parentPid
            $descendantSeen = New-Object "System.Collections.Generic.HashSet[int]"
            while ($cursor -ne 0 -and $byPid.ContainsKey($cursor) -and $descendantSeen.Add($cursor)) {
                if ($cursor -eq [int]$item.pid) {
                    if ($possibleDescendant.classification -in @("protected", "ambiguous_identity")) {
                        $blockedByTree = $true
                    }
                    break
                }
                $cursor = [int]$byPid[$cursor].parentPid
            }
            if ($blockedByTree) { break }
        }
    }
    if ($blockedByTree) {
        $item.classification = "suspected_excess"
        $item.confidence = "medium"
        $item.blockers = @($item.blockers) + @("A protected or ambiguous process exists in the same ancestor/descendant chain.")
    }
}

$candidates = @($classified | Where-Object { $_.classification -eq "reclaim_candidate" })
$estimated = 0L
foreach ($candidate in $candidates) {
    $estimated += [long]$candidate.workingSetBytes
}

$counts = [ordered]@{}
foreach ($name in @("protected", "ambiguous_identity", "suspected_excess", "reclaim_candidate")) {
    $counts[$name] = @($classified | Where-Object { $_.classification -eq $name }).Count
}

$result = [ordered]@{
    schemaVersion = "2.0"
    generatedAtUtc = [datetime]::UtcNow.ToString("o")
    sourceAudit = (Resolve-Path -LiteralPath $InputPath).Path
    mode = "approval-plan"
    approvalRequired = $true
    applySupported = $true
    thresholds = [ordered]@{
        minimumAgeMinutes = $MinimumAgeMinutes
        recentCpuThresholdMs = $RecentCpuThresholdMs
        recentIoThresholdBytes = $RecentIoThresholdBytes
    }
    summary = [ordered]@{
        counts = $counts
        estimatedReclaimableWorkingSetBytes = $estimated
    }
    processes = @($classified)
    exactApprovalTargets = @($candidates | Select-Object pid, parentPid, creationTimeUtc, executablePath, commandLineFingerprint, workingSetBytes)
    approval = [ordered]@{
        digestAlgorithm = "SHA256"
        digestScope = "Exact bytes of the completed plan file"
        requiredResponseFormat = "APPROVE <64-character-plan-sha256>"
    }
    safety = @(
        "This plan does not terminate processes.",
        "Apply requires an exact user-approved plan-file SHA-256.",
        "Apply revalidates every identity and stops the whole plan on preflight drift.",
        "A post-apply audit and receipt are mandatory."
    )
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    [void](New-Item -ItemType Directory -Force -Path $parent)
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output ("Plan written: {0} ({1} reclaim candidates)" -f $OutputPath, $candidates.Count)
