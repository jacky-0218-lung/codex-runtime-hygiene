# Codex Runtime Hygiene

Windows-first Agent Skill for auditing Codex-related process trees without terminating them.

v0.1 collects two process samples, validates PID plus creation time, incorporates authoritative Codex task ownership when available, and produces a read-only approval plan. It intentionally contains no apply command.

## Development

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-runtime-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-repository.ps1
```

The Skill lives at `skills/codex-runtime-hygiene`. Runtime audit and plan JSON files may contain local paths and must not be committed.

## Maintenance model

The Skill and its weekly maintenance are separate:

- The Skill performs local audit and planning.
- A Codex scheduled task reviews new evidence and proposes repository changes.
- A pushed `weekly-improve-*` branch opens a draft PR through GitHub Actions.
- CI and human review gate every change.
- The scheduled task never terminates processes, installs the Skill, merges PRs, or changes the installed copy.
