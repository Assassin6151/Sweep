import CoreGraphics

/// Squarified treemap layout (after Bruls, Huizing & van Wijk). Places rectangles whose areas are
/// proportional to `values` inside `bounds`, keeping them as close to squares as possible.
enum TreemapLayout {
    /// Returns one rectangle per input value, in input order. Values ≤ 0 get an empty rectangle.
    static func squarify(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let order = values.indices
            .filter { values[$0] > 0 }
            .sorted { values[$0] > values[$1] }
        var areas = order.map { values[$0] * scale }[...]
        var indices = order[...]
        var remaining = bounds

        while !areas.isEmpty {
            let side = Double(min(remaining.width, remaining.height))
            var row: [Double] = []
            var rowCount = 0
            for area in areas {
                if row.isEmpty || worstRatio(row + [area], side: side) <= worstRatio(row, side: side) {
                    row.append(area)
                    rowCount += 1
                } else {
                    break
                }
            }
            let rects = layoutRow(row, in: &remaining)
            for (offset, rect) in rects.enumerated() {
                result[indices[indices.startIndex + offset]] = rect
            }
            areas = areas.dropFirst(rowCount)
            indices = indices.dropFirst(rowCount)
        }
        return result
    }

    /// The worst (largest) aspect ratio in a row laid out along a side of length `side`.
    static func worstRatio(_ row: [Double], side: Double) -> Double {
        guard let maxArea = row.max(), let minArea = row.min(), minArea > 0, side > 0 else { return .infinity }
        let sum = row.reduce(0, +)
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(sideSquared * maxArea / sumSquared, sumSquared / (sideSquared * minArea))
    }

    /// Lays out one row along the shorter side of `rect` and shrinks `rect` to the remaining space.
    private static func layoutRow(_ row: [Double], in rect: inout CGRect) -> [CGRect] {
        let sum = row.reduce(0, +)
        var rects: [CGRect] = []
        if rect.width >= rect.height {
            // Vertical strip on the left.
            let stripWidth = CGFloat(sum) / rect.height
            var y = rect.minY
            for area in row {
                let height = CGFloat(area) / stripWidth
                rects.append(CGRect(x: rect.minX, y: y, width: stripWidth, height: height))
                y += height
            }
            rect = CGRect(x: rect.minX + stripWidth, y: rect.minY, width: max(0, rect.width - stripWidth), height: rect.height)
        } else {
            // Horizontal strip at the top.
            let stripHeight = CGFloat(sum) / rect.width
            var x = rect.minX
            for area in row {
                let width = CGFloat(area) / stripHeight
                rects.append(CGRect(x: x, y: rect.minY, width: width, height: stripHeight))
                x += width
            }
            rect = CGRect(x: rect.minX, y: rect.minY + stripHeight, width: rect.width, height: max(0, rect.height - stripHeight))
        }
        return rects
    }
}
