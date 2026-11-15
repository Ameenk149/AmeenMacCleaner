import SwiftUI

// MARK: - System Junk

struct JunkView: View {
    @Environment(AppState.self) private var state
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .junk, subtitle: "Caches, logs, developer data and installers that are safe to remove.") {
                Button {
                    Task { await state.scanJunk() }
                } label: {
                    Label(state.junkScanned ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                }
                .disabled(state.isScanningJunk)
            }
            if !state.junkScanned && !state.isScanningJunk {
                EmptyStateView(symbol: "sparkles", tint: .orange, title: "Find system junk",
                               message: "Scan caches, logs, Xcode data, package-manager caches and leftover installers.",
                               buttonTitle: "Scan Now") { Task { await state.scanJunk() } }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(state.junkGroups) { group in
                            JunkGroupCard(group: group, isExpanded: Binding(
                                get: { expanded.contains(group.id) },
                                set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                ActionBar {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(state.junkSelectedTotal.bytes) selected").font(.headline).monospacedDigit()
                        Text("Caches are recreated by apps as needed.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.requestJunkClean()
                    } label: {
                        Label("Clean", systemImage: "sparkles").frame(minWidth: 90)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(state.junkSelectedTotal == 0 || state.isScanningJunk)
                }
            }
        }
    }
}

struct JunkGroupCard: View {
    @Bindable var group: JunkGroup
    @Binding var isExpanded: Bool

    private var checkState: CheckButton.State {
        if group.selected.isEmpty { return .off }
        return group.selected.count == group.items.count ? .on : .mixed
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CheckButton(state: checkState, tint: group.kind.tint) {
                    group.selected = checkState == .on ? [] : Set(group.items.map(\.id))
                }
                .disabled(group.items.isEmpty)
                IconTile(symbol: group.kind.symbol, tint: group.kind.tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.kind.title).font(.headline)
                    Text(group.kind.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if group.scanning {
                    ProgressView().controlSize(.small)
                } else if group.items.isEmpty {
                    Text("Nothing found").foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(group.totalSize.bytes)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("\(group.items.count) items").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(group.items.isEmpty ? 0 : 1)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !group.items.isEmpty else { return }
                withAnimation(.snappy) { isExpanded.toggle() }
            }

            if isExpanded {
                Divider()
                VStack(spacing: 0) {
                    ForEach(group.items.prefix(300)) { item in
                        FileRow(url: item.url, size: item.size, isOn: Binding(
                            get: { group.selected.contains(item.id) },
                            set: { if $0 { group.selected.insert(item.id) } else { group.selected.remove(item.id) } }),
                            tint: group.kind.tint)
                    }
                    if group.items.count > 300 {
                        Text("+ \(group.items.count - 300) smaller items").font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .card(radius: 14)
        .opacity(group.scanned && group.items.isEmpty ? 0.6 : 1)
    }
}

// MARK: - Leftovers

struct LeftoversView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            PageHeader(section: .leftovers, subtitle: "Preferences, caches and containers left behind by apps that are no longer installed.") {
                Button {
                    Task { await state.scanOrphans() }
                } label: {
                    Label(state.orphansScanned ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
                }
                .disabled(state.isScanningOrphans)
            }
            if state.isScanningOrphans && state.orphans.isEmpty {
                ProgressView("Looking for leftovers…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.orphansScanned {
                EmptyStateView(symbol: "puzzlepiece.extension.fill", tint: .pink, title: "Find leftovers",
                               message: "Find files from apps you've already deleted.",
                               buttonTitle: "Scan Now") { Task { await state.scanOrphans() } }
            } else if state.orphans.isEmpty {
                EmptyStateView(symbol: "checkmark.seal.fill", tint: .green, title: "No leftovers",
                               message: "No files from uninstalled apps were found.")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.pink)
                    Text("Review before removing — some files may belong to command-line tools, plug-ins or apps on an external drive. Nothing is selected by default.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.pink.opacity(0.07)))
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                List {
                    ForEach(state.orphans) { item in
                        FileRow(url: item.url, size: item.size, subtitle: "\(item.category) · \(item.url.deletingLastPathComponent().tildePath)",
                                isOn: Binding(
                                    get: { state.orphanSelection.contains(item.id) },
                                    set: { if $0 { state.orphanSelection.insert(item.id) } else { state.orphanSelection.remove(item.id) } }),
                                tint: .pink)
                    }
                }
                .listStyle(.inset)

                let selectedSize = state.orphans.filter { state.orphanSelection.contains($0.id) }.reduce(0) { $0 + $1.size }
                ActionBar {
                    Button(state.orphanSelection.count == state.orphans.count ? "Deselect All" : "Select All") {
                        if state.orphanSelection.count == state.orphans.count {
                            state.orphanSelection = []
                        } else {
                            state.orphanSelection = Set(state.orphans.map(\.id))
                        }
                    }
                    Text("\(state.orphans.count) items · \(state.orphanTotal.bytes)").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text("\(selectedSize.bytes) selected").foregroundStyle(.secondary).monospacedDigit()
                    Button(role: .destructive) {
                        state.requestOrphanRemoval()
                    } label: {
                        Label("Remove", systemImage: "trash").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .controlSize(.large)
                    .disabled(state.orphanSelection.isEmpty)
                }
            }
        }
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\LargeFile.size, order: .reverse)]

    private let thresholds = [50, 100, 250, 500, 1000]

    var body: some View {
        @Bindable var state = state
        let rows = state.visibleLargeFiles.sorted(using: sortOrder)
        VStack(spacing: 0) {
            PageHeader(section: .large, subtitle: "Big files hiding in your home folder. Turn on “Show hidden items” to include ~/Library and dot-folders.") {
                Picker("Larger than", selection: $state.largeThresholdMB) {
                    ForEach(thresholds, id: \.self) { mb in
                        Text(mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB").tag(mb)
                    }
                }
                .fixedSize()
                .disabled(state.isScanningLarge)
                if state.isScanningLarge {
                    Button("Stop") { state.stopLarge() }
                } else {
                    Button { state.scanLarge() } label: {
                        Label(state.largeScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                    }
                }
            }
            if state.isScanningLarge {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanned \(state.largeScannedCount.formatted()) files…")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.largeScanned {
                EmptyStateView(symbol: "doc.on.doc.fill", tint: .teal, title: "Find large files",
                               message: "Scan your home folder for videos, disk images, archives and other big files you may have forgotten.",
                               buttonTitle: "Scan Home Folder") { state.scanLarge() }
            } else if rows.isEmpty {
                EmptyStateView(symbol: "checkmark.seal.fill", tint: .green, title: "No large files",
                               message: "Nothing over the selected size was found.")
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { f in
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.icon(for: f.url)).resizable().frame(width: 18, height: 18)
                            Text(f.name).lineLimit(1)
                        }
                    }
                    .width(min: 180, ideal: 280)
                    TableColumn("Size", value: \.size) { f in
                        Text(f.size.bytes).monospacedDigit().fontWeight(.medium)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Kind", value: \.kind) { f in
                        Text(f.kind).foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 70)
                    TableColumn("Last Opened", value: \.accessed) { f in
                        Text(f.accessed == .distantPast ? "—" : f.accessed.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn("Location", value: \.folder) { f in
                        Text(f.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
                    }
                    Button("Remove…", role: .destructive) { state.requestLargeRemoval(ids) }
                } primaryAction: { ids in
                    NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
                }

                let selectedSize = rows.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size }
                ActionBar {
                    Text("\(rows.count) files · \(state.largeTotal.bytes)").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if !selection.isEmpty {
                        Text("\(selection.count) selected · \(selectedSize.bytes)").foregroundStyle(.secondary).monospacedDigit()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(selection.map { URL(fileURLWithPath: $0) })
                        }
                    } else {
                        Text("⌘-click to select several files").font(.caption).foregroundStyle(.tertiary)
                    }
                    Button(role: .destructive) {
                        state.requestLargeRemoval(selection)
                    } label: {
                        Label("Remove", systemImage: "trash").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .controlSize(.large)
                    .disabled(selection.isEmpty)
                }
            }
        }
    }
}
