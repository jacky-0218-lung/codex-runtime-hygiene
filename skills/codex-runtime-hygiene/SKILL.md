---
name: codex-runtime-hygiene
description: Safely audit and classify Codex Desktop, app-server, MCP, Node kernel, terminal, and descendant runtime processes on Windows, then produce an evidence-based, approval-required reclaim plan without terminating anything. Use when Codex or ChatGPT Desktop accumulates helpers, Node processes, MCP servers, stale terminals, duplicate runtime generations, high memory usage, or suspected orphaned process trees; also use before any proposed Codex process cleanup. Do not use this skill as permission to terminate processes.
---

# Codex Runtime Hygiene

Audit first. Treat memory use as severity evidence, never as permission to terminate.

## Safety contract

- Keep v0.1 read-only. Do not call `Stop-Process`, `taskkill`, WMI termination, or equivalent APIs.
- Protect any process linked to a loaded thread, active or idle task, background terminal, active workspace, or recent CPU/I/O.
- Validate identities with PID plus creation time. Never trust a PID alone.
- Cap classification at `suspected_excess` when task ownership is missing or incomplete.
- Produce `reclaim_candidate` only when ownership evidence is complete, ended-task evidence matches, the process is old, and two samples show no meaningful activity.
- Require explicit approval for any future apply workflow. A plan is not approval.

Read [classification-policy.md](references/classification-policy.md) before classifying or interpreting results. Read [ownership-snapshot.md](references/ownership-snapshot.md) when Codex task or terminal APIs are available. Read [report-format.md](references/report-format.md) before presenting results.

## Workflow

1. Query Codex app-server or host task tools for loaded threads, task status, active turns, workspaces, and background terminals.
2. Build an ownership snapshot following `references/ownership-snapshot.md`. Mark `complete: false` if any authoritative source is unavailable.
3. Run the read-only audit:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit-runtime.ps1 `
     -OwnershipSnapshotPath <ownership.json> `
     -OutputPath <audit.json>
   ```

4. Build the read-only reclaim plan:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-reclaim-plan.ps1 `
     -InputPath <audit.json> `
     -OutputPath <plan.json>
   ```

5. Summarize protected, suspected, ambiguous, and reclaim-candidate groups using `references/report-format.md`. Show exact identity evidence and estimated reclaimable working set.
6. Stop. v0.1 has no apply command.

If host task APIs are unavailable, run the audit without an ownership snapshot and state that no process can reach `reclaim_candidate`.

## Output handling

Audit and plan files may contain local paths and process fingerprints. Keep them outside the repository, do not upload them by default, and redact them before sharing.

Report uncertainty explicitly. Prefer a false negative over a false positive.
