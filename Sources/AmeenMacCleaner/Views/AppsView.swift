import SwiftUI

enum AppSort: String, CaseIterable, Identifiable {
    case size = "Size", name = "Name", lastUsed = "Last Opened"
    var id: String { rawValue }
}

enum AppFilter: String, CaseIterable, Identifiable {
    case all = "All", large = "Large", unused = "Unused", appStore = "App Store", menuBar = "Menu Bar", hidden = "Hidden"
    var id: String { rawValue }
}

struct AppsView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var sort: AppSort = .size
    @State private var filter: AppFilter = .all
    @State private var selection: Set<String> = []

    private var filtered: [AppItem] {
        var list = state.visibleApps
        switch filter {
        case .all: break
        case .large: list = list.filter { $0.totalSize >= 500_000_000 }
        case .unused:
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            list = list.filter { !$0.isProtected && ($0.lastUsed ?? .distantPast) < cutoff }
        case .appStore: list = list.filter(\.isAppStore)
        case .menuBar: list = list.filter(\.isAgent)
        case .hidden: list = list.filter(\.isHidden)
        }
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(search)
            }
        }
        switch sort {
        case .size: list.sort { $0.totalSize > $1.totalSize }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    var body: some View {
        let list = filtered
        let maxSize = Double(list.map(\.totalSize).max() ?? 1)
        HSplitView {
            VStack(spacing: 0) {
                listHeader(list)
                List(list, selection: $selection) { app in
                    AppRow(app: app, maxSize: maxSize).tag(app.id)
                }
                .listStyle(.inset)
                .overlay {
                    if list.isEmpty && !state.isScanningApps {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .frame(minWidth: 360, idealWidth: 420, maxWidth: 560)

            detail
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
        .onChange(of: state.showHidden) { _, show in
            if !show && filter == .hidden { filter = .all }
        }
    }

    private func listHeader(_ list: [AppItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("\(list.count) apps · \(list.reduce(0) { $0 + $1.totalSize }.bytes)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Picker("Sort", selection: $sort) {
                    ForEach(AppSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Button {
                    Task { await state.scanApps() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan applications")
                .disabled(state.isScanningApps)
            }
            Picker("Filter", selection: $filter) {
                ForEach(AppFilter.allCases.filter { $0 != .hidden || state.showHidden }) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if state.isScanningApps {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(state.appsMeasured), total: Double(max(state.apps.count, 1)))
                    Text(state.apps.isEmpty ? "Finding apps…" : "Measuring apps and their files… \(state.appsMeasured)/\(state.apps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var detail: some View {
        let picked = state.apps.filter { selection.contains($0.id) }
        if picked.count == 1, let app = picked.first {
            AppDetailView(app: app).id(app.id)
        } else if picked.count > 1 {
            BatchUninstallView(apps: picked)
        } else {
            EmptyStateView(symbol: "square.grid.2x2.fill", tint: .indigo, title: "Select an app",
                           message: "Pick an app to see its size, every file it left around your Mac, and uninstall it completely. ⌘-click to select several.")
        }
    }
}

struct AppRow: View {
    let app: AppItem
    let maxSize: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 34, height: 34)
                .opacity(app.isHidden ? 0.7 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(app.name).fontWeight(.medium).lineLimit(1)
                    if app.isHidden {
                        Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                    }
                    if app.isProtected {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text([app.version.map { "v\($0)" }, app.lastUsedText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                if app.isMeasured {
                    Text(app.totalSize.bytes).font(.callout.monospacedDigit())
                } else {
                    ProgressView().controlSize(.mini)
                }
                SizeBar(fraction: Double(app.totalSize) / maxSize, tint: .indigo)
                    .frame(width: 64, height: 4)
            }
        }
        .padding(.vertical, 3)
    }
}

struct AppDetailView: View {
    @Environment(AppState.self) private var state
    let app: AppItem
    @State private var unchecked: Set<String> = []

    private var includeApp: Bool { !unchecked.contains(app.id) }
    private var chosenFiles: [RelatedFile] { app.related.filter { !unchecked.contains($0.id) } }
    private var chosenSize: Int64 { (includeApp ? (app.appSize ?? 0) : 0) + chosenFiles.reduce(0) { $0 + $1.size } }

    private var groups: [(String, [RelatedFile])] {
        Dictionary(grouping: app.related, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.size } > $1.1.reduce(0) { $0 + $1.size } }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { !unchecked.contains(id) },
                set: { if $0 { unchecked.remove(id) } else { unchecked.insert(id) } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                stats
                if app.isProtected {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.secondary)
                        Text("This app is part of macOS and protected by System Integrity Protection, so it can't be removed.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                } else {
                    filesCard
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            if !app.isProtected {
                ActionBar {
                    Button { app.url.revealInFinder() } label: { Label("Show in Finder", systemImage: "folder") }
                    Spacer()
                    Text("\(chosenSize.bytes) selected")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button(role: .destructive) {
                        state.requestUninstall(app, includeApp: includeApp, files: chosenFiles)
                    } label: {
                        Label(includeApp ? "Uninstall" : "Remove Files", systemImage: "trash")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(!includeApp && chosenFiles.isEmpty)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(app.name).font(.system(size: 26, weight: .bold, design: .rounded))
                Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(app.url.tildePath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Badge(text: app.location.rawValue, color: .indigo, symbol: "mappin.and.ellipse")
                    if app.isAppStore { Badge(text: "App Store", color: .blue, symbol: "bag.fill") }
                    if app.isAgent { Badge(text: "Menu Bar / Background", color: .purple, symbol: "menubar.rectangle") }
                    if app.isHidden { Badge(text: "Hidden", color: .gray, symbol: "eye.slash") }
                    if app.isProtected { Badge(text: "System", color: .gray, symbol: "lock.fill") }
                    if app.isRunning { Badge(text: "Running", color: .green, symbol: "circle.fill") }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatPill(title: "Application", value: app.appSize?.bytes ?? "…", tint: .indigo)
            StatPill(title: "Related files", value: app.relatedScanned ? app.relatedSize.bytes : "…",
                     detail: app.relatedScanned ? "\(app.related.count) items" : nil, tint: .pink)
            StatPill(title: "Total", value: app.isMeasured ? app.totalSize.bytes : "…", tint: .orange)
            StatPill(title: "Last opened",
                     value: app.lastUsed.map { relativeFormatter.localizedString(for: $0, relativeTo: Date()) } ?? "Never",
                     tint: .teal)
        }
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Everything that will be removed").font(.headline)
                Spacer()
                Button(unchecked.isEmpty ? "Deselect All" : "Select All") {
                    if unchecked.isEmpty {
                        unchecked = Set([app.id] + app.related.map(\.id))
                    } else {
                        unchecked = []
                    }
                }
                .buttonStyle(.link)
            }
            .padding(.bottom, 4)

            sectionLabel("Application bundle")
            FileRow(url: app.url, size: app.appSize ?? 0, isOn: binding(app.id), tint: .red)

            ForEach(groups, id: \.0) { category, files in
                sectionLabel(category)
                ForEach(files) { f in
                    FileRow(url: f.url, size: f.size, isOn: binding(f.id), tint: .red)
                }
            }

            if !app.relatedScanned {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching your Library for related files…").foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else if app.related.isEmpty {
                Text("No caches, preferences or support files found for this app.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(18)
        .card()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
    }
}

struct StatPill: View {
    let title: String
    let value: String
    var detail: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 12)
        }
    }
}

struct BatchUninstallView: View {
    @Environment(AppState.self) private var state
    let apps: [AppItem]

    var body: some View {
        let removable = apps.filter { !$0.isProtected }
        let total = removable.reduce(0) { $0 + $1.totalSize }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: -14) {
                        ForEach(apps.prefix(7)) { app in
                            Image(nsImage: IconCache.icon(for: app.url))
                                .resizable()
                                .frame(width: 60, height: 60)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                    }
                    Text("\(apps.count) apps selected").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Uninstalling removes each app together with its caches, preferences and support files.")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(apps) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: IconCache.icon(for: app.url)).resizable().frame(width: 24, height: 24)
                                Text(app.name)
                                if app.isProtected { Badge(text: "Protected", color: .gray, symbol: "lock.fill") }
                                Spacer()
                                Text("\(app.related.count) files").font(.caption).foregroundStyle(.secondary)
                                Text(app.totalSize.bytes).monospacedDigit().frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16)
                    .card()
                }
                .padding(24)
            }
            ActionBar {
                Spacer()
                Text("\(total.bytes) total").foregroundStyle(.secondary).monospacedDigit()
                Button(role: .destructive) {
                    state.requestBatchUninstall(apps)
                } label: {
                    Label("Uninstall \(removable.count) Apps", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(removable.isEmpty)
            }
        }
    }
}
