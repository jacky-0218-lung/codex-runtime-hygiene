# Codex Runtime Hygiene

安全檢查 Windows 上可能殘留的 Codex、MCP、Node kernel 與背景終端程序。

它會告訴你哪些程序仍在使用、哪些證據不足，以及哪些可能是已結束任務留下的程序。**預設只產生報告；沒有精確核准就不會關閉任何程序。**

## 適合什麼情況？

- Codex 開久後出現大量 Node、MCP 或 helper 程序
- 關閉任務後，記憶體占用沒有下降
- 重新開啟 Codex 後，懷疑新舊兩批程序同時存在
- 想檢查殘留程序，但不希望只靠 PID、名稱或記憶體大小判斷

## 安裝

### 選擇 A：只安裝

把下面這段貼給 Codex：

```text
請從 https://github.com/jacky-0218-lung/codex-runtime-hygiene/tree/main/skills/codex-runtime-hygiene
安裝 codex-runtime-hygiene Skill。

安裝前請先靜態檢查完整 Skill 內容，不要執行下載的腳本。
如果目的地已存在，請停止並回報，不要覆蓋。
安裝後告訴我來源 commit、安裝路徑，以及是否需要開啟新任務才會生效。
```

安裝通常可在一個 Codex 任務內完成。完成後建議開啟新任務再使用。

### 選擇 B：安裝並每週自動檢查

如果希望安裝後每週收到一次唯讀報告，把下面整段貼給 Codex：

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

這是一個提示詞完成兩個明確動作：安裝 Skill，以及建立每週排程。它不是安裝後偷偷啟用的背景服務。電腦必須開機，而且 Codex Desktop 必須持續執行，排程才會在本機準時啟動。

每週排程只會產生報告，不會自動清理。即使報告出現「待核准候選」，仍要回到互動式任務查看完整計畫，並另外核准精確的計畫 SHA-256。

需要固定版本、更新既有安裝或檢查排程是否建立成功時，請參考[完整安裝說明](install.md)。

## 使用

在新的 Codex 任務中輸入：

```text
使用 $codex-runtime-hygiene 檢查是否有 Codex 殘留程序。
先做檢查，不要終止任何程序。
```

你也可以直接說：

```text
幫我檢查為什麼 Codex 累積很多 Node 和 MCP 程序，不要清理。
```

檢查過程通常需要幾秒鐘，因為 Skill 會取兩次活動樣本，避免把暫時安靜但仍在工作的程序誤判為殘留。

## 你會拿到什麼？

Codex 會先用中文說明結論，再把程序分成四類：

| 分類 | 代表什麼 |
|---|---|
| 使用中／受保護 | 屬於目前任務、背景終端，或近期仍有 CPU／I/O 活動 |
| 身分有疑問 | PID 可能重用，或前後兩次資料不一致 |
| 疑似多餘 | 看起來像殘留，但任務所有權或活動證據還不完整 |
| 待核准候選 | 已完成任務、程序身分與靜止證據完整；必須另外精確核准 |

報告範例如下：

```text
Codex Runtime Hygiene — 唯讀檢查

結論：發現 3 個疑似多餘程序；目前沒有可確認的清理候選。
檢查品質：任務所有權資料不完整，因此採取保守判定。

使用中／受保護    8 個 / 1.42 GiB
身分有疑問        1 個 / 96 MiB
疑似多餘          3 個 / 740 MiB
待核准候選        0 個 / 0 MiB

本次沒有終止任何程序。
```

需要精確審查時，Codex 也會保留本機 `audit.json` 與 `plan.json`。這些檔案可能包含本機路徑，不應直接公開。查看[完整報告範例](examples/report-example.md)。

## 它怎麼避免誤判？

Skill 不會因為「記憶體很高」或「程序很久沒動」就認定可以清理。它會一起檢查：

- Codex 任務與背景終端是否仍在使用
- PID 與程序建立時間是否一致
- 執行檔路徑與命令列指紋
- 父子程序關係
- 兩次取樣之間的 CPU 與 I/O 活動

只要所有權資料缺少、程序身分改變，或同一棵程序樹中仍有受保護項目，結果就會降級為「疑似多餘」或「身分有疑問」。

## 報告後會自動清理嗎？

不會。如果只要求檢查，流程會停在報告：

```text
檢查 → 分類 → 顯示證據 → 停止
```

報告中的 PID 也不應直接轉成 `Stop-Process` 或 `taskkill` 指令，因為 PID 可能已被其他新程序重新使用。

如果希望清理「待核准候選」，請要求 Codex 顯示完整目標與計畫 SHA-256。只有回覆完全相同的：

```text
APPROVE <計畫的 64 字元 SHA-256>
```

才會重新檢查整份計畫。任何 PID、建立時間、父程序、路徑、命令列指紋或程序樹狀態改變，都會在終止前停止整批操作。完成後會再檢查一次並產生收據。

## 支援範圍

- Windows 優先
- PowerShell 5.1 或更新版本
- Codex Desktop／app-server 相關程序
- MCP servers、Node kernels、背景終端及其程序樹

目前版本：**v0.2，預設唯讀；支援精確核准式清理**

## 授權

本專案採用 [MIT License](LICENSE)。你可以依授權條款使用、修改與散布本專案。

---

English summary: Codex Runtime Hygiene is a Windows-first Skill that audits Codex-related process trees. Reclaim requires an exact plan digest approval and a fresh full-plan identity check.
