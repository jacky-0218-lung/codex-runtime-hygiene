# Codex Runtime Hygiene

Windows 優先的 Codex Skill：找出可能殘留、重複或仍在使用中的 Codex、MCP、Node kernel 與背景終端程序，產生可審查的唯讀報告。

> v0.1 只做 `audit` 與 `plan`，不會終止任何程序，也不提供刪除指令。

## 一個提示詞安裝

可以。把下面整段貼給 Codex，Codex 可在同一個任務中完成下載、靜態檢查與安裝：

```text
請從 https://github.com/jacky-0218-lung/codex-runtime-hygiene/tree/main/skills/codex-runtime-hygiene
安裝 codex-runtime-hygiene Skill。

只取得 skills/codex-runtime-hygiene 完整子目錄，安裝到 Codex 信任的個人 skills 目錄。
安裝前先靜態檢查 SKILL.md、references、scripts 與 agents；不要為了安裝而執行下載的腳本。
如果目的地已存在，請停止並回報差異，不要覆蓋。
安裝後回報來源 commit、完整檔案清單、安裝路徑，以及是否需要開啟新任務才會生效。
```

公開 repo 通常不需要 GitHub 登入。要讓安裝內容可重現，請把網址中的 `main` 換成 release tag 或完整 commit SHA。更完整的安裝說明見 [install.md](install.md)。

## 怎麼使用

安裝完成後，建議開一個新 Codex 任務，貼上：

```text
使用 $codex-runtime-hygiene 檢查目前是否有 Codex 殘留程序。
只執行 audit 和 plan，不要終止任何程序。
用中文摘要結果，並列出 protected、ambiguous_identity、
suspected_excess 與 reclaim_candidate 的證據和下一步。
```

也可以直接用自然語言觸發，例如：

```text
幫我檢查為什麼 Codex 累積很多 Node、MCP 或背景終端程序。
只做唯讀檢查，不要清理。
```

Skill 會先查詢 Codex 任務與背景終端的使用狀態，再對 Windows 程序取兩次樣本，最後分類：

| 分類 | 意義 | v0.1 動作 |
|---|---|---|
| `protected` | 正在使用、近期有活動或仍在保護期 | 絕不列入清理目標 |
| `ambiguous_identity` | PID 重用、身分漂移或證據衝突 | 重新取樣與補證據 |
| `suspected_excess` | 看起來多餘，但任務所有權或活動資料不完整 | 只報告 |
| `reclaim_candidate` | 完整所有權、已結束任務、穩定身分與跨樣本無活動都吻合 | 只產生待核准目標 |

## 報告會長怎樣

Codex 會先提供中文摘要，並保留 `audit.json` 與 `plan.json` 供精確審查。以下為合成範例：

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
證據：屬於已完成任務；程序樹身分穩定；超過最低年齡；兩次取樣無活動

動作：未終止任何程序。v0.1 applySupported=false。
```

完整欄位與 JSON 範例見 [examples/report-example.md](examples/report-example.md)。

## 報告出來後，要再叫 Codex 刪除嗎？

**不要。v0.1 的安全流程在報告與人工審查後就停止。**

即使出現 `reclaim_candidate`，它仍只是「未來可交給核准式清理器的精確目標」，不是刪除許可。直接叫一般 Codex 按 PID 終止程序，會繞過建立時間、路徑、命令列指紋與整棵程序樹的重新驗證。

預計 v0.2 才會加入獨立的核准式 apply 流程；執行前必須重新比對整份計畫，任何 PID 重用或身分漂移都整批停止。在那之前，若需要立即釋放資源，優先正常關閉相關任務、背景終端或 Codex App，再重新稽核。

## 每週維護

Skill 與每週維護是兩件事：

- Skill 在使用者電腦上做唯讀稽核與分類。
- Codex 排程每週檢查新證據、Windows/Codex 變更與改善機會。
- 只有具體且可驗證的改善才建立 `weekly-improve-*` 分支與 Draft PR。
- 排程不終止程序、不安裝 Skill、不自動合併 PR，也不直接修改已安裝版本。

## 開發與驗證

Skill 位於 `skills/codex-runtime-hygiene`。稽核輸出的 JSON 可能包含本機路徑與程序指紋，不應提交到 repo。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-runtime-hygiene.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-repository.ps1
```

---

## English

Codex Runtime Hygiene is a Windows-first, read-only Agent Skill for auditing Codex-related process trees. v0.1 samples activity twice, validates PID plus creation time, incorporates authoritative task ownership when available, and produces an approval-oriented plan without terminating anything.

Install it by asking Codex to copy the complete `skills/codex-runtime-hygiene` subtree into the trusted personal skills directory, statically inspect the files first, and stop if the destination already exists. Start a new task afterward and ask:

```text
Use $codex-runtime-hygiene to audit possible Codex runtime leftovers.
Run audit and plan only. Do not terminate any process.
```

The weekly review automation proposes improvements through draft PRs; it never kills processes, installs the Skill, merges PRs, or changes an installed copy.
