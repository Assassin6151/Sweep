import SwiftUI

/// Interactive treemap of a folder's children. Folders show their own children as a faint inner layer.
struct TreemapView: View {
    let node: DiskNode
    @Binding var hovered: DiskNode?
    let onOpen: (DiskNode) -> Void
    let onTrash: (DiskNode) -> Void

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let rects = TreemapLayout.squarify(node.children.map { Double($0.size) }, in: bounds)
            ZStack(alignment: .topLeading) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    let rect = rects[index]
                    if rect.width >= 2 && rect.height >= 2 {
                        TreemapTile(node: child, color: TreemapPalette.color(for: child, index: index),
                                    isHovered: hovered?.id == child.id)
                            .frame(width: rect.width - 2, height: rect.height - 2)
                            .offset(x: rect.minX + 1, y: rect.minY + 1)
                            .onHover { inside in
                                if inside { hovered = child } else if hovered?.id == child.id { hovered = nil }
                            }
                            .onTapGesture { onOpen(child) }
                            .contextMenu {
                                if child.canDrillDown { Button("Öffnen") { onOpen(child) } }
                                if child.isRealItem {
                                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([child.url]) }
                                    Divider()
                                    Button("In den Papierkorb legen …", role: .destructive) { onTrash(child) }
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct TreemapTile: View {
    let node: DiskNode
    let color: Color
    let isHovered: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.92), color.shaded(by: 0.18).opacity(0.92)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))

                if node.kind == .folder && size.width > 60 && size.height > 50 {
                    InnerLayer(node: node)
                        .padding(EdgeInsets(top: 30, leading: 4, bottom: 4, trailing: 4))
                }

                if size.width > 54 && size.height > 28 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if size.width > 90 {
                                Image(systemName: icon).font(.caption2)
                            }
                            Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        if size.height > 44 {
                            Text(ByteFormat.string(node.size)).font(.caption2.monospacedDigit()).opacity(0.85)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(isHovered ? 0.9 : 0.12), lineWidth: isHovered ? 2 : 0.5)
            )
            .brightness(isHovered ? 0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }

    private var icon: String {
        switch node.kind {
        case .folder: "folder.fill"
        case .package: "shippingbox.fill"
        case .other: "ellipsis.circle"
        case .unreadable: "lock.fill"
        case .file: FileKind(url: node.url).symbol
        }
    }
}

/// Grandchildren drawn with a Canvas – cheap even for many folders.
private struct InnerLayer: View {
    let node: DiskNode

    var body: some View {
        Canvas { context, size in
            let rects = TreemapLayout.squarify(node.children.map { Double($0.size) }, in: CGRect(origin: .zero, size: size))
            for rect in rects where rect.width > 3 && rect.height > 3 {
                let path = Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 3)
                context.fill(path, with: .color(.white.opacity(0.10)))
                context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

enum TreemapPalette {
    static let folderColors: [Color] = [
        Color(red: 0.97, green: 0.58, blue: 0.20), Color(red: 0.30, green: 0.60, blue: 0.92),
        Color(red: 0.20, green: 0.68, blue: 0.56), Color(red: 0.66, green: 0.42, blue: 0.88),
        Color(red: 0.90, green: 0.40, blue: 0.48), Color(red: 0.36, green: 0.48, blue: 0.86),
        Color(red: 0.82, green: 0.62, blue: 0.22), Color(red: 0.26, green: 0.66, blue: 0.78),
    ]

    static func color(for node: DiskNode, index: Int) -> Color {
        switch node.kind {
        case .folder: folderColors[index % folderColors.count]
        case .package: FileKind.application.color
        case .file: FileKind(url: node.url).color
        case .other, .unreadable: Color.gray.opacity(0.7)
        }
    }
}
