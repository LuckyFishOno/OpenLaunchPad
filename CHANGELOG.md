# Changelog

## 1.1 (build 2) — 2026-11-12

### Fixed

- Safari now appears in the launcher and search when macOS exposes it through
  a hidden symbolic link in `/Applications`. Discovery accepts hidden app links
  to visible application directories while continuing to skip ordinary hidden
  apps, hidden directories, broken links, and links to hidden targets.
- Existing layouts are preserved. Restart OpenLaunchPad after updating so the
  application catalog refreshes; resetting the layout is unnecessary.

### Validation

- 195 deterministic core tests passed, including the discovery regression case.
- Production discovery found the installed Safari at `/Applications/Safari.app`.
- Apple silicon Release build and deep signature verification passed.

### 繁體中文

- 修正 Safari 未出現在啟動器與搜尋中的問題：macOS 可能以帶有隱藏屬性的
  `/Applications/Safari.app` 符號連結提供 Safari，舊版掃描器會略過該連結。
- 更新後重新啟動 OpenLaunchPad 即可重新掃描，不需要重置既有排列。
- 一般隱藏應用程式、隱藏目錄、失效連結與指向隱藏目標的連結仍會被過濾。
