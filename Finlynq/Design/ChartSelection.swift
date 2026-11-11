import Charts
import SwiftUI

/// What a chart draws for the selected point. Lines get a rule and a ringed point, bars a highlight band of the
/// given width: the plot's full height, or with `hugsBar` from just above the bar down, for bars with a value label
/// above them inside the plot.
enum ChartSelectionStyle {
    case line(Color)
    case bar(width: CGFloat, hugsBar: Bool = false)
}

/// What a line chart marks when nothing is selected: nothing, a dot on the last point, or the full selection
/// (rule, ring and tooltip) on the last point, as the Mac Home chart does.
enum ChartResting: Equatable {
    case none
    case dot
    case tooltip
}

/// The selection on top of a chart: the Mac pointer hovers, and on iOS a press and drag scrubs, with a light
/// haptic each time the point changes; lifting the finger hides it. It owns the selection, so moving it redraws
/// only this layer, never the chart's marks.
struct ChartSelectionLayer: View {
    /// The plot area in this layer: the rule's and band's height, and where the tooltip stays.
    let plot: CGRect
    let style: ChartSelectionStyle
    var resting: ChartResting = .none
    var interactive = true
    /// The point marked at rest.
    var last: Int?
    /// The point nearest a location in this layer.
    let pick: (CGPoint) -> Int?
    /// A point's position in this layer.
    let anchor: (Int) -> CGPoint?
    /// The tooltip's lines for a point: a title (a date or a period), then one or more values.
    let tip: (Int) -> [String]
    @State private var selected: Int?

    var body: some View {
        ChartDebug.plotBuilt("selection")
        return ZStack(alignment: .topLeading) {
            Color.clear
            if let index = selected ?? (resting == .tooltip ? last : nil), let point = anchor(index) {
                indicator(point)
                // A plot too short for every line gets the values on one line.
                ViewThatFits(in: .vertical) {
                    ChartTooltip(lines: tip(index))
                    ChartTooltip(lines: tip(index), compact: true)
                }
                .frame(maxHeight: plot.height)
                .placed(at: point, in: plot)
            } else if resting == .dot, case .line(let color) = style, let last, let point = anchor(last) {
                Circle().fill(color).frame(width: 9, height: 9).position(point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(interactive)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): select(location)
            case .ended: selected = nil
            }
        }
        #if os(iOS)
        .gesture(ScrubGesture { location in
            if let location { select(location) } else { selected = nil }
        })
        .sensoryFeedback(.selection, trigger: selected) { _, new in new != nil }
        #endif
        .accessibilityHidden(true)
        .onAppear { if ChartDebug.sweeps && interactive { Task { await sweep() } } }
    }

    /// See `ChartDebug.sweeps`.
    private func sweep() async {
        try? await Task.sleep(for: .seconds(2))
        ChartDebug.mark("sweep start")
        let start = ContinuousClock.now
        var step = 0
        while ContinuousClock.now - start < .seconds(2) {
            select(CGPoint(x: plot.minX + plot.width * CGFloat(step % 240) / 240, y: plot.midY))
            step += 1
            try? await Task.sleep(for: .milliseconds(8))
        }
        ChartDebug.mark("sweep end, \(step) moves")
        selected = nil
    }

    private func select(_ location: CGPoint) {
        guard plot.insetBy(dx: -8, dy: -8).contains(location) else {
            selected = nil
            return
        }
        let index = pick(location)
        if index != selected { selected = index }
    }

    @ViewBuilder
    private func indicator(_ point: CGPoint) -> some View {
        switch style {
        case .line(let color):
            Path { path in
                path.move(to: CGPoint(x: point.x, y: plot.minY))
                path.addLine(to: CGPoint(x: point.x, y: plot.maxY))
            }
            #if os(macOS)
            .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            #else
            .stroke(color.opacity(0.3), lineWidth: 1)
            #endif
            Circle().fill(Theme.card).overlay(Circle().stroke(color, lineWidth: 2)).frame(width: 9, height: 9).position(point)
        case .bar(let width, let hugsBar):
            let top = hugsBar ? max(point.y - 4, plot.minY) : plot.minY
            RoundedRectangle(cornerRadius: 6).fill(Theme.text.opacity(0.07))
                .frame(width: width, height: plot.maxY - top)
                .position(x: point.x, y: (top + plot.maxY) / 2)
        }
    }
}

/// The Home chart's tooltip: a dark rounded box with the date over the value. Compact puts every value on one
/// smaller line under the title, for short plots.
struct ChartTooltip: View {
    let lines: [String]
    var compact = false

    var body: some View {
        let values = Array(lines.dropFirst())
        VStack(alignment: .leading, spacing: 2) {
            if let title = lines.first {
                Text(title).font(compact ? .footnote : .callout).foregroundStyle(.white.opacity(0.75))
            }
            if compact {
                Text(values.joined(separator: " \u{00B7} ")).font(.footnote.weight(.semibold)).foregroundStyle(.white)
            } else {
                ForEach(values, id: \.self) { line in
                    Text(line).font(.body.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
        .monospacedDigit().lineLimit(1).fixedSize()
        .padding(.horizontal, compact ? 8 : 12).padding(.vertical, compact ? 4 : 6)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    /// Sits above and to the right of `point`, or to the left when there's no room, and stays inside `bounds`.
    func placed(at point: CGPoint, in bounds: CGRect) -> some View {
        alignmentGuide(.leading) { size in
            let right = point.x + 12
            let x = right + size.width <= bounds.maxX ? right : point.x - 12 - size.width
            return -max(min(x, bounds.maxX - size.width), bounds.minX)
        }
        .alignmentGuide(.top) { size in
            -max(min(point.y - 6 - size.height, bounds.maxY - size.height), bounds.minY)
        }
    }

    /// Hover (Mac) or press and drag (iOS) over a bar chart with one column per label highlights the column and
    /// shows `tip(index)` in the tooltip. `tops` are each column's tallest value, where the tooltip points.
    func barSelection(labels: [String], tops: [Double], tip: @escaping (Int) -> [String]) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame, !labels.isEmpty {
                    let plot = geometry[frame]
                    let centers = labels.map { Double(plot.minX + (proxy.position(forX: $0) ?? 0)) }
                    ChartSelectionLayer(
                        plot: plot, style: .bar(width: plot.width / CGFloat(labels.count) * 0.92),
                        pick: { ChartMath.nearest(centers, to: Double($0.x)) },
                        anchor: { index in
                            proxy.position(forY: tops[index]).map { CGPoint(x: centers[index], y: plot.minY + $0) }
                        },
                        tip: tip
                    )
                }
            }
        }
    }
}

#if os(iOS)
/// A press that turns into a drag, like the Stocks chart: it starts after a hold of a quarter second, so a swipe
/// still scrolls the page, and reports the finger's location in the view until it lifts (nil).
private struct ScrubGesture: UIGestureRecognizerRepresentable {
    let changed: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.25
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: changed(context.converter.localLocation)
        default: changed(nil)
        }
    }
}
#endif
