# Ownership snapshot

Create this file from Codex app-server or host task tools immediately before the process audit.

```json
{
  "schemaVersion": "1.0",
  "capturedAtUtc": "2026-07-25T00:00:00Z",
  "source": "codex-app-server",
  "complete": true,
  "activeProcessIdentities": [
    {
      "pid": 4242,
      "creationTimeUtc": "2026-07-24T23:00:00Z",
      "reason": "background terminal for loaded thread"
    }
  ],
  "endedProcessIdentities": [
    {
      "pid": 3131,
      "creationTimeUtc": "2026-07-23T08:00:00Z",
      "reason": "terminal belongs to completed task"
    }
  ],
  "activeWorkspaces": [
    "C:\\work\\active-project"
  ],
  "endedWorkspaces": [
    "C:\\work\\completed-project"
  ],
  "loadedThreadIds": [],
  "activeTaskIds": [],
  "backgroundTerminalIds": []
}
```

## Completeness

Set `complete: true` only when all available loaded-thread, task-status, turn-lifecycle, workspace, and background-terminal sources were queried successfully. Otherwise use `false` and record an explanatory `errors` array.

## Identity rules

- Record UTC creation time with the PID.
- Prefer exact terminal process identities when the host exposes them.
- Use workspace paths only as supporting ownership evidence.
- Never infer that a task ended merely because it is not visible in one paginated response.
- Capture the snapshot close to the process samples; stale ownership is incomplete ownership.

The audit stores command-line fingerprints rather than unredacted command lines by default.
