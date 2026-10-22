import SwiftUI
import AppKit

enum Ring {
    static func image(percent: Double?, hot: Bool, size: CGFloat = 16, dashed: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth = size * 0.16
            let inset = lineWidth / 2 + 0.5
            let circle = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = circle.width / 2

            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = lineWidth
            if dashed { track.setLineDash([lineWidth, lineWidth], count: 2, phase: 0) }
            let color = hot ? NSColor.warn : NSColor.black
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()

            if let percent {
                let fraction = min(max(percent, 0), 100) / 100
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = !hot
        return image
    }

    struct View: SwiftUI.View {
        let percent: Double?
        let color: Color
        var size: CGFloat = 16
        var dashed = false

        var body: some SwiftUI.View {
            let lineWidth = size * 0.16
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [lineWidth, lineWidth] : []))
                if let percent {
                    Circle()
                        .trim(from: 0, to: min(max(percent, 0), 100) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(lineWidth / 2)
            .frame(width: size, height: size)
        }
    }
}
