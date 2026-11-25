# Changelog

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
