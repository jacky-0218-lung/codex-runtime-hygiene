# 安裝 Codex Runtime Hygiene

## 最簡單：貼一個提示詞

把以下內容貼到 Codex：

```text
請從 https://github.com/jacky-0218-lung/codex-runtime-hygiene/tree/main/skills/codex-runtime-hygiene
安裝 codex-runtime-hygiene Skill。

只取得 skills/codex-runtime-hygiene 完整子目錄，安裝到 Codex 信任的個人 skills 目錄。
安裝前先靜態檢查 SKILL.md、references、scripts 與 agents；不要為了安裝而執行下載的腳本。
如果目的地已存在，請停止並回報差異，不要覆蓋。
安裝後回報來源 commit、完整檔案清單、安裝路徑，以及是否需要開啟新任務才會生效。
```

這段提示詞已明確授權安裝，但沒有授權覆蓋現有版本，也沒有授權執行 Skill 中的稽核腳本。

## Codex 應完成的事情

1. 解析 repo 中 `skills/codex-runtime-hygiene` 的完整子目錄。
2. 取得固定來源版本，並回報實際 commit SHA。
3. 靜態檢查所有要安裝的檔案，不執行下載內容。
4. 確認目的地不存在。
5. 安裝到 `$CODEX_HOME/skills/codex-runtime-hygiene`；一般預設等同 `~/.codex/skills/codex-runtime-hygiene`。
6. 回報來源、檔案清單與安裝位置。

安裝通常可在同一個 Codex 任務完成。為確保 Skill 清單重新載入，完成後建議開一個新任務再使用。

## 安裝並建立每週唯讀檢查

如果希望 Codex 每週自動檢查一次，可以用一個提示詞同時要求安裝與建立排程：

```text
請安裝：
https://github.com/jacky-0218-lung/codex-runtime-hygiene/tree/main/skills/codex-runtime-hygiene

安裝前先靜態檢查完整 Skill；若目的地存在就停止，不要覆蓋。
安裝成功後，建立名為「Codex Runtime Hygiene Weekly Audit」的排程：
- 每週一上午 9:00（使用者當地時區）
- 使用 $codex-runtime-hygiene
- 只做 audit 和 plan
- 絕不執行 apply，也不終止任何程序
- 無異常時只回報簡短摘要
- 發現 suspected_excess 或 reclaim_candidate 時，列出證據並通知我
- 如果同名排程已存在，就更新它，不要重複建立

最後回報來源 commit、安裝位置、排程時間與排程狀態。
```

這個流程有幾項重要限制：

- 安裝 Skill 與建立排程是兩個明確動作；安裝本身不會偷偷新增背景工作。
- 本機排程執行時，電腦必須開機，而且 Codex Desktop 必須持續執行。
- 同名排程應更新而不是重複建立，避免每週收到多份相同報告。
- 排程只允許 `audit` 與 `plan`。不得在無人互動時執行 `apply`、`Stop-Process`、`taskkill` 或任何等效終止操作。
- 排程發現 `reclaim_candidate` 時只通知。清理仍必須在互動式任務中顯示完整計畫，並取得完全相同的 `APPROVE <SHA-256>` 核准。

建立後，請在 Codex Desktop 的排程頁面確認：

1. 名稱是 `Codex Runtime Hygiene Weekly Audit`。
2. 時區與預定時間正確。
3. 提示詞明確包含 `$codex-runtime-hygiene`、`audit`、`plan` 與「不得執行 apply」。
4. 只有一個同名排程。
5. 第一次執行後有產生唯讀摘要，且沒有終止任何程序。

## 可重現安裝

`main` 會隨 repo 更新。需要完全可重現時，請把安裝網址固定到 release tag 或完整 commit SHA，例如：

```text
請從下列完整 commit 的 skills/codex-runtime-hygiene 子目錄安裝：
https://github.com/jacky-0218-lung/codex-runtime-hygiene/tree/<完整-commit-SHA>/skills/codex-runtime-hygiene
其餘安全條件與 README 的一個提示詞安裝相同。
```

不要自行填入不存在的 tag。請先從 GitHub release 或 commit 頁面取得實際值。

## 如果已經安裝

若 `$CODEX_HOME/skills/codex-runtime-hygiene` 已存在，Codex 應停止，不應覆蓋。先比較：

- 已安裝來源與目標來源的 commit；
- 完整檔案清單；
- 檔案內容或摘要雜湊；
- 本機是否有未提交或自行修改的內容。

確認替換範圍後，再另外明確核准更新。安裝授權不等於覆蓋授權。

## 安裝後測試

開一個新任務並貼上：

```text
使用 $codex-runtime-hygiene 做唯讀健康檢查。
只建立 audit 與 plan，不要終止任何程序。
```

預期結果應明確寫出 `v0.2`，先以唯讀模式摘要四種分類；沒有精確的計畫 SHA-256 核准時，不得執行清理。

---

## English quick install

Ask Codex to install the complete `skills/codex-runtime-hygiene` subtree into the trusted personal skills directory, statically inspect every file before copying, report the resolved commit and file list, and stop without overwriting if the destination already exists. Pin a release tag or full commit SHA when reproducibility matters.
