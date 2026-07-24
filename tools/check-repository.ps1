[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$errors = @()
$forbiddenRuntimePatterns = @(
    '\bStop-Process\b',
    '\btaskkill(\.exe)?\b',
    '\.Terminate\s*\('
)

$skillScripts = Get-ChildItem -LiteralPath (Join-Path $root "skills\codex-runtime-hygiene\scripts") -File -Recurse
foreach ($file in $skillScripts) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $forbiddenRuntimePatterns) {
        if ($text -match $pattern) {
            $errors += "Forbidden process primitive found in $($file.FullName): $pattern"
        }
    }
    if ($file.Name -ne "apply-reclaim-plan.ps1" -and $text -match '\.Kill\s*\(') {
        $errors += "Process handle termination is allowed only in apply-reclaim-plan.ps1: $($file.FullName)"
    }
}

$applyPath = Join-Path $root "skills\codex-runtime-hygiene\scripts\apply-reclaim-plan.ps1"
if (Test-Path -LiteralPath $applyPath) {
    $applyText = Get-Content -LiteralPath $applyPath -Raw
    foreach ($requiredPattern in @(
        'ApprovedPlanSha256',
        'SupportsShouldProcess\s*=\s*\$true',
        'Test-ReclaimPlanAgainstFreshPlan',
        'GetProcessById',
        '\.Kill\s*\(',
        'post-apply'
    )) {
        if ($applyText -notmatch $requiredPattern) {
            $errors += "apply-reclaim-plan.ps1 is missing required safety control: $requiredPattern"
        }
    }
}
else {
    $errors += "v0.2 requires apply-reclaim-plan.ps1"
}

$required = @(
    "skills\codex-runtime-hygiene\SKILL.md",
    "skills\codex-runtime-hygiene\agents\openai.yaml",
    "skills\codex-runtime-hygiene\scripts\audit-runtime.ps1",
    "skills\codex-runtime-hygiene\scripts\build-reclaim-plan.ps1",
    "skills\codex-runtime-hygiene\scripts\apply-reclaim-plan.ps1",
    "skills\codex-runtime-hygiene\scripts\reclaim-validation.ps1",
    "skills\codex-runtime-hygiene\references\classification-policy.md",
    "skills\codex-runtime-hygiene\references\apply-policy.md",
    "skills\codex-runtime-hygiene\references\report-format.md",
    "tests\fixtures\active-task.json",
    "tests\fixtures\recent-activity.json",
    "tests\fixtures\pid-reuse.json",
    "tests\fixtures\overlapping-generations.json",
    "tests\fixtures\seventeen-kernels.json",
    "tests\fixtures\ownership-incomplete.json",
    "tests\fixtures\fallback-collector.json"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        $errors += "missing required file: $relative"
    }
}

$skill = Get-Content -LiteralPath (Join-Path $root "skills\codex-runtime-hygiene\SKILL.md") -Raw
if ($skill -notmatch '(?s)^---\r?\nname:\s*codex-runtime-hygiene\r?\ndescription:\s*.+?\r?\n---') {
    $errors += "SKILL.md frontmatter is missing or malformed"
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "repository guard: ok"
