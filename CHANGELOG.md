# Changelog

## [Unreleased]

- Add a digest-approved v0.2 apply workflow with fresh ownership and two-sample preflight.
- Revalidate PID, parent PID, creation time, path, fingerprint, and process-tree safety before action.
- Acquire every original process handle before terminating descendants first.
- Add mandatory post-apply audit and machine-readable receipt.
- Make the README Chinese-first and document one-prompt installation.
- Add concrete human-readable and JSON report examples.
- Define the installed Skill's Chinese-first report format.
- Clarify that v0.1 reports and stops; it must not be followed by ad hoc PID termination.

## [0.1.0] - 2026-07-25

- Add a read-only Windows process audit with two-sample CPU and I/O deltas.
- Add ownership-aware classification and approval-plan generation.
- Add PID-reuse, active-task, recent-activity, overlapping-generation, and 17-kernel fixtures.
- Add repository guards, CI, and draft weekly-PR automation.
