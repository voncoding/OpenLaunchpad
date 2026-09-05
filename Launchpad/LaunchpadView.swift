import SwiftUI

struct LaunchpadView: View {
    @Bindable var store: LaunchpadStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            wallpaperLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    OverlayController.shared.hide()
                }

            VStack(spacing: 0) {
                SearchPill(query: $store.query)
                    .focused($searchFocused)
                    .padding(.top, store.topInset + 16)
                    .padding(.bottom, 16)
                    .zIndex(2)

                if store.isLoading && store.apps.isEmpty {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Spacer()
                } else if store.filteredApps.isEmpty {
                    Spacer()
                    Text(store.query.isEmpty ? "没有找到应用程序" : "未找到“\(store.query)”")
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

                if store.query.isEmpty && store.pages.count > 1 {
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
        }
        .preferredColorScheme(.dark)
        .containerBackground(.clear, for: .window)
        .scaleEffect(store.isPresented ? 1 : 1.04)
        .animation(.easeOut(duration: 0.2), value: store.isPresented)
        .onChange(of: store.isPresented) { _, presented in
            if !presented {
                searchFocused = false
            }
        }
        .onChange(of: store.query) { _, _ in
            store.selectedID = nil
        }
    }

    @ViewBuilder
    private var wallpaperLayer: some View {
        if let wallpaper = store.wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            Color.black
        }
    }
}

struct SearchPill: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .tint(.white)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 280)
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

struct PagedAppGrid: View {
    @Bindable var store: LaunchpadStore

    var body: some View {
        GeometryReader { geo in
            PagingScrollHost(
                pages: store.pages,
                columns: store.columns,
                rows: store.rows,
                selectedID: store.selectedID,
                isReordering: store.isReordering,
                draggingID: store.draggingApp?.id,
                currentPage: Binding(
                    get: { store.currentPage },
                    set: { store.currentPage = $0 }
                ),
                size: geo.size,
                onLaunch: { OverlayController.shared.launch($0) },
                onReveal: { store.revealInFinder($0) },
                onEmptyTap: {
                    if store.isReordering {
                        store.endDrag()
                    } else {
                        OverlayController.shared.hide()
                    }
                },
                onLift: { app in
                    store.beginDrag(app, pageFrame: geo.size)
                },
                onDrag: { translation in
                    store.updateDrag(translation: translation, pageFrame: geo.size)
                },
                onDrop: {
                    store.endDrag()
                },
                draggingApp: store.draggingApp,
                dragPosition: store.dragPosition
            )
        }
        .padding(.horizontal, 72)
        .animation(
            store.isReordering ? .easeInOut(duration: 0.16) : .snappy(duration: 0.22),
            value: store.apps.map(\.id)
        )
    }
}

struct SearchResultsGrid: View {
    @Bindable var store: LaunchpadStore

    var body: some View {
        ScrollView {
            AppGridPage(
                apps: store.filteredApps,
                columns: store.columns,
                rows: store.rows,
                selectedID: store.selectedID,
                onLaunch: { OverlayController.shared.launch($0) },
                onReveal: { store.revealInFinder($0) },
                onEmptyTap: { OverlayController.shared.hide() },
                fillsPage: false,
                draggingID: nil
            )
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 72)
    }
}

struct AppGridPage: View {
    let apps: [InstalledApp]
    let columns: Int
    var rows: Int = 5
    let selectedID: URL?
    let onLaunch: (InstalledApp) -> Void
    let onReveal: (InstalledApp) -> Void
    var onEmptyTap: (() -> Void)?
    var fillsPage: Bool = true
    var draggingID: URL?
    var onLift: ((InstalledApp) -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDrop: (() -> Void)?

    var body: some View {
        let columnCount = max(columns, 1)
        let rowCount = fillsPage ? max(rows, 1) : max((apps.count + columnCount - 1) / columnCount, 1)

        ZStack {
            // Search results still need empty taps; paged mode uses the AppKit gap catcher.
            if !fillsPage {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEmptyTap?()
                    }
            }

            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let index = row * columnCount + column
                            iconCell(at: index)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil, alignment: .top)
    }

    private func iconCell(at index: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil)
            .overlay {
                if index < apps.count {
                    AppIconCell(
                        app: apps[index],
                        isSelected: apps[index].id == selectedID,
                        isPlaceholder: apps[index].id == draggingID,
                        onLaunch: { onLaunch(apps[index]) },
                        onReveal: { onReveal(apps[index]) },
                        onLift: onLift == nil ? nil : { onLift?(apps[index]) },
                        onDrag: onDrag,
                        onDrop: onDrop
                    )
                }
            }
    }
}

struct AppIconCell: View {
    let app: InstalledApp
    let isSelected: Bool
    var isPlaceholder: Bool = false
    var isFloating: Bool = false
    let onLaunch: () -> Void
    let onReveal: () -> Void
    var onLift: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onDrop: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: IconCache.image(for: app.url))
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: LaunchpadMetrics.iconSize, height: LaunchpadMetrics.iconSize)
                .shadow(color: .black.opacity(isFloating ? 0.45 : 0.32), radius: isFloating || hovering || isSelected ? 18 : 10, y: 6)
                .scaleEffect(isFloating ? 1.12 : (hovering || isSelected ? 1.06 : 1))
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
        .background {
            if isSelected && !isFloating && !isPlaceholder {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .padding(-10)
                    .allowsHitTesting(false)
            }
        }
        .opacity(isPlaceholder ? 0.28 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .allowsHitTesting(!isFloating)
    }
}

private struct IconPressModifier: ViewModifier {
    let enabled: Bool
    let onLift: () -> Void
    let onDrag: (CGSize) -> Void
    let onDrop: () -> Void

    @State private var lifted = false

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(dragGesture)
        } else {
            content
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { drag in
                if !lifted {
                    lifted = true
                    onLift()
                }
                onDrag(drag.translation)
            }
            .onEnded { _ in
                if lifted {
                    onDrop()
                }
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
            ForEach(0..<max(count, 1), id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(.white.opacity(index == current ? 0.95 : 0.35))
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview {
    LaunchpadView(store: LaunchpadStore())
        .frame(width: 1200, height: 800)
}
