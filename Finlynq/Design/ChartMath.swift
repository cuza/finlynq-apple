import Foundation

/// Pure helpers behind the charts: downsampling, the Y scale and the nearest point under the pointer.
nonisolated enum ChartMath {
    /// At most `limit` items: the first and the last, and between them the lowest and the highest item of each of
    /// `(limit - 2) / 2` equal buckets, in their original order, so peaks and steps survive. Shorter input comes back as is.
    static func downsample<T>(_ items: [T], limit: Int, value: (T) -> Double) -> [T] {
        let limit = max(limit, 4)
        guard items.count > limit else { return items }
        let inner = items.count - 2
        let buckets = (limit - 2) / 2
        var kept = [items[0]]
        kept.reserveCapacity(limit)
        for bucket in 0..<buckets {
            let start = 1 + bucket * inner / buckets
            let end = 1 + (bucket + 1) * inner / buckets
            guard start < end else { continue }
            var low = start
            var high = start
            for index in start..<end {
                let current = value(items[index])
                if current < value(items[low]) { low = index }
                if current > value(items[high]) { high = index }
            }
            kept.append(items[min(low, high)])
            if low != high { kept.append(items[max(low, high)]) }
        }
        kept.append(items[items.count - 1])
        return kept
    }

    /// A Y axis range on round numbers, with `step` between gridlines.
    struct Scale: Equatable {
        let lower: Double
        let upper: Double
        let step: Double

        var domain: ClosedRange<Double> { lower...upper }
        /// The gridline values from the bottom to the top.
        var ticks: [Double] { Array(stride(from: lower, through: upper + step / 2, by: step)) }
    }

    /// Round bounds around `values`, split into about `intervals` steps of 1, 2, 2.5 or 5 times a power of ten.
    /// The next smaller step replaces it when it gives tighter bounds in at most `intervals + 2` steps, so the data
    /// fills more of the height. The bounds are multiples of the step, so zero is inside only when the values reach
    /// or cross it, or the lowest value is less than one step above it (positive values never get a negative bound,
    /// and the reverse).
    static func yScale(_ values: [Double], intervals: Int = 4) -> Scale {
        let finite = values.filter(\.isFinite)
        guard var low = finite.min(), var high = finite.max() else { return Scale(lower: 0, upper: 1, step: 1) }
        if low == high {
            let pad = low == 0 ? 1 : abs(low) * 0.1
            low = low > 0 ? max(low - pad, 0) : low - pad
            high = high < 0 ? min(high + pad, 0) : high + pad
        }
        let intervals = max(intervals, 1)
        let step = niceStep((high - low) / Double(intervals))
        let scale = Scale(lower: (low / step).rounded(.down) * step, upper: (high / step).rounded(.up) * step, step: step)
        let smaller = smallerStep(step)
        let tight = Scale(lower: (low / smaller).rounded(.down) * smaller, upper: (high / smaller).rounded(.up) * smaller, step: smaller)
        let fits = ((tight.upper - tight.lower) / smaller).rounded() <= Double(intervals + 2)
        return fits && tight.upper - tight.lower < scale.upper - scale.lower ? tight : scale
    }

    /// The nice step just below `step`: 5 for 10, 2.5 for 5, 2 for 2.5, 1 for 2, 0.5 for 1.
    static func smallerStep(_ step: Double) -> Double {
        let magnitude = pow(10, (log10(step)).rounded(.down))
        let fraction = (step / magnitude * 10).rounded() / 10
        let nice: Double = fraction >= 10 ? 5 : fraction >= 5 ? 2.5 : fraction >= 2.5 ? 2 : fraction >= 2 ? 1 : 0.5
        return nice * magnitude
    }

    /// The smallest of 1, 2, 2.5, 5 or 10 times a power of ten that is at least `raw`.
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let fraction = raw / magnitude
        let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
        return nice * magnitude
    }

    /// The index of the value in `sorted` (ascending) closest to `target`, by binary search. Ties go to the earlier one.
    static func nearest(_ sorted: [Double], to target: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < target { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return 0 }
        if low == sorted.count { return sorted.count - 1 }
        return target - sorted[low - 1] <= sorted[low] - target ? low - 1 : low
    }
}
