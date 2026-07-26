# 報告範例

以下內容完全是合成資料，用來說明 Codex 應如何呈現 `audit` 與 `plan` 的結果，不代表任何真實電腦狀態。

## 中文摘要

### Codex Runtime Hygiene — 唯讀檢查

**結論：目前不建議終止任何程序。**

| 項目 | 結果 |
|---|---|
| 版本／模式 | v0.2 / approval-plan |
| 檢查時間 | 2026-07-25 09:15:00 +09:00 |
| 所有權證據 | 完整 |
| 收集方式 | Win32_Process |
| 取樣 | 2 次，相隔 5 秒 |
| 程序總工作集 | 2.54 GiB |
| 預估候選工作集 | 312 MiB |
| 是否已終止程序 | 否 |

### 分類摘要

| 分類 | 數量 | 工作集 | 解讀 |
|---|---:|---:|---|
| `protected` | 8 | 1.42 GiB | 正在使用、近期有活動或仍在保護期 |
| `ambiguous_identity` | 1 | 96 MiB | PID 或身分證據發生衝突 |
| `suspected_excess` | 3 | 740 MiB | 看似多餘，但證據尚不足 |
| `reclaim_candidate` | 1 | 312 MiB | 符合高信心候選條件，但尚未獲准執行 |

### 受保護項目

- PID 22160，`node.exe`，工作集 438 MiB
  - 保護理由：屬於目前 loaded task 的背景終端。
  - 活動：CPU +184 ms、I/O +96 KiB。
  - 動作：保持執行。

### 身分不明項目

- PID 9604，`node.exe`，工作集 96 MiB
  - 衝突：兩次取樣的建立時間或程序指紋不一致，可能發生 PID 重用。
  - 動作：不列入候選；重新收集所有權與程序樣本。

### 疑似多餘項目

- PID 17312，`codex-app-server.exe` 的舊世代後代，工作集 408 MiB
  - 支持證據：超過 12 小時、兩次取樣低活動、與目前 App 世代重疊。
  - 阻擋原因：沒有精確的已結束任務身分。
  - 動作：只報告。

### 待核准候選

- 候選 `candidate-001`
  - PID：18440
  - 父 PID：17888
  - 建立時間：`2026-07-24T02:14:31.0000000Z`
  - 執行檔：`C:\Users\example\AppData\Local\Programs\Codex\resources\node.exe`
  - 命令列指紋：`SHA256:8B71…C922`
  - 工作集：312 MiB
  - 活動差值：CPU 0 ms、I/O 0 bytes
  - 支持證據：
    - 完整 Codex 所有權快照；
    - 精確吻合已完成任務；
    - Codex 程序樹身分成立；
    - 超過最低年齡；
    - 兩次取樣沒有顯著活動。
  - 動作：等待精確計畫 SHA-256 核准。

### 下一步

1. 保留 `audit.json` 與 `plan.json` 在本機，避免公開其中的路徑與指紋。
2. 先處理 `ambiguous_identity` 與所有權缺口，再重新稽核。
3. 不要把這份報告直接轉成 `Stop-Process` 或 `taskkill` 指令。
4. 只有回覆這份計畫的精確 SHA-256，才可交給 apply 流程重新驗證。

## `plan.json` 節錄

```json
{
  "schemaVersion": "2.0",
  "mode": "approval-plan",
  "approvalRequired": true,
  "applySupported": true,
  "summary": {
    "counts": {
      "protected": 8,
      "ambiguous_identity": 1,
      "suspected_excess": 3,
      "reclaim_candidate": 1
    },
    "estimatedReclaimableWorkingSetBytes": 327155712
  },
  "exactApprovalTargets": [
    {
      "pid": 18440,
      "parentPid": 17888,
      "creationTimeUtc": "2026-07-24T02:14:31.0000000Z",
      "executablePath": "C:\\Users\\example\\AppData\\Local\\Programs\\Codex\\resources\\node.exe",
      "commandLineFingerprint": "SHA256:8B71...C922",
      "workingSetBytes": 327155712
    }
  ],
  "safety": [
    "This plan does not terminate processes.",
    "Apply requires an exact user-approved plan-file SHA-256.",
    "Apply revalidates every identity and stops the whole plan on preflight drift.",
    "A post-apply audit and receipt are mandatory."
  ]
}
```

`exactApprovalTargets` 的存在不代表已獲准，也不表示現在可以手動按 PID 刪除。
