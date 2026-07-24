# Classification policy

## Invariants

1. High memory, process name, PID, age, or low activity alone never authorizes cleanup.
2. Match an identity by PID, creation time, executable path, and command-line fingerprint when available.
3. A reused PID or any identity drift blocks cleanup.
4. A protected descendant blocks cleanup of its ancestor tree.
5. Missing ownership evidence lowers confidence; it never increases it.
6. Audit and plan are always read-only. Apply is a separate digest-approved workflow.

## Classes

| Class | Required evidence | Action |
|---|---|---|
| `protected` | Active ownership match, active workspace match, recent CPU/I/O, or newly created process | Never include in a reclaim target |
| `ambiguous_identity` | PID reuse, creation-time mismatch, sample drift, or contradictory ownership | Report the conflict; collect fresh evidence |
| `suspected_excess` | Codex-connected, old and quiet, but ownership is incomplete or no ended-task evidence matches | Report only |
| `reclaim_candidate` | Complete ownership snapshot, exact ended-task evidence, Codex lineage, minimum age, quiet across samples, and no identity conflict | Include in a digest-bound approval plan |

## Default thresholds

- Minimum age: 60 minutes.
- Sampling interval: 5 seconds.
- Recent CPU threshold: 50 milliseconds during the interval.
- Recent I/O threshold: 4096 bytes during the interval.

Thresholds reduce noise; they do not replace ownership evidence.

## Ownership precedence

Apply evidence in this order:

1. Exact active PID plus creation-time match.
2. Active terminal or task identity match.
3. Active workspace match.
4. Recent CPU or I/O.
5. Exact ended-task identity or ended-workspace match.
6. Heuristics such as age, duplicate executable, or old application generation.

Items 1–4 protect. Item 5 can support a reclaim candidate. Item 6 can only support `suspected_excess`.

## Tree rule

Never plan a tree-level reclaim when any member is protected or ambiguous. Apply must re-sample the entire tree and revalidate every identity immediately before acting. Any preflight drift must stop the whole approved plan.

## Confidence

- `high`: complete authoritative ownership plus exact ended-task evidence and stable identity.
- `medium`: strong Codex lineage and inactivity, but one authoritative ownership dimension is absent.
- `low`: heuristic-only evidence.

Only `high` confidence can become `reclaim_candidate`.

If the host denies `Win32_Process`, the audit falls back to `Get-Process` plus the Windows Tool Help API. That fallback retains PID, creation time, parent relationship, path, memory and CPU sampling, but cannot reliably collect command lines or I/O counters. Therefore fallback-only processes cannot become `reclaim_candidate`; they remain protected, ambiguous, or suspected until richer evidence is collected.
