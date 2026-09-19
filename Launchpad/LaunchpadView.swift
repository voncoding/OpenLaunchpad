import SwiftUI

struct LaunchpadView: View {
    @Bindable var store: LaunchpadStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            wallpaperLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.black.opacity(store.openFolderID == nil ? 0.22 : 0.52)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if store.openFolderID != nil {
                        store.closeFolder()
                    } else {
                        OverlayController.shared.hide()
                    }
                }

            // Hide the whole icon board while a folder is open (wallpaper + folder only).
            if store.openFolderID == nil {
                VStack(spacing: 0) {
                    SearchPill(query: $store.query)
                        .focused($searchFocused)
                        .padding(.top, store.topInset + 16)
                        .padding(.bottom, 16)
                        .zIndex(2)
                        .overlay(alignment: .bottom) {
                            if store.wallpaperStatus.needsAttention {
                                SettingsLink {
                                    Label("壁纸未能读取 · 打开设置", systemImage: "photo.badge.exclamationmark")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white.opacity(0.85))
                                .offset(y: 2)
                            }
                        }

                    if store.isLoading && store.appsIsEmpty {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                        Spacer()
                    } else if store.displayItems.isEmpty {
                        Spacer()
                        Text(store.query.isEmpty ? (store.hiddenAppCount > 0 ? "应用已隐藏，可按 ⌘, 在设置中恢复" : "没有找到应用程序") : "未找到“\(store.query)”")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                        Spacer()
                    } else if store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PagedAppGrid(store: store)
                            .zIndex(1)
                    } else {
                        SearchResultsGrid(store: store)
                            .zIndex(1)
                    }

                    if store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.pages.count > 1 {
                        PageIndicator(
                            count: store.pages.count,
                            current: store.currentPage
                        ) { page in
                            store.goToPage(page)
                        }
                        .padding(.bottom, store.bottomInset)
                    } else {
                        Color.clear.frame(height: store.bottomInset)
                    }
                }
                .transition(.opacity)
            }

            if store.openFolderID != nil {
                FolderOverlay(store: store)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.22), value: store.openFolderID)
        .preferredColorScheme(.dark)
        .containerBackground(.clear, for: .window)
        .scaleEffect(store.isPresented ? 1 : 1.04)
        .animation(.easeOut(duration: 0.2), value: store.isPresented)
        .onChange(of: store.isPresented) { _, presented in
            if !presented {
                searchFocused = false
                store.closeFolder()
            }
        }
        .onChange(of: store.query) { _, _ in
            store.closeFolder()
        }
        .onChange(of: store.openFolderID) { _, _ in
            OverlayController.shared.updateFolderPresentation()
        }
    }

    @ViewBuilder
    private var wallpaperLayer: some View {
        if let wallpaper = store.wallpaper {
            GeometryReader { geo in
                Image(nsImage: wallpaper)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct SearchPill: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .tint(.white.opacity(0.7))
                .accessibilityLabel("搜索应用程序")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 280)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

struct PagedAppGrid: View {
    @Bindable var store: LaunchpadStore

    var body: some View {
        GeometryReader { geo in
            let gridFrame = CGSize(width: max(geo.size.width - 2 * store.horizontalInset, 1), height: geo.size.height)
            ZStack(alignment: .topLeading) {
                PagingScrollHost(
                    store: store,
                    pageFrame: geo.size,
                    horizontalInset: store.horizontalInset,
                    onLaunch: { OverlayController.shared.launch($0) },
                    onReveal: { store.revealInFinder($0) },
                    onOpenFolder: { store.openFolder($0) },
                    onEmptyTap: {
                        if store.isReordering {
                            store.endDrag()
                        } else {
                            OverlayController.shared.hide()
                        }
                    }
                )

                // Floating icon outside AppKit pager — position updates must not rebuild the grid.
                if let draggingItem = store.draggingItem,
                   let dragPosition = store.dragPosition,
                   store.dragSourceIsFolder == false {
                    let pageOffset = CGFloat(store.currentPage) * gridFrame.width
                    let local = CGPoint(x: dragPosition.x - pageOffset + store.horizontalInset, y: dragPosition.y)
                    Group {
                        switch draggingItem {
                        case .app(let app):
                            AppIconCell(
                                app: app,
                                isSelected: false,
                                isFloating: true,
                                onLaunch: {},
                                onReveal: {}
                            )
                        case .folder(let folder):
                            FolderIconCell(
                                folder: folder,
                                apps: store.apps(in: folder),
                                isFloating: true
                            )
                        }
                    }
                    .position(local)
                    .allowsHitTesting(false)
                }
            }
        }
        .animation(
            store.mergeTargetID != nil || store.isReordering
                ? nil
                : .snappy(duration: 0.22),
            value: store.items.map(\.id)
        )
    }
}

struct SearchResultsGrid: View {
    @Bindable var store: LaunchpadStore

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 1).id("search-top")
                    ItemGridPage(
                        items: store.displayItems,
                        columns: store.columns,
                        rows: store.rows,
                        selectedID: store.selectedID,
                        onLaunch: { OverlayController.shared.launch($0) },
                        onReveal: { store.revealInFinder($0) },
                        onOpenFolder: { store.openFolder($0) },
                        onEmptyTap: { OverlayController.shared.hide() },
                        fillsPage: false,
                        draggingID: nil,
                        mergeTargetID: nil,
                        resolveFolderApps: { store.apps(in: $0) }
                    )
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .task {
                await Task.yield()
                if let selectedID = store.selectedID { scroll.scrollTo(selectedID) }
            }
            .onChange(of: store.selectedID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    scroll.scrollTo(selectedID)
                }
            }
            .onChange(of: store.query) { _, _ in
                scroll.scrollTo("search-top", anchor: .top)
            }
        }
        .padding(.horizontal, store.horizontalInset)
    }
}

struct ItemGridPage: View {
    let items: [LaunchpadItem]
    let columns: Int
    var rows: Int = 5
    let selectedID: String?
    let onLaunch: (InstalledApp) -> Void
    let onReveal: (InstalledApp) -> Void
    let onOpenFolder: (LaunchpadFolder) -> Void
    var onEmptyTap: (() -> Void)?
    var fillsPage: Bool = true
    var draggingID: String?
    var mergeTargetID: String?
    var onLift: ((LaunchpadItem) -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDrop: (() -> Void)?
    var resolveFolderApps: ((LaunchpadFolder) -> [InstalledApp])?

    var body: some View {
        let columnCount = max(columns, 1)
        if fillsPage {
            VStack(spacing: 0) {
                ForEach(0..<max(rows, 1), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let index = row * columnCount + column
                            iconCell(at: index)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount),
                spacing: 0
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    iconCell(at: index)
                        .frame(height: LaunchpadMetrics.cellHeight)
                        .id(item.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onEmptyTap?() }
            }
        }
    }

    @ViewBuilder
    private func iconCell(at index: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if index < items.count {
                    let item = items[index]
                    switch item {
                    case .app(let app):
                        AppIconCell(
                            app: app,
                            isSelected: item.id == selectedID,
                            isPlaceholder: item.id == draggingID,
                            hideWhileMerging: mergeTargetID != nil && item.id == draggingID,
                            isMergeTarget: item.id == mergeTargetID,
                            onLaunch: { onLaunch(app) },
                            onReveal: { onReveal(app) },
                            onLift: onLift == nil ? nil : { onLift?(item) },
                            onDrag: onDrag,
                            onDrop: onDrop
                        )
                    case .folder(let folder):
                        FolderIconCell(
                            folder: folder,
                            apps: resolveFolderApps?(folder) ?? [],
                            isSelected: item.id == selectedID,
                            isPlaceholder: item.id == draggingID,
                            hideWhileMerging: mergeTargetID != nil && item.id == draggingID,
                            isMergeTarget: item.id == mergeTargetID,
                            onOpen: { onOpenFolder(folder) },
                            onLift: onLift == nil ? nil : { onLift?(item) },
                            onDrag: onDrag,
                            onDrop: onDrop
                        )
                    }
                }
            }
    }
}

struct FolderIconCell: View {
    let folder: LaunchpadFolder
    let apps: [InstalledApp]
    var isSelected: Bool = false
    var isPlaceholder: Bool = false
    var hideWhileMerging: Bool = false
    var isFloating: Bool = false
    var isMergeTarget: Bool = false
    var onOpen: (() -> Void)?
    var onLift: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDrop: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.16))
                    .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)

                let preview = Array(apps.prefix(4))
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(preview, id: \.id) { app in
                        AppIconImage(app: app)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(14)
                .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
            }
            .overlay {
                if (isSelected || isMergeTarget) && !isPlaceholder && !isFloating {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(isMergeTarget ? 0.75 : 0.45), lineWidth: isMergeTarget ? 2 : 1.5)
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: .black.opacity(isFloating ? 0.45 : 0.32),
                radius: isFloating || hovering || isSelected || isMergeTarget ? 18 : 10,
                y: 6
            )
            .scaleEffect(
                isFloating ? 1.12 : (isMergeTarget ? 1.14 : (hovering || isSelected ? 1.06 : 1))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .modifier(
                IconPressModifier(
                    enabled: onLift != nil && !isFloating,
                    onLift: { onLift?() },
                    onDrag: { onDrag?($0) },
                    onDrop: { onDrop?() }
                )
            )
            .onTapGesture {
                guard !isFloating else { return }
                onOpen?()
            }

            Text(folder.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.labelHeight, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconBlockHeight)
        .fixedSize()
        .opacity(hideWhileMerging ? 0 : (isPlaceholder ? 0.22 : 1))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isMergeTarget)
        .allowsHitTesting(!isFloating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(folder.name)，文件夹，\(apps.count) 个应用程序")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen?() }
        .accessibilityHidden(isFloating)
    }
}

struct AppIconCell: View {
    let app: InstalledApp
    let isSelected: Bool
    var isPlaceholder: Bool = false
    var hideWhileMerging: Bool = false
    var isFloating: Bool = false
    var isMergeTarget: Bool = false
    var isInFolder: Bool = false
    var labelWidth: CGFloat = LaunchpadMetrics.iconSize
    let onLaunch: () -> Void
    let onReveal: () -> Void
    var onLift: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDrop: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: isInFolder ? 6 : 8) {
            AppIconImage(app: app)
                .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
                .shadow(
                    color: .black.opacity(isFloating ? 0.35 : (isInFolder ? 0.12 : 0.32)),
                    radius: isFloating ? 14 : (isInFolder ? 3 : 10),
                    y: isInFolder ? 2 : 6
                )
                .scaleEffect(isFloating ? 1.12 : (isMergeTarget ? 1.14 : (hovering || isSelected ? 1.06 : 1)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .modifier(
                    IconPressModifier(
                        enabled: onLift != nil && !isFloating,
                        onLift: { onLift?() },
                        onDrag: { onDrag?($0) },
                        onDrop: { onDrop?() }
                    )
                )
                .onTapGesture {
                    guard !isFloating else { return }
                    onLaunch()
                }
                .contextMenu {
                    Button("打开", action: onLaunch)
                    Button("在 Finder 中显示", action: onReveal)
                }

            Text(app.name)
                .font(.system(size: 13, weight: isInFolder ? .regular : .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(isInFolder ? 0.16 : 0.75), radius: isInFolder ? 1 : 3, y: 1)
                .lineLimit(isInFolder ? 1 : 2)
                .multilineTextAlignment(.center)
                .frame(width: labelWidth, height: isInFolder ? 20 : LaunchpadMetrics.labelHeight, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(width: labelWidth, height: isInFolder ? LaunchpadMetrics.iconSize + 26 : LaunchpadMetrics.iconBlockHeight)
        .fixedSize()
        .background {
            if (isSelected || isMergeTarget) && !isFloating && !isPlaceholder {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(isMergeTarget ? 0.22 : 0.12))
                    .padding(-10)
                    .allowsHitTesting(false)
            }
        }
        .opacity(hideWhileMerging ? 0 : (isPlaceholder ? 0.22 : 1))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isMergeTarget)
        .allowsHitTesting(!isFloating)
        .accessibilityElement(children: .ignore)
        .help(app.name)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onLaunch() }
        .accessibilityAction(named: Text("在 Finder 中显示")) { onReveal() }
        .accessibilityHidden(isFloating)
    }
}

struct FolderOverlay: View {
    @Bindable var store: LaunchpadStore
    @FocusState private var nameFocused: Bool

    private let panelCorner: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let apps = store.openFolderApps
            let expanded = store.isFolderExpanded
            // Keep the native wide folder silhouette; distribute columns across it.
            let panelWidth = min(max(1, geo.size.width - 32), max(280, geo.size.width * 0.83))
            let hPad = max(16, min(28, panelWidth * 0.016))
            let columnCount = max(1, min(7, Int((panelWidth - hPad * 2) / 132)))
            let columnWidth = max(1, (panelWidth - hPad * 2) / CGFloat(columnCount))
            let labelWidth = max(LaunchpadMetrics.iconSize, columnWidth - 12)
            let vPad = min(40, max(22, geo.size.height * 0.037))
            let rowCount = max(1, (apps.count + columnCount - 1) / columnCount)
            let maxPanelHeight = max(1, min(geo.size.height * 0.663, geo.size.height - 144))
            let rowHeight = max(132, min(180, (maxPanelHeight - vPad * 2) / 4))
            let panelHeight = min(maxPanelHeight, CGFloat(min(rowCount, 4)) * rowHeight + vPad * 2)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { store.closeFolder() }

                VStack(spacing: 18) {
                    TextField("文件夹", text: $store.folderNameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .light))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        .focused($nameFocused)
                        .onSubmit {
                            store.commitOpenFolderName()
                            nameFocused = false
                        }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { store.commitOpenFolderName() }
                        }
                        .frame(width: min(panelWidth - 32, 480), height: 36)
                        .accessibilityLabel("文件夹名称")

                    ScrollViewReader { scroll in
                        ScrollView(.vertical) {
                            LazyVGrid(
                                columns: Array(
                                    repeating: GridItem(.flexible(minimum: 0), spacing: 0),
                                    count: columnCount
                                ),
                                alignment: .leading,
                                spacing: 0
                            ) {
                                ForEach(apps, id: \.id) { app in
                                    FolderAppCell(store: store, app: app, overlaySize: geo.size, labelWidth: labelWidth)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: rowHeight)
                                        .id(LaunchpadItem.app(app).id)
                                }
                            }
                            .padding(.horizontal, hPad)
                        }
                        .scrollDisabled(store.dragSourceIsFolder)
                        // Also suppress legacy scrollers when macOS is set to Always.
                        .scrollIndicators(.never)
                        .frame(width: panelWidth, height: max(1, panelHeight - vPad * 2))
                        .overlay {
                            if apps.isEmpty {
                                Text("此文件夹中的应用已隐藏，可在设置中恢复。")
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding()
                            }
                        }
                        .padding(.vertical, vPad)
                        .onChange(of: store.selectedID) { _, selectedID in
                            guard let selectedID else { return }
                            withAnimation(.easeOut(duration: 0.16)) {
                                scroll.scrollTo(selectedID)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: panelCorner))
                    .contentShape(RoundedRectangle(cornerRadius: panelCorner))
                    .onTapGesture { nameFocused = false }
                    .background {
                        // Wallpaper is already blurred. A neutral translucent surface
                        // reproduces the original Launchpad frost without glass highlights.
                        RoundedRectangle(cornerRadius: panelCorner, style: .continuous)
                            .fill(Color(white: 0.65).opacity(0.82))
                            .allowsHitTesting(false)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("folderOverlay"))
                    } action: { frame in
                        store.folderPanelFrame = frame
                    }
                }
                .scaleEffect(expanded ? 1 : 0.88, anchor: .center)
                .opacity(expanded ? 1 : 0)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.465)

                if case .app(let app) = store.draggingItem,
                   store.dragSourceIsFolder,
                   let pos = store.dragPosition {
                    AppIconCell(
                        app: app,
                        isSelected: false,
                        isFloating: true,
                        isInFolder: true,
                        labelWidth: labelWidth,
                        onLaunch: {},
                        onReveal: {}
                    )
                    .position(pos)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "folderOverlay")
            .onAppear { store.folderColumns = columnCount }
            .onChange(of: columnCount) { _, count in store.folderColumns = count }
            .onDisappear { store.folderPanelFrame = .zero }
        }
    }
}

/// Keep the drag origin in the same space as the floating icon, including scroll offset.
private struct FolderAppCell: View {
    @Bindable var store: LaunchpadStore
    let app: InstalledApp
    let overlaySize: CGSize
    let labelWidth: CGFloat

    @State private var frameInOverlay: CGRect = .zero

    var body: some View {
        let itemID = LaunchpadItem.app(app).id
        AppIconCell(
            app: app,
            isSelected: store.selectedID == itemID,
            isPlaceholder: store.draggingItem?.id == itemID && store.dragSourceIsFolder,
            isInFolder: true,
            labelWidth: labelWidth,
            onLaunch: { OverlayController.shared.launch(app) },
            onReveal: { store.revealInFinder(app) },
            onLift: {
                guard let folderID = store.openFolderID, !frameInOverlay.isEmpty else { return }
                store.beginFolderDrag(
                    app,
                    folderID: folderID,
                    startInOverlay: CGPoint(x: frameInOverlay.midX, y: frameInOverlay.midY)
                )
            },
            onDrag: { translation in
                store.updateDrag(translation: translation, pageFrame: overlaySize)
            },
            onDrop: { store.endFolderDrag() }
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("folderOverlay"))
        } action: { frame in
            frameInOverlay = frame
        }
    }
}

private struct IconPressModifier: ViewModifier {
    let enabled: Bool
    let onLift: () -> Void
    let onDrag: (CGSize) -> Void
    let onDrop: () -> Void

    @State private var lifted = false
    @GestureState private var gestureActive = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .gesture(dragGesture)
                .onChange(of: gestureActive) { _, active in
                    if !active { lifted = false }
                }
                .onDisappear { lifted = false }
        } else {
            content
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { drag in
                if !lifted {
                    lifted = true
                    onLift()
                }
                onDrag(drag.translation)
            }
            .onEnded { drag in
                onDrag(drag.translation)
                onDrop()
                lifted = false
            }
    }
}

struct PageIndicator: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if count > 9 {
                Button { onSelect(current - 1) } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 18)
                }
                .disabled(current <= 0)
                .accessibilityLabel("上一页")
                Text("\(current + 1) / \(count)")
                    .monospacedDigit()
                    .accessibilityLabel("第 \(current + 1) 页，共 \(count) 页")
                Button { onSelect(current + 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 24, height: 18)
                }
                .disabled(current >= count - 1)
                .accessibilityLabel("下一页")
            } else {
              ForEach(0..<max(count, 1), id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(.white.opacity(index == current ? 0.95 : 0.35))
                        .frame(width: 7, height: 7)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 页，共 \(count) 页")
                .accessibilityValue(index == current ? "当前页" : "")
                .help("第 \(index + 1) 页")
              }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

#if DEBUG
#Preview {
    LaunchpadView(store: LaunchpadStore())
        .frame(width: 1200, height: 800)
}
#endif
