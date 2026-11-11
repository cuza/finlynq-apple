import Accessibility
import Charts
import SwiftUI

/// A value over time: a line over a soft fill that reaches the bottom of the plot, with an optional dashed line
/// (cost basis or a comparison plan) and target rule. The series is reduced to about one point per x point of the
/// plot, the Y range is fixed on round numbers, and hovering or scrubbing shows a tooltip without redrawing the marks.
struct TimeSeriesChart: View {
    enum XAxis: Equatable {
        case hidden
        /// Charts' own date labels, about `count` of them (Home).
        case automatic(Int)
        /// Month names, about `count` of them.
        case months(Int)
        /// Month names, with the year in place of January, in footnote grey (Account, Holding, Investments).
        case monthsAndYears
        /// "Now" under the first point, then each later January 1 by year (Debts.dc.html).
        case nowAndYears
    }

    enum YAxis: Equatable {
        case hidden
        /// Gridlines with compact money labels: `count` labels on the left or right.
        case leading(Int)
        case trailing(Int)
    }

    let points: [ValuePoint]
    var color: Color = Theme.accent
    var height: CGFloat = 120
    var xAxis: XAxis = .monthsAndYears
    var yAxis: YAxis = .hidden
    var currency: String?
    /// Monotone curve instead of straight segments (net worth).
    var smooth = false
    var fillOpacity = 0.1
    /// Keeps zero inside the Y range (debt projections falling to zero).
    var fromZero = false
    /// A second series drawn as a dashed grey line, such as the loan plan without the extra payment.
    var dashed: [ValuePoint] = []
    /// A dashed horizontal line with a label under its right end, such as a goal's target.
    var target: (value: Double, label: String)?
    var resting: ChartResting = .dot
    /// Off where the chart is a link or too small to point at.
    var interactive = true

    @State private var width: CGFloat = 0

    var body: some View {
        // Until the first layout reports the width, assume a phone-sized plot.
        let limit = Int(width > 0 ? width : 400)
        let costs = points.compactMap { point in point.cost.map { ValuePoint(day: point.day, value: $0) } }
        var extra = dashed.map(\.value) + costs.map(\.value)
        if let target { extra.append(target.value) }
        if fromZero { extra.append(0) }
        let intervals = switch yAxis {
        case .hidden: 8
        case .leading(let count), .trailing(let count): max(count - 1, 1)
        }
        return TimeSeriesPlot(
            full: points,
            fullDays: points.map(\.day.timeIntervalSinceReferenceDate),
            points: ChartMath.downsample(points, limit: limit) { $0.value },
            dashed: ChartMath.downsample(dashed, limit: limit) { $0.value },
            costs: ChartMath.downsample(costs, limit: limit) { $0.value },
            scale: ChartMath.yScale(points.map(\.value) + extra, intervals: intervals),
            style: .init(color: color, xAxis: xAxis, yAxis: yAxis, currency: currency, smooth: smooth, fillOpacity: fillOpacity,
                         targetValue: target?.value, targetLabel: target?.label, resting: resting, interactive: interactive),
            descriptor: TimeSeriesDescriptor(points: points, currency: currency)
        )
        .equatable()
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The chart's marks. It changes only when the series, the scale or the style do, never with the selection.
private struct TimeSeriesPlot: View, Equatable {
    struct Style: Equatable {
        let color: Color
        let xAxis: TimeSeriesChart.XAxis
        let yAxis: TimeSeriesChart.YAxis
        let currency: String?
        let smooth: Bool
        let fillOpacity: Double
        let targetValue: Double?
        let targetLabel: String?
        let resting: ChartResting
        let interactive: Bool
    }

    /// Every point, for the tooltip, and their dates as seconds for the binary search. Not compared: the marks
    /// depend only on the downsampled `points`.
    let full: [ValuePoint]
    let fullDays: [Double]
    let points: [ValuePoint]
    let dashed: [ValuePoint]
    let costs: [ValuePoint]
    let scale: ChartMath.Scale
    let style: Style
    let descriptor: TimeSeriesDescriptor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.points == rhs.points && lhs.dashed == rhs.dashed && lhs.costs == rhs.costs && lhs.scale == rhs.scale && lhs.style == rhs.style
    }

    var body: some View {
        ChartDebug.plotBuilt("timeSeries")
        let color = style.color
        let interpolation: InterpolationMethod = style.smooth ? .monotone : .linear
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.day), yStart: .value("Floor", scale.lower), yEnd: .value("Value", point.value))
                    .foregroundStyle(color.opacity(style.fillOpacity)).interpolationMethod(interpolation)
                LineMark(x: .value("Date", point.day), y: .value("Value", point.value), series: .value("Line", "value"))
                    .foregroundStyle(color).interpolationMethod(interpolation)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(costs) { point in
                LineMark(x: .value("Date", point.day), y: .value("Cost", point.value), series: .value("Line", "cost"))
                    .foregroundStyle(Theme.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .interpolationMethod(.stepEnd)
            }
            ForEach(dashed) { point in
                LineMark(x: .value("Date", point.day), y: .value("Compare", point.value), series: .value("Line", "dashed"))
                    .foregroundStyle(Theme.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            if let value = style.targetValue {
                RuleMark(y: .value("Target", value))
                    .foregroundStyle(Theme.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text(style.targetLabel ?? "").font(.caption).foregroundStyle(Theme.secondary)
                    }
            }
        }
        .chartYScale(domain: scale.domain)
        .chartYAxis { yAxisMarks }
        .chartXAxis { xAxisMarks }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame, style.interactive || style.resting != .none {
                    let plot = geometry[frame]
                    ChartSelectionLayer(
                        plot: plot, style: .line(color), resting: style.resting, interactive: style.interactive,
                        last: full.indices.last,
                        pick: { location in
                            proxy.value(atX: location.x - plot.minX, as: Date.self).flatMap {
                                ChartMath.nearest(fullDays, to: $0.timeIntervalSinceReferenceDate)
                            }
                        },
                        anchor: { index in
                            guard let x = proxy.position(forX: full[index].day), let y = proxy.position(forY: full[index].value)
                            else { return nil }
                            return CGPoint(x: plot.minX + x, y: plot.minY + y)
                        },
                        tip: { index in
                            [full[index].day.formatted(date: .abbreviated, time: .omitted), full[index].value.wholeMoney(style.currency)]
                        }
                    )
                }
            }
        }
        .accessibilityChartDescriptor(descriptor)
    }

    @AxisContentBuilder
    private var yAxisMarks: some AxisContent {
        switch style.yAxis {
        case .hidden:
            AxisMarks { _ in }
        case .leading:
            moneyMarks(.leading)
        case .trailing:
            moneyMarks(.trailing)
        }
    }

    private func moneyMarks(_ position: AxisMarkPosition) -> some AxisContent {
        AxisMarks(position: position, values: scale.ticks) { value in
            AxisGridLine().foregroundStyle(Theme.fill)
            AxisValueLabel { Text((value.as(Double.self) ?? 0).compactMoney(style.currency)) }
        }
    }

    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        switch style.xAxis {
        case .hidden:
            AxisMarks { _ in }
        case .automatic(let count):
            AxisMarks(values: .automatic(desiredCount: count)) { _ in AxisValueLabel() }
        case .months(let count):
            AxisMarks(values: .automatic(desiredCount: count)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(Theme.secondary)
            }
        case .monthsAndYears:
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(Self.monthOrYear(date)) }
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
            }
        case .nowAndYears:
            AxisMarks(values: yearTicks) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date == points.first?.day ? "Now" : date.formatted(.dateTime.year()))
                    }
                }
                .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// The first point, then January 1 of each later year in the series.
    private var yearTicks: [Date] {
        guard let first = points.first?.day, let end = points.last?.day else { return [] }
        let last = max(end, dashed.last?.day ?? end)
        let calendar = Calendar(identifier: .gregorian)
        let firstYear = calendar.component(.year, from: first) + 1
        let years = firstYear...max(calendar.component(.year, from: last), firstYear)
        // A year label within four months of "Now" would overlap it.
        let gap: TimeInterval = 120 * 86_400
        return [first] + years.compactMap { calendar.date(from: DateComponents(year: $0, month: 1, day: 1)) }
            .filter { $0 <= last && $0.timeIntervalSince(first) > gap }
    }

    /// "Nov" or, for January, "2027".
    private static func monthOrYear(_ date: Date) -> String {
        Calendar(identifier: .gregorian).component(.month, from: date) == 1
            ? date.formatted(.dateTime.year()) : date.formatted(.dateTime.month(.abbreviated))
    }
}

/// Lets VoiceOver read the series point by point and play it as an audio graph.
private struct TimeSeriesDescriptor: AXChartDescriptorRepresentable {
    let points: [ValuePoint]
    let currency: String?

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let first = points.first?.day.timeIntervalSince1970 ?? 0
        let last = points.last?.day.timeIntervalSince1970 ?? 1
        let currency = currency
        let xAxis = AXNumericDataAxisDescriptor(title: "Date", range: first...max(last, first + 1), gridlinePositions: []) {
            Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted)
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Value", range: (values.min() ?? 0)...max(values.max() ?? 1, (values.min() ?? 0) + 1), gridlinePositions: []
        ) { $0.wholeMoney(currency) }
        let series = AXDataSeriesDescriptor(name: "Value", isContinuous: true, dataPoints: points.map {
            AXDataPoint(x: $0.day.timeIntervalSince1970, y: $0.value)
        })
        return AXChartDescriptor(title: nil, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
