# 启动台 / Launchpad

面向 **macOS Tahoe（macOS 26）** 的原生启动台替代应用。  
系统移除 Launchpad 之后，用这个小工具继续快速打开应用。

A native **Launchpad replacement for macOS Tahoe (macOS 26)**.  
Apple removed Launchpad — this brings a familiar full-screen app grid back.

---

## 功能 Features

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

## 系统要求 Requirements

- macOS 26.0+（Tahoe）
- Apple Silicon 或 Intel（按当前构建目标）

---

## 安装 Install

1. 下载 [Releases](../../releases) 里的 `Launchpad.zip`
2. 解压得到 `Launchpad.app`（显示名：**启动台**）
3. 拖到「应用程序」或 `~/Applications`
4. 首次打开若被拦截：系统设置 → 隐私与安全性 → 仍要打开

From Releases, unzip `Launchpad.app` and move it to Applications. If Gatekeeper blocks it, allow it in System Settings → Privacy & Security.

也可从源码编译：

```bash
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad \
  -configuration Release -derivedDataPath build/DerivedData ONLY_ACTIVE_ARCH=YES
```

产物：`build/DerivedData/Build/Products/Release/Launchpad.app`

---

## 使用 Usage

- **打开**：⌥⌘L、菜单栏网格图标，或点击程序坞图标  
- **关闭**：Esc、点击空白处  
- **搜索**：点击搜索框后再输入（不会自动聚焦）  
- **翻页**：触控板左右滑，或在图标空隙处按住拖动  
- **重排**：在图标上拖动  

---

## 仓库简介（可贴到 GitHub About）

**中文：**  
macOS Tahoe 原生启动台替代：全屏应用网格、拼音搜索、拖拽排序。

**English：**  
Native Launchpad replacement for macOS Tahoe — full-screen app grid, Pinyin search, and drag-to-reorder.

---

## 技术栈 Stack

SwiftUI + AppKit 混合：无边框覆盖层窗口、AppKit 跟手翻页，SwiftUI 负责图标网格与搜索。

SwiftUI + AppKit hybrid: borderless overlay window, AppKit-driven paging, SwiftUI grid & search.

---

## 许可 License

MIT（可按需修改）
