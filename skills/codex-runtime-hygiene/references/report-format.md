# Report format

Use Traditional Chinese first unless the user requests another language. Preserve the machine-readable `audit.json` and `plan.json`, but lead with a compact human-readable report.

## Required sections

1. **Conclusion**
   - Say whether evidence is complete.
   - Say that v0.1 terminated no processes.
   - Do not convert a candidate into a statement that it is safe to delete.
2. **Collection quality**
   - Ownership snapshot completeness and errors.
   - Collector method, sample count, interval, and unavailable evidence.
3. **Summary**
   - Counts for `protected`, `ambiguous_identity`, `suspected_excess`, and `reclaim_candidate`.
   - Total relevant working set and estimated candidate working set.
4. **Evidence by group**
   - Show PID, creation time, executable path, abbreviated command-line fingerprint, working set, activity deltas, reasons, and blockers when available.
   - Redact personal path components unless the user needs the exact local path.
5. **Next action**
   - `protected`: keep.
   - `ambiguous_identity`: collect fresh identity evidence.
   - `suspected_excess`: report only and fill ownership gaps.
   - `reclaim_candidate`: retain as an unapproved target; do not execute.

## Compact example

```text
Codex Runtime Hygiene — 唯讀檢查

結論：目前不建議終止任何程序。
所有權證據：完整
收集方式：Win32_Process，兩次取樣相隔 5 秒

protected              8 個 / 1.42 GiB
ambiguous_identity     1 個 / 96 MiB
suspected_excess       3 個 / 740 MiB
reclaim_candidate      1 個 / 312 MiB

待核准候選 #1
PID / 建立時間：18440 / 2026-07-24T02:14:31Z
路徑：C:\...\node.exe
命令列指紋：SHA256:8B71…C922
活動差值：CPU 0 ms、I/O 0 bytes
證據：已完成任務吻合；身分穩定；超過最低年齡；兩次取樣無活動

動作：未終止任何程序。v0.1 applySupported=false。
```

If ownership is incomplete, state explicitly that no process can reach `reclaim_candidate`.
