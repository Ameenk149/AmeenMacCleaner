import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state
    @Binding var section: AppSection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Overview")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("See what's taking up space on your Mac and safely reclaim it.")
                        .foregroundStyle(.secondary)
                }
                if !state.hasFullDiskAccess { FullDiskAccessBanner() }
                diskCard
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    StatCard(title: "Applications", symbol: AppSection.apps.symbol, tint: .indigo,
                             value: state.appsTotal.bytes,
                             caption: "\(state.visibleApps.count) apps incl. their support files",
                             busy: state.isScanningApps, button: "Review Apps") { section = .apps }
                    StatCard(title: "System Junk", symbol: AppSection.junk.symbol, tint: .orange,
                             value: state.junkScanned ? state.junkTotal.bytes : "—",
                             caption: "\(state.junkItemCount) items in caches, logs and developer data",
                             busy: state.isScanningJunk, button: "Clean Junk") { section = .junk }
                    StatCard(title: "Leftovers", symbol: AppSection.leftovers.symbol, tint: .pink,
                             value: state.orphansScanned ? state.orphanTotal.bytes : "—",
                             caption: "\(state.orphans.count) files left behind by apps you deleted",
                             busy: state.isScanningOrphans, button: "Review Leftovers") { section = .leftovers }
                    StatCard(title: "Large Files", symbol: AppSection.large.symbol, tint: .teal,
                             value: state.largeScanned ? state.largeTotal.bytes : "—",
                             caption: state.largeScanned
                                 ? "\(state.visibleLargeFiles.count) files over \(state.largeThresholdMB) MB in your home folder"
                                 : "Find big, forgotten files in your home folder",
                             busy: state.isScanningLarge, button: state.largeScanned ? "Review Files" : "Find Large Files") {
                        if !state.largeScanned && !state.isScanningLarge { state.scanLarge() }
                        section = .large
                    }
                    StatCard(title: "Space Explorer", symbol: AppSection.explorer.symbol, tint: .purple,
                             value: homeSize.map(\.bytes) ?? "—",
                             caption: "Your home folder — drill into folders to see what uses the space",
                             busy: state.explorer.folders[Paths.home.path]?.loading ?? false, button: "Explore Folders") {
                        state.explorer.setRoot(Paths.home)
                        section = .explorer
                    }
                    StatCard(title: "Trash", symbol: "trash.fill", tint: .gray,
                             value: state.trashSize.bytes,
                             caption: "Space isn't freed until the Trash is emptied",
                             busy: false, button: "Empty Trash") { state.requestEmptyTrash() }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var homeSize: Int64? {
        guard let f = state.explorer.folders[Paths.home.path], !f.loading else { return nil }
        return f.total(includeHidden: true)
    }

    private var segments: [StorageBar.Segment] {
        let total = Double(max(state.disk.total, 1))
        let apps = Double(state.appsTotal)
        let junk = Double(state.junkTotal)
        let left = Double(state.orphanTotal)
        let large = Double(state.largeScanned ? state.largeTotal : 0)
        let trash = Double(state.trashSize)
        let other = max(0, Double(state.disk.used) - apps - junk - left - large - trash)
        return [
            .init(label: "Apps", color: .indigo, fraction: apps / total),
            .init(label: "Junk", color: .orange, fraction: junk / total),
            .init(label: "Leftovers", color: .pink, fraction: left / total),
            .init(label: "Large files", color: .teal, fraction: large / total),
            .init(label: "Trash", color: .gray, fraction: trash / total),
            .init(label: "Other", color: Color.primary.opacity(0.28), fraction: other / total),
        ]
    }

    private var diskCard: some View {
        HStack(alignment: .center, spacing: 32) {
            DiskRing(fraction: state.disk.usedFraction)
                .frame(width: 170, height: 170)
            VStack(alignment: .leading, spacing: 10) {
                Label(state.disk.name, systemImage: "internaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(state.disk.free.bytes) available")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(state.disk.used.bytes) used of \(state.disk.total.bytes)")
                    .foregroundStyle(.secondary)
                StorageBar(segments: segments)
                    .frame(height: 12)
                    .padding(.top, 4)
                HStack(spacing: 14) {
                    ForEach(segments.filter { $0.fraction > 0 }, id: \.label) { seg in
                        HStack(spacing: 5) {
                            Circle().fill(seg.color).frame(width: 8, height: 8)
                            Text(seg.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button {
                        Task { await state.smartScan() }
                    } label: {
                        HStack(spacing: 6) {
                            if state.isSmartScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(state.isSmartScanning ? "Scanning…" : "Smart Scan")
                        }
                        .frame(minWidth: 130)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isSmartScanning)

                    if state.isScanningApps, !state.apps.isEmpty {
                        Text("Measuring apps \(state.appsMeasured)/\(state.apps.count)…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else if state.reclaimable > 0 {
                        Text("Up to **\(state.reclaimable.bytes)** can be freed")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .card(radius: 20)
    }
}

struct DiskRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 18)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [.blue, .purple, .pink, .orange], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("used").font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.easeOut(duration: 0.8), value: fraction)
    }
}

struct StorageBar: View {
    struct Segment {
        let label: String
        let color: Color
        let fraction: Double
    }
    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments.filter { $0.fraction > 0.0015 }, id: \.label) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(2, geo.size.width * seg.fraction))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
        }
        .animation(.easeOut(duration: 0.6), value: segments.map(\.fraction))
    }
}

struct StatCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let caption: String
    let busy: Bool
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(symbol: symbol, tint: tint, size: 36)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Button(button, action: action)
                .buttonStyle(.bordered)
                .tint(tint)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
