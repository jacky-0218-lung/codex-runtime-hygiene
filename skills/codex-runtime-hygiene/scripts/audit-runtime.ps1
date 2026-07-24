[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Get-Location) "codex-runtime-audit.json"),
    [ValidateRange(0, 300)]
    [int]$SampleIntervalSeconds = 5,
    [string]$OwnershipSnapshotPath,
    [switch]$IncludeCommandLinePreview
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

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
    try {
        if ($Value -is [datetime]) {
            return $Value.ToUniversalTime().ToString("o")
        }
        return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToUniversalTime().ToString("o")
    }
    catch {
        return $null
    }
}

function Protect-CommandLine {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $redacted = $Text
    $patterns = @(
        '(?i)(authorization:\s*bearer\s+)[^\s"]+',
        '(?i)(api[_-]?key\s*[=:]\s*)[^\s"]+',
        '(?i)(token\s*[=:]\s*)[^\s"]+',
        '(?i)(password\s*[=:]\s*)[^\s"]+'
    )
    foreach ($pattern in $patterns) {
        $redacted = [regex]::Replace($redacted, $pattern, '$1<redacted>')
    }
    if ($redacted.Length -gt 240) {
        $redacted = $redacted.Substring(0, 240) + "..."
    }
    return $redacted
}

function Read-OwnershipSnapshot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [pscustomobject]@{
            source = "none"
            complete = $false
            activeProcessIdentities = @()
            endedProcessIdentities = @()
            activeWorkspaces = @()
            endedWorkspaces = @()
            errors = @("No authoritative ownership snapshot was supplied.")
        }
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $data = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json
    return [pscustomobject]@{
        source = if ($data.source) { [string]$data.source } else { "unknown" }
        complete = [bool]$data.complete
        activeProcessIdentities = @($data.activeProcessIdentities)
        endedProcessIdentities = @($data.endedProcessIdentities)
        activeWorkspaces = @($data.activeWorkspaces)
        endedWorkspaces = @($data.endedWorkspaces)
        errors = @($data.errors)
    }
}

function Test-Identity {
    param($Process, $Identity)
    if ([int]$Process.pid -ne [int]$Identity.pid) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Identity.creationTimeUtc)) { return $false }
    try {
        $a = [datetime]::Parse([string]$Process.creationTimeUtc).ToUniversalTime()
        $b = [datetime]::Parse([string]$Identity.creationTimeUtc).ToUniversalTime()
        return [math]::Abs(($a - $b).TotalSeconds) -lt 1
    }
    catch {
        return $false
    }
}

function Test-TextContainsPath {
    param([AllowNull()][string]$Text, [AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
    return $Text.IndexOf($Path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-ToolhelpParentMap {
    if (-not ("CodexRuntimeHygiene.NativeMethods" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace CodexRuntimeHygiene {
    public static class NativeMethods {
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct PROCESSENTRY32 {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool Process32First(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool Process32Next(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        public static Dictionary<int, int> ParentMap() {
            var result = new Dictionary<int, int>();
            IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == INVALID_HANDLE_VALUE) {
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            }
            try {
                var entry = new PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                if (Process32First(snapshot, ref entry)) {
                    do {
                        result[(int)entry.th32ProcessID] = (int)entry.th32ParentProcessID;
                        entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                    } while (Process32Next(snapshot, ref entry));
                }
            }
            finally {
                CloseHandle(snapshot);
            }
            return result;
        }
    }
}
"@
    }
    return [CodexRuntimeHygiene.NativeMethods]::ParentMap()
}

$script:collectionErrors = @()
$script:collectorCapabilities = [ordered]@{
    source = "Win32_Process"
    parentProcessId = $true
    commandLine = $true
    executablePath = $true
    cpu = $true
    io = $true
}

function Get-ProcessSample {
    $items = @()
    try {
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)) {
            $creation = Convert-ToUtcText $p.CreationDate
            $commandLine = [string]$p.CommandLine
            $path = [string]$p.ExecutablePath
            $signalText = "{0} {1} {2}" -f [string]$p.Name, $path, $commandLine
            $isCodexSignal = $signalText -match '(?i)(openai\.codex|chatgpt|(^|[\\/\s._-])codex([\\/\s._-]|$)|[\\/]\.codex[\\/])'
            $items += [pscustomobject]@{
                pid = [int]$p.ProcessId
                parentPid = [int]$p.ParentProcessId
                creationTimeUtc = $creation
                name = [string]$p.Name
                executablePath = if ([string]::IsNullOrWhiteSpace($path)) { $null } else { $path }
                commandLineFingerprint = Get-Sha256Text $commandLine
                commandLinePreview = if ($IncludeCommandLinePreview) { Protect-CommandLine $commandLine } else { $null }
                sessionId = [int]$p.SessionId
                workingSetBytes = [long]$p.WorkingSetSize
                cpu100ns = ([long]$p.KernelModeTime + [long]$p.UserModeTime)
                ioBytes = ([long]$p.ReadTransferCount + [long]$p.WriteTransferCount + [long]$p.OtherTransferCount)
                isCodexSignal = [bool]$isCodexSignal
                rawCommandLine = $commandLine
            }
        }
        return @($items)
    }
    catch {
        $script:collectionErrors += "Win32_Process unavailable; using reduced Get-Process collector: $($_.Exception.Message)"
        $script:collectorCapabilities = [ordered]@{
            source = "Get-Process+Toolhelp32"
            parentProcessId = $true
            commandLine = $false
            executablePath = $true
            cpu = $true
            io = $false
        }
    }

    $parentMap = Get-ToolhelpParentMap
    foreach ($p in @(Get-Process)) {
        $creation = $null
        $path = $null
        $cpuTicks = $null
        try { $creation = $p.StartTime.ToUniversalTime().ToString("o") } catch {}
        try { $path = [string]$p.Path } catch {}
        try { $cpuTicks = [long]$p.TotalProcessorTime.Ticks } catch {}
        $signalText = "{0} {1}" -f [string]$p.ProcessName, $path
        $isCodexSignal = $signalText -match '(?i)(openai\.codex|chatgpt|(^|[\\/\s._-])codex([\\/\s._-]|$)|[\\/]\.codex[\\/])'
        $parentPid = 0
        if ($parentMap.ContainsKey([int]$p.Id)) {
            $parentPid = [int]$parentMap[[int]$p.Id]
        }
        $items += [pscustomobject]@{
            pid = [int]$p.Id
            parentPid = $parentPid
            creationTimeUtc = $creation
            name = ([string]$p.ProcessName + ".exe")
            executablePath = if ([string]::IsNullOrWhiteSpace($path)) { $null } else { $path }
            commandLineFingerprint = $null
            commandLinePreview = $null
            sessionId = [int]$p.SessionId
            workingSetBytes = [long]$p.WorkingSet64
            cpu100ns = $cpuTicks
            ioBytes = $null
            isCodexSignal = [bool]$isCodexSignal
            rawCommandLine = $null
        }
    }
    return @($items)
}

$ownership = Read-OwnershipSnapshot $OwnershipSnapshotPath
$firstCapturedAt = [datetime]::UtcNow
$first = @(Get-ProcessSample)
if ($SampleIntervalSeconds -gt 0) {
    Start-Sleep -Seconds $SampleIntervalSeconds
}
$secondCapturedAt = [datetime]::UtcNow
$second = @(Get-ProcessSample)

$firstByPid = @{}
foreach ($p in $first) { $firstByPid[[int]$p.pid] = $p }
$secondByPid = @{}
foreach ($p in $second) { $secondByPid[[int]$p.pid] = $p }

$seedPids = New-Object "System.Collections.Generic.HashSet[int]"
foreach ($p in $second) {
    if ($p.isCodexSignal) { [void]$seedPids.Add([int]$p.pid) }
}
foreach ($identity in @($ownership.activeProcessIdentities) + @($ownership.endedProcessIdentities)) {
    if ($null -ne $identity.pid) { [void]$seedPids.Add([int]$identity.pid) }
}

$included = New-Object "System.Collections.Generic.HashSet[int]"
foreach ($pidValue in $seedPids) { [void]$included.Add($pidValue) }

$changed = $true
while ($changed) {
    $changed = $false
    foreach ($p in $second) {
        if ($included.Contains([int]$p.pid) -and $secondByPid.ContainsKey([int]$p.parentPid)) {
            if ($included.Add([int]$p.parentPid)) { $changed = $true }
        }
        if ($included.Contains([int]$p.parentPid)) {
            if ($included.Add([int]$p.pid)) { $changed = $true }
        }
    }
}

$processes = @()
foreach ($current in $second) {
    if (-not $included.Contains([int]$current.pid)) { continue }
    $previous = $firstByPid[[int]$current.pid]
    $identityDrift = $false
    if ($null -eq $previous -or [string]$previous.creationTimeUtc -ne [string]$current.creationTimeUtc) {
        $identityDrift = $true
    }

    $activeMatches = @()
    $samePidActiveMismatch = $false
    foreach ($identity in @($ownership.activeProcessIdentities)) {
        if ([int]$identity.pid -eq [int]$current.pid) {
            if (Test-Identity $current $identity) {
                $activeMatches += [string]$identity.reason
            }
            else {
                $samePidActiveMismatch = $true
            }
        }
    }

    $endedMatches = @()
    $samePidEndedMismatch = $false
    foreach ($identity in @($ownership.endedProcessIdentities)) {
        if ([int]$identity.pid -eq [int]$current.pid) {
            if (Test-Identity $current $identity) {
                $endedMatches += [string]$identity.reason
            }
            else {
                $samePidEndedMismatch = $true
            }
        }
    }

    $activeWorkspaceMatches = @()
    foreach ($workspace in @($ownership.activeWorkspaces)) {
        if ((Test-TextContainsPath $current.rawCommandLine ([string]$workspace)) -or
            (Test-TextContainsPath $current.executablePath ([string]$workspace))) {
            $activeWorkspaceMatches += [string]$workspace
        }
    }

    $endedWorkspaceMatches = @()
    foreach ($workspace in @($ownership.endedWorkspaces)) {
        if ((Test-TextContainsPath $current.rawCommandLine ([string]$workspace)) -or
            (Test-TextContainsPath $current.executablePath ([string]$workspace))) {
            $endedWorkspaceMatches += [string]$workspace
        }
    }

    $ageSeconds = $null
    try {
        $ageSeconds = [math]::Max(0, ([datetime]::UtcNow - [datetime]::Parse([string]$current.creationTimeUtc).ToUniversalTime()).TotalSeconds)
    }
    catch {}

    $cpuDeltaMs = $null
    $ioDeltaBytes = $null
    if (-not $identityDrift -and $null -ne $current.cpu100ns -and $null -ne $previous.cpu100ns) {
        $cpuDeltaMs = [math]::Max(0, ([long]$current.cpu100ns - [long]$previous.cpu100ns) / 10000.0)
    }
    if (-not $identityDrift -and $null -ne $current.ioBytes -and $null -ne $previous.ioBytes) {
        $ioDeltaBytes = [math]::Max(0, [long]$current.ioBytes - [long]$previous.ioBytes)
    }

    $processes += [pscustomobject]@{
        pid = [int]$current.pid
        parentPid = [int]$current.parentPid
        creationTimeUtc = $current.creationTimeUtc
        name = $current.name
        executablePath = $current.executablePath
        commandLineFingerprint = $current.commandLineFingerprint
        commandLinePreview = $current.commandLinePreview
        sessionId = [int]$current.sessionId
        workingSetBytes = [long]$current.workingSetBytes
        ageSeconds = $ageSeconds
        cpuDeltaMs = $cpuDeltaMs
        ioDeltaBytes = $ioDeltaBytes
        isCodexSignal = [bool]$current.isCodexSignal
        lineageCodexConnected = $true
        identityDrift = [bool]$identityDrift
        ownershipIdentityMismatch = [bool]($samePidActiveMismatch -or $samePidEndedMismatch)
        activeOwnershipMatches = @($activeMatches)
        endedOwnershipMatches = @($endedMatches)
        activeWorkspaceMatches = @($activeWorkspaceMatches)
        endedWorkspaceMatches = @($endedWorkspaceMatches)
    }
}

$result = [ordered]@{
    schemaVersion = "1.0"
    generatedAtUtc = [datetime]::UtcNow.ToString("o")
    mode = "read-only"
    sampling = [ordered]@{
        intervalSeconds = $SampleIntervalSeconds
        firstCapturedAtUtc = $firstCapturedAt.ToString("o")
        secondCapturedAtUtc = $secondCapturedAt.ToString("o")
    }
    ownership = [ordered]@{
        source = $ownership.source
        complete = [bool]$ownership.complete
        errors = @($ownership.errors)
    }
    collector = $script:collectorCapabilities
    collectionErrors = @($script:collectionErrors | Select-Object -Unique)
    processCount = @($processes).Count
    processes = @($processes)
    warnings = @(
        "This audit is read-only and is not permission to terminate processes.",
        "Command lines are fingerprinted; previews are omitted unless explicitly requested.",
        "Reports may contain local paths and must not be committed by default."
    )
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    [void](New-Item -ItemType Directory -Force -Path $parent)
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output ("Audit written: {0} ({1} relevant processes)" -f $OutputPath, @($processes).Count)
