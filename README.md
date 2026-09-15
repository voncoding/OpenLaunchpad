# OpenLaunchpad

**macOS Tahoe Launchpad alternative / macOS 26 启动台替代**

<p align="center">
  <img src="docs/logo.png" width="160" height="160" alt="OpenLaunchpad — macOS Tahoe Launchpad alternative app icon">
</p>

<p align="center">
  <a href="https://github.com/voncoding/OpenLaunchpad/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/voncoding/OpenLaunchpad?label=Download&color=0A84FF"></a>
  <a href="https://github.com/voncoding/OpenLaunchpad/releases"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2026%2B-black"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-green"></a>
</p>

OpenLaunchpad is a **native Launchpad replacement for macOS Tahoe (macOS 26)** after Apple removed the system Launchpad.  
It restores a familiar full-screen app launcher with search, paging, and drag-to-reorder.

**OpenLaunchpad** 是面向 **macOS Tahoe（macOS 26）** 的原生启动台替代应用：全屏应用网格、拼音搜索、翻页与拖拽排序。

[官网 Website](https://appledev.app/) · [Download latest release](https://github.com/voncoding/OpenLaunchpad/releases/latest) · [中文说明](#install-安装)

---

## Why OpenLaunchpad

- macOS Tahoe removed Launchpad — this brings it back as a lightweight native app
- Blurred desktop wallpaper overlay (Dock & menu bar stay on top)
- Chinese name / Pinyin / initials search
- Trackpad paging + mouse drag on empty space
- Icon reorder with remembered page

适合关键词检索：`Launchpad alternative`、`macOS Tahoe Launchpad`、`macOS 26 启动台`、`Launchpad replacement`、`open source Launchpad`。

---

## Features 功能

| 中文 | English |
|------|---------|
| 全屏网格，模糊当前桌面壁纸 | Full-screen grid over a blurred desktop wallpaper |
| 扫描 `/Applications`、系统与用户应用 | Scans `/Applications`, system, and user app folders |
| 中文名 / 拼音 / 首字母搜索 | Search by Chinese name, Pinyin, or initials |
| 触控板两指翻页；空白处鼠标拖动翻页 | Trackpad two-finger paging; drag empty space with the mouse |
| 拖拽图标重排，顺序会记住 | Drag icons to reorder; order is persisted |
| 记住上次停留的页 | Remembers the last page you were on |
| 快捷键 ⌥⌘L，菜单栏常驻 | Hotkey ⌥⌘L; lives in the menu bar |
| 支持登录时启动 | Optional launch at login |

---

## Requirements 系统要求

- macOS 26.0+（Tahoe）
- Apple Silicon or Intel

---

## Install 安装

1. Open the [latest Release](https://github.com/voncoding/OpenLaunchpad/releases/latest)
2. Download `OpenLaunchpad.zip` and unzip
3. Move `OpenLaunchpad.app` (display name: **启动台**) to Applications or `~/Applications`
4. If macOS blocks it: System Settings → Privacy & Security → Open Anyway

```bash
# Build from source
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad \
  -configuration Release -derivedDataPath build/DerivedData ONLY_ACTIVE_ARCH=YES
# Output: build/DerivedData/Build/Products/Release/OpenLaunchpad.app
```

---

## Usage 使用

- **Open**：⌥⌘L, menu bar grid icon, or Dock icon  
- **Close**：Esc, or click empty space  
- **Search**：click the search field first (no auto-focus)  
- **Page**：trackpad swipe, or drag on gaps between icons  
- **Reorder**：drag icons  

---

## Stack 技术栈

SwiftUI + AppKit hybrid: borderless overlay window, AppKit-driven paging, SwiftUI grid & search.

---

## FAQ

**Is this the official Apple Launchpad?**  
No. It is an independent open-source alternative for macOS Tahoe.

**Can I use a custom domain?**  
The [product website](https://appledev.app/) runs on **GitHub Pages**, published from `codex/website` → `/docs`. See [website maintenance and custom domain setup](WEBSITE.md) for publishing and DNS instructions.

**Gatekeeper warning?**  
Unsigned / ad-hoc signed builds may need “Open Anyway” in Privacy & Security.

---

## License

MIT
