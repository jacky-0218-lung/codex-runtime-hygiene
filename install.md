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

預期結果應明確寫出 `v0.1`、`read-only`、`applySupported=false`，並以中文摘要四種分類。

---

## English quick install

Ask Codex to install the complete `skills/codex-runtime-hygiene` subtree into the trusted personal skills directory, statically inspect every file before copying, report the resolved commit and file list, and stop without overwriting if the destination already exists. Pin a release tag or full commit SHA when reproducibility matters.
