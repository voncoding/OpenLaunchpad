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

本次更新 **v1.1.1**：改进 macOS 27 壁纸读取失败的诊断、重试与权限设置指引，减少不必要的壁纸缓存访问。详见 [更新日志 / Changelog](CHANGELOG.md)。

---

## Why OpenLaunchpad

- macOS Tahoe removed Launchpad — this brings it back as a lightweight native app
- Blurred desktop wallpaper overlay (Dock & menu bar auto-hide only inside a folder)
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
| 快捷键 ⌥⌘L，菜单栏图标可隐藏 | Hotkey ⌥⌘L; optional menu bar icon |
| 文件夹、独立分页、自定义网格 | Folders, independent pages, and configurable grid dimensions |
| 隐藏或恢复应用，保留布局与设置 | Hide and restore apps while preserving layout and preferences |
| 后台刷新列表、异步加载图标 | Background catalog refresh and asynchronous icon loading |
| 支持登录时启动 | Optional launch at login |

---

## Requirements 系统要求

- macOS 26.0+（Tahoe）
- Apple Silicon or Intel（同一个通用安装包 / universal binary）

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
- **Menu bar icon**：Settings → 显示菜单栏图标; after hiding it, open the launcher from the Dock or with ⌥⌘L, then press ⌘, to reopen Settings
- **Search**：click the search field first (no auto-focus)  
- **Page**：trackpad swipe, or drag on gaps between icons  
- **Reorder**：drag an icon to a new position and release; hold near a page edge to move between pages
- **Folders**：pause over the center of another icon until it highlights, then release to create or join a folder
- **Move out of a folder**：drag an app outside the folder panel and release; it returns beside the folder
- **Keyboard**：arrow keys select apps; Return opens the selection, including folders; Escape cancels a drag before closing the folder or launcher

拖放即可排序；在目标图标中心稍作停留、出现高亮后松手，可创建文件夹或放入已有文件夹。拖到页面边缘稍停可跨页移动，按 Escape 可取消。文件夹内应用较多时可以滚动，拖出面板可移回主网格。

每页独立保存：移走图标、合并文件夹或卸载应用后，当前页底部可以留空，不会从下一页自动补齐；重新打开后仍保留分页。新安装的应用添加到最后一页。

文件夹采用接近原生启动台的宽幅浅灰面板，最多显示四行，更多应用可滚动查看，滚动条隐藏。仅展开文件夹时，程序坞和菜单栏会自动隐藏；回到主网格后恢复。

打开启动台后按 **⌘,** 进入设置，可关闭菜单栏图标。在“网格”中关闭“自动适配屏幕”即可调整行列数；上限随屏幕大小变化。减少容量会拆分页，增加容量不会把下一页的应用补到前页。

“应用显示 → 管理应用…”支持按名称、拼音或首字母查找应用，关闭开关即可隐藏，切换到“已隐藏”可随时恢复。隐藏同时作用于主网格、文件夹预览和搜索，不会卸载应用。恢复后，文件夹内应用仍在原文件夹，独立应用追加到最后一页；隐藏偏好在重启和重新扫描后保留。

反复打开启动台会复用已有应用列表；安装、卸载和更新应用时自动在后台刷新，并在五分钟后的再次打开时兜底检查。图标采用异步加载与请求合并，界面只直接查询内存缓存，当前页及相邻页优先加载。

每次打开时重新读取当前壁纸，并做模糊、压暗处理。支持读取“照片”来源壁纸对应的系统缓存原图，避免错误显示系统默认壁纸。

**macOS 27 壁纸不显示：** 打开启动台设置查看“壁纸”状态。若提示权限不足，可在“系统设置 → 隐私与安全性 → 完整磁盘访问”中添加当前安装的 **启动台 / OpenLaunchpad**，再退出并重新打开。此权限覆盖范围大于壁纸目录；也可以在系统壁纸设置中改用本地图片文件，然后点“重新读取壁纸”。安装包使用临时签名，更新替换后可能需要重新添加授权。

**Wallpaper access on macOS 27:** Some Photos wallpapers use protected system caches. Settings now explains a failed read and offers retry and privacy settings. Following these wallpapers may require granting the installed OpenLaunchpad app Full Disk Access, then quitting and reopening it. This permission covers more than wallpaper files; using a local image in macOS Wallpaper settings is an alternative. Ad-hoc signed updates may require granting access again.

开发时运行 `./scripts/test-interactions.sh` 可检查拖拽、文件夹、搜索选择、页码恢复和扫描刷新等关键交互。测试使用隔离的数据，不会启动其他应用或改动现有排序。

---

## Stack 技术栈

SwiftUI + AppKit hybrid: borderless overlay window, AppKit-driven paging, SwiftUI grid & search.

---

## FAQ

**Is this the official Apple Launchpad?**  
No. It is an independent open-source alternative for macOS Tahoe.

**Can I use a custom domain?**  
The [product website](https://appledev.app/) runs on GitHub Pages. See the [website maintenance and domain guide](https://github.com/voncoding/OpenLaunchpad/blob/codex/website/WEBSITE.md) for details.

**Gatekeeper warning?**  
Unsigned / ad-hoc signed builds may need “Open Anyway” in Privacy & Security.

---

## License

MIT
