import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview, explorer, apps, junk, leftovers, large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .explorer: "Space Explorer"
        case .apps: "Applications"
        case .junk: "System Junk"
        case .leftovers: "Leftovers"
        case .large: "Large Files"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .explorer: "chart.pie.fill"
        case .apps: "square.grid.2x2.fill"
        case .junk: "sparkles"
        case .leftovers: "puzzlepiece.extension.fill"
        case .large: "doc.on.doc.fill"
        }
    }
    var tint: Color {
        switch self {
        case .overview: .blue
        case .explorer: .purple
        case .apps: .indigo
        case .junk: .orange
        case .leftovers: .pink
        case .large: .teal
        }
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.25), radius: size * 0.08, y: size * 0.04)
    }
}

struct Badge: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct CardModifier: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = 16) -> some View { modifier(CardModifier(radius: radius)) }
}

struct PageHeader<Trailing: View>: View {
    let section: AppSection
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: section.symbol, tint: section.tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            IconTile(symbol: symbol, tint: tint, size: 72)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Square checkbox that can show a mixed state.
struct CheckButton: View {
    enum State { case on, off, mixed }
    let state: State
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(state == .off ? Color.secondary : tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

struct FileRow: View {
    let url: URL
    let size: Int64
    var subtitle: String?
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            CheckButton(state: isOn ? .on : .off, tint: tint) { isOn.toggle() }
            Image(nsImage: IconCache.icon(for: url))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).lineLimit(1)
                Text(subtitle ?? url.deletingLastPathComponent().tildePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(size.bytes)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { url.revealInFinder() } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

struct SizeBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Grant Full Disk Access for a deeper clean").font(.headline)
                Text("Without it, macOS hides some caches, containers and app data from the scanner. Add Ameen Mac Cleaner in Privacy & Security → Full Disk Access, then reopen the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .controlSize(.large)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.3)))
    }
}

/// Bottom action bar used by list pages.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}
