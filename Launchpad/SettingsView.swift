import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(LaunchpadStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("launchpad.showMenuBarIcon") private var showMenuBarIcon = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var managesApps = false

    var body: some View {
        Form {
            Section("快捷键") {
                LabeledContent("打开启动台") {
                    Text("⌥⌘L")
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("也可以点击程序坞图标、菜单栏网格图标，或在键盘上按 Escape 关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
                Text("隐藏后仍可通过程序坞或 ⌥⌘L 打开启动台，再按 ⌘, 进入设置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("网格") {
                Toggle("自动适配屏幕", isOn: Binding(
                    get: { store.usesAutomaticGrid }, set: { store.setAutomaticGrid($0) }
                ))
                if !store.usesAutomaticGrid {
                    Stepper("列数：\(store.columns)", value: Binding(
                        get: { min(store.preferredColumns, store.maximumColumns) },
                        set: { store.setGridColumns($0) }
                    ), in: 1...store.maximumColumns)
                    Stepper("行数：\(store.rows)", value: Binding(
                        get: { min(store.preferredRows, store.maximumRows) },
                        set: { store.setGridRows($0) }
                    ), in: 1...store.maximumRows)
                }
                LabeledContent("当前布局", value: "\(store.columns) 列 × \(store.rows) 行")
                Text("行列上限随屏幕大小调整。减少容量时会拆分页，增加容量时保留各页空余。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("壁纸") {
                Text(store.wallpaperStatus.description)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("重新读取壁纸") { OverlayController.shared.retryWallpaper() }
                        .disabled(store.wallpaperStatus == .loading)
                    if store.wallpaperStatus == .accessDenied {
                        Button("打开隐私设置…") {
                            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if store.wallpaperStatus == .accessDenied {
                    Text("完整磁盘访问的范围大于壁纸目录。也可以在系统壁纸设置中改用本地图片文件，然后重新读取。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("在访达中显示启动台") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }

            Section("应用显示") {
                HStack {
                    Text("已显示 \(store.appCatalog.count - store.hiddenAppCount) 个 · 已隐藏 \(store.hiddenAppCount) 个")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("管理应用…") { managesApps = true }
                }
                Text("选择哪些应用出现在启动台和搜索中，可随时恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("启动") {
                Toggle("登录时启动启动台", isOn: loginBinding)
                Text("登录后在后台运行，不会自动弹出网格。点击程序坞图标或按 ⌥⌘L 即可打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if loginStatus == .requiresApproval {
                    Text("还需要在系统设置中允许登录时启动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section("关于") {
                LabeledContent("应用数") {
                    Text("\(store.appCatalog.count)")
                }
                Text("扫描 /Applications、系统应用和用户应用文件夹。支持中文名、拼音和首字母搜索。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .sheet(isPresented: $managesApps) { AppVisibilitySettings(store: store) }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            OverlayController.shared.hide()
            OverlayController.shared.retryWallpaper()
            if let screen = NSScreen.main {
                let dockHeight = max(screen.visibleFrame.minY - screen.frame.minY, 0)
                let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 0)
                store.updateLayout(for: screen.frame.size, topInset: menuHeight + 8, bottomInset: dockHeight + 36)
            }
            store.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                loginStatus = SMAppService.mainApp.status
            }
        }
        .alert("无法更改登录启动", isPresented: Binding(
            get: { loginError != nil },
            set: { if !$0 { loginError = nil } }
        )) {
            Button("好", role: .cancel) { loginError = nil }
        } message: {
            Text(loginError ?? "")
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginStatus = SMAppService.mainApp.status
                } catch {
                    loginStatus = SMAppService.mainApp.status
                    loginError = error.localizedDescription
                }
            }
        )
    }
}

private struct AppVisibilitySettings: View {
    @Bindable var store: LaunchpadStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var onlyHidden = false

    private var filteredApps: [InstalledApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.appCatalog.values.filter {
            (!onlyHidden || store.hiddenAppPaths.contains($0.url.path)) && (trimmed.isEmpty || $0.matches(trimmed))
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.url.path < $1.url.path : comparison == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("应用显示与隐藏").font(.title2.bold())
            Text("关闭开关即可隐藏应用，不会卸载。恢复时，文件夹内应用回到原文件夹，独立应用追加到最后一页。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("搜索应用名称、拼音或首字母", text: $query)
                .textFieldStyle(.roundedBorder)
            Picker("筛选应用", selection: $onlyHidden) {
                Text("全部应用（\(store.appCatalog.count)）").tag(false)
                Text("已隐藏（\(store.hiddenAppCount)）").tag(true)
            }
            .pickerStyle(.segmented)
            List(filteredApps) { app in
                Toggle(isOn: Binding(
                    get: { !store.hiddenAppPaths.contains(app.url.path) },
                    set: { store.setAppVisible($0, path: app.url.path) }
                )) {
                    HStack(spacing: 10) {
                        AppIconImage(app: app)
                            .frame(width: 32, height: 32)
                        Text(app.name).lineLimit(1)
                    }
                }
                .toggleStyle(.switch)
                .help(app.url.path)
                .accessibilityLabel("显示 \(app.name)")
            }
            .overlay {
                if filteredApps.isEmpty {
                    Text(store.isLoading ? "正在扫描应用…" : (query.isEmpty ? (onlyHidden ? "没有隐藏的应用" : "没有找到应用") : "没有匹配的应用"))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("开启：显示　关闭：隐藏").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
    }
}
