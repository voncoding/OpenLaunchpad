# Changelog

## 1.1.0 — 2026-09-16

### 新增

- 设置中可开关菜单栏图标，记住显示偏好；隐藏后仍可通过程序坞或快捷键打开启动台，再按 ⌘, 打开设置。
- 设置中可选择自动网格或自定义行列数，按当前屏幕限制最大密度，并保留各页空余。
- 应用显示管理：支持搜索、隐藏和恢复；隐藏应用不出现在网格、文件夹预览或搜索中，重新扫描和重启后仍生效。
- 文件夹：悬停合并、重命名、拖出应用，以及文件夹内键盘导航。
- 独立分页：当前页可以保留空余，不从下一页自动补齐；重新打开后仍保留分页，新安装的应用追加到最后一页。
- 图标内存与磁盘缓存，预加载当前页及相邻页图标。

### 优化与修复

- 应用列表复用内存快照，目录变更合并后后台刷新；五分钟后的再次打开才进行兜底检查，避免每次打开都全量扫描。
- 修复文件夹展开期间完成应用扫描后，第一次重新打开启动台仍显示旧应用列表的问题，无需额外扫描即可立即应用更新。
- 图标缓存查询不再访问磁盘；解码与加载在后台合并执行，最多两个并发任务，仅主动加载当前及相邻页面，应用更新时刷新对应图标。
- 文件夹采用宽幅浅灰面板，隐藏滚动条并保留滚动操作；收起后恢复正常图标外观。
- 仅展开文件夹时自动隐藏程序坞和菜单栏，返回主网格时恢复。
- 翻页裁切边界移至屏幕边缘，修复手势在区域外结束或取消时停留半页的问题。
- 区分拖拽排序与悬停合并，支持边缘停留跨页移动及 Escape 取消拖拽。
- 修复搜索结果布局、键盘选择、输入法处理、扫描刷新与拖拽冲突，以及快速开关窗口的状态问题。
- 改进登录启动状态与错误提示；应用启动失败时显示错误。
- 修复“照片”来源壁纸被误读为系统默认壁纸的问题，按当前选中的照片标识读取系统缓存原图，每次打开时重新检查配置。
- 壁纸文件读取与模糊处理移到后台，避免文件访问等待阻塞启动台操作。
- 页数超过九页时使用紧凑页码和前后按钮，避免稀疏网格的分页指示器超出屏幕。

### 验证

- 51 项交互回归检查，包括扫描复用、真实目录事件、异步图标并发、网格设置持久化、应用隐藏与恢复、壁纸来源解析，以及实际 SwiftUI/AppKit 文件夹滚动条和分页视图测试。
- Release 支持 Apple Silicon 与 Intel；安装包使用临时签名，尚未经过 Apple 公证。

### Highlights

- Create, rename, and navigate folders; drag apps out to the main grid.
- Keep independent page layouts with intentional empty space, including across restarts.
- Improve folder presentation, drag intent, keyboard navigation, and full-width page transitions.
- Fix interrupted swipe snapping, scan/drag races, and rapid window visibility changes.
- Resolve selected Photos wallpapers instead of displaying the system default fallback.
- Configure grid dimensions and manage hidden apps without backfilling earlier pages.
- Reuse the app catalog with coalesced filesystem updates and load icons asynchronously through a shared, bounded queue.
- Add 51 isolated interaction regression checks.

## 1.0.0

- 首个版本：全屏启动台、应用搜索、翻页、拖拽排序和登录启动。
