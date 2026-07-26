# Apply policy

Read this file only when a user asks to reclaim processes after reviewing an audit.

## Approval boundary

1. Build the plan and stop.
2. Show every exact target with PID, creation time, parent PID, executable path, abbreviated command-line fingerprint, and estimated working set.
3. Compute the SHA-256 of the final plan file bytes.
4. Ask the user to reply with exactly:

   ```text
   APPROVE <64-character-plan-sha256>
   ```

5. Do not infer approval from “go ahead,” prior cleanup requests, a plan review, or approval of a different digest.
6. Do not modify, recreate, or re-download the plan after approval.
7. Run `apply-reclaim-plan.ps1` only when the user's digest exactly matches the same file bytes.

## Mandatory preflight

Apply requires:

- a complete ownership snapshot captured within the configured freshness window;
- a fresh two-sample audit;
- every approved target to remain `reclaim_candidate`;
- exact PID, parent PID, creation time, executable path, and command-line fingerprint matches;
- no protected or ambiguous process in the same relevant ancestor or descendant chain;
- a process handle acquired for every target before any termination begins.

Any mismatch blocks the entire plan before action. Never fall back to PID-only termination, `taskkill`, or an incomplete collector.

## Execution and receipt

Terminate descendants before ancestors. Use the already validated process handles so PID reuse after handle acquisition cannot redirect the action to a different process.

After execution:

1. Run a fresh audit and plan.
2. Write the apply receipt.
3. Report terminated, failed, remaining, protected, and ambiguous items.
4. If any runtime action fails, stop remaining actions, retain the receipt, and report that rollback is impossible for processes already terminated.

The workflow reduces identity risk but cannot make multi-process termination transactionally atomic.
