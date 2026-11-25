# Changelog

## 1.2.3 (build 6) — 2026-11-26

The app behaves as in 1.2.2. This release corrects a test.

### Fixed

- The reset check no longer fails when OpenLaunchPad is installed. It now uses the
  launcher's own list of apps. **Reset Launchpad** itself was correct.

### Validation

- All 219 deterministic core tests passed.
- The reset check passed, and it detects three deliberately broken resets.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- App 的行為與 1.2.2 相同，這一版只修正測試。
- 已安裝 OpenLaunchPad 時，重設檢查不會再誤報失敗。**Reset Launchpad** 功能本身一直正常。

## 1.2.2 (build 5) — 2026-11-25

### Fixed

- An app that disappears while it is updated or reinstalled keeps its position
  and folder for ten minutes instead of moving to the end of the last page.
- A change in the application folders during a drag no longer makes that drag and
  every later one fail. After a save conflict, the next drag works again.
- A catalog refresh no longer closes an open folder. Changes wait until the folder
  closes or the drag ends, and a refresh that finds nothing new changes nothing.
- An updated app shows its new name and icon without restarting the agent. Icons of
  newly installed first-page apps are loaded before the next opening.
- Apps added to or removed from subfolders are noticed, and so is a `~/Applications`
  folder created later.

### Validation

- All 219 deterministic core tests passed.
- The new catalog refresh check passed, and the existing drag, folder, paging, icon,
  search, and update checks still pass.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- App 更新或重新安裝時，位置與資料夾會保留十分鐘，不會再排到最後一頁。
- 拖曳途中 App 清單變動，不會再讓這次與之後的拖曳失敗。
- 清單更新不會再關閉開啟中的資料夾；沒有變動時不會重新整理畫面。
- App 更新後會顯示新名稱與新圖示，不需重新啟動背景程式。
- 會偵測子資料夾的變動，也會偵測之後才建立的 `~/Applications`。

## 1.2.1 (build 4) — 2026-11-25

### Fixed

- After replacing the app by hand, the old background agent kept running until
  the next login, so new features such as **Check for Updates** stayed hidden.
  Opening OpenLaunchPad now ends an outdated agent and starts the new one.

### Validation

- All 207 deterministic core tests passed, including the agent identity cases.
- Isolated launcher runs passed for an agent whose app was moved to the Trash,
  overwritten in place, or deleted, for an unchanged copy, and for an agent that
  refuses to quit.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- 手動取代 App 後，舊的背景程式會一直執行到下次登入，因此看不到 **Check for Updates**
  等新功能。現在開啟 OpenLaunchPad 時，會先結束過期的背景程式，再啟動新版。

## 1.2 (build 3) — 2026-11-25

### Added

- **Check for Updates** in the search field's menu. It closes the launcher, then
  downloads, verifies, and installs a newer release with Sparkle. Nothing is
  contacted until the command is chosen.
- Copies of 1.1 and earlier have no updater. Install 1.2 by hand once.

### Validation

- 201 deterministic core tests passed, including the update cases.
- A test build updated itself with Sparkle: download, signature check,
  installation, and relaunch of the embedded agent.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- 搜尋欄選單新增 **Check for Updates**：收起啟動器後，以 Sparkle 下載、驗證並安裝新版本。
  只有點選時才會連線。
- 1.1 及更早的版本沒有更新功能，需要先手動安裝一次 1.2。

## 1.1 (build 2) — 2026-11-12

### Fixed

- Safari now appears in the launcher and search when macOS exposes it through
  a hidden symbolic link in `/Applications`. Discovery accepts hidden app links
  to visible application directories while continuing to skip ordinary hidden
  apps, hidden directories, broken links, and links to hidden targets.
- Existing layouts are preserved. Restart OpenLaunchPad after updating so the
  application catalog refreshes; resetting the layout is unnecessary.
- Application symbolic links are resolved to their actual bundle paths before
  loading icons and launching, so Safari appears without a shortcut arrow.

### Validation

- 195 deterministic core tests passed, including the discovery regression case.
- Production discovery found the installed Safari at `/Applications/Safari.app`.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- 修正 Safari 未出現在啟動器與搜尋中的問題：macOS 可能以帶有隱藏屬性的
  `/Applications/Safari.app` 符號連結提供 Safari，舊版掃描器會略過該連結。
- 更新後重新啟動 OpenLaunchPad 即可重新掃描，不需要重置既有排列。
- 讀取圖示及啟動前先解析符號連結的實際 App 路徑，移除 Safari 圖示的捷徑箭頭。
- 一般隱藏應用程式、隱藏目錄、失效連結與指向隱藏目標的連結仍會被過濾。
