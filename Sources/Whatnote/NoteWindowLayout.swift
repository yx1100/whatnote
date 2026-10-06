import AppKit

enum NoteWindowLayout {
    /// The part of `visibleFrame` left free by other apps' UI along its left, right and bottom
    /// edges, such as a Dock or a floating panel. Only strips that hug an edge count; ordinary
    /// windows and small banners do not shrink the area.
    static func usableFrame(
        in visibleFrame: NSRect,
        avoiding obstacles: [NSRect],
        edgeTolerance: CGFloat = 24,
        spacing: CGFloat = 8
    ) -> NSRect {
        var minX = visibleFrame.minX
        var maxX = visibleFrame.maxX
        var minY = visibleFrame.minY
        for obstacle in obstacles {
            let overlap = obstacle.intersection(visibleFrame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let isSideStrip = overlap.width < visibleFrame.width * 0.35 && overlap.height >= visibleFrame.height * 0.15
            let isEndStrip = overlap.height < visibleFrame.height * 0.35 && overlap.width >= visibleFrame.width * 0.15
            if isSideStrip, overlap.minX <= visibleFrame.minX + edgeTolerance {
                minX = max(minX, overlap.maxX + spacing)
            } else if isSideStrip, overlap.maxX >= visibleFrame.maxX - edgeTolerance {
                maxX = min(maxX, overlap.minX - spacing)
            } else if isEndStrip, overlap.minY <= visibleFrame.minY + edgeTolerance {
                minY = max(minY, overlap.maxY + spacing)
            }
            // The top edge is left alone: below the menu bar only passing banners appear there.
        }
        let usable = NSRect(x: minX, y: minY, width: maxX - minX, height: visibleFrame.maxY - minY)
        // Never give up most of the screen because of something unexpected.
        guard usable.width >= visibleFrame.width / 2, usable.height >= visibleFrame.height / 2 else { return visibleFrame }
        return usable
    }

    static func alignedFrames(
        sizes: [NSSize],
        in visibleFrame: NSRect,
        margin: CGFloat = 16,
        gap: CGFloat = 12,
        maximumRows: Int = 4
    ) -> [NSRect] {
        guard !sizes.isEmpty else { return [] }

        let count = sizes.count
        let availableWidth = max(1, visibleFrame.width - margin * 2)
        let availableHeight = max(1, visibleFrame.height - margin * 2)
        let rows = min(count, max(1, maximumRows))
        let columns = Int(ceil(Double(count) / Double(rows)))
        let maximumColumnWidth = max(
            1,
            (availableWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        )
        let columnRanges = (0..<columns).map { column in
            let start = column * rows
            let end = min(start + rows, count)
            return start..<end
        }
        let columnWidths = columnRanges.map { range in
            return min(
                maximumColumnWidth,
                sizes[range].map(\.width).max() ?? maximumColumnWidth
            )
        }
        let columnHeightScales = columnRanges.map { range in
            let requestedHeight = sizes[range].reduce(CGFloat.zero) { total, size in
                total + max(1, size.height)
            }
            let availableNoteHeight = max(1, availableHeight - gap * CGFloat(range.count - 1))
            return min(1, availableNoteHeight / requestedHeight)
        }
        var columnOrigins: [CGFloat] = []
        var nextX = visibleFrame.minX + margin
        for width in columnWidths {
            columnOrigins.append(nextX)
            nextX += width + gap
        }

        var columnTops = Array(repeating: visibleFrame.maxY - margin, count: columns)
        return sizes.enumerated().map { index, requestedSize in
            let column = index / rows
            let size = NSSize(
                width: min(requestedSize.width, columnWidths[column]),
                height: max(1, requestedSize.height) * columnHeightScales[column]
            )
            let x = columnOrigins[column]
            let y = columnTops[column] - size.height
            columnTops[column] = y - gap
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}
