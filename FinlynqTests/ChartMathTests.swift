import Foundation
import Testing
@testable import Finlynq

struct ChartMathTests {
    // MARK: Downsampling

    @Test func shortSeriesComeBackUnchanged() {
        let values = [3.0, 1, 2]
        #expect(ChartMath.downsample(values, limit: 10) { $0 } == values)
    }

    @Test func downsamplingKeepsTheEndpointsAndStaysUnderTheLimit() {
        let values = (0..<2_000).map { sin(Double($0) / 50) * 100 + Double($0) }
        for limit in [4, 5, 50, 333, 1_000] {
            let kept = ChartMath.downsample(Array(values.indices), limit: limit) { values[$0] }
            #expect(kept.count <= limit)
            #expect(kept.first == 0)
            #expect(kept.last == values.count - 1)
            #expect(zip(kept, kept.dropFirst()).allSatisfy { $0 < $1 }, "strictly increasing, no repeats")
        }
    }

    @Test func tinyLimitsAreClampedToFour() {
        let values = (0..<100).map(Double.init)
        for limit in [-3, 0, 1, 2, 3] {
            let kept = ChartMath.downsample(Array(values.indices), limit: limit) { values[$0] }
            #expect(kept.count <= 4)
            #expect(kept.first == 0 && kept.last == 99)
        }
    }

    @Test func oneMoreThanTheLimitIsReduced() {
        for limit in [4, 10, 101] {
            let values = (0...limit).map { Double($0 % 7) }
            let kept = ChartMath.downsample(Array(values.indices), limit: limit) { values[$0] }
            #expect(kept.count <= limit)
            #expect(kept.first == 0 && kept.last == limit)
            #expect(zip(kept, kept.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    @Test func downsamplingKeepsPeaksAndDips() {
        // A year of daily balances with a one-day spike and a one-day dip, reduced to 60 points.
        var values = Array(repeating: 1_000.0, count: 365)
        values[100] = 9_000
        values[250] = -4_000
        let kept = ChartMath.downsample(Array(values.indices), limit: 60) { values[$0] }
        #expect(kept.contains(100))
        #expect(kept.contains(250))
        #expect(kept.map { values[$0] }.max() == 9_000)
        #expect(kept.map { values[$0] }.min() == -4_000)
    }

    @Test func downsamplingKeepsBothSidesOfAStep() {
        let values = (0..<500).map { $0 < 321 ? 5_000.0 : 15_000 }
        let kept = ChartMath.downsample(Array(values.indices), limit: 40) { values[$0] }
        #expect(kept.contains { values[$0] == 5_000 && $0 > 300 })
        #expect(kept.contains { values[$0] == 15_000 && $0 < 340 })
    }

    // MARK: Y scale

    @Test func valuesFarFromZeroDoNotIncludeIt() {
        let scale = ChartMath.yScale([171_770, 178_190, 184_250], intervals: 2)
        #expect(scale.lower > 0)
        #expect(scale.lower <= 171_770)
        #expect(scale.upper >= 184_250)
    }

    @Test func valuesThatCrossZeroIncludeIt() {
        let scale = ChartMath.yScale([-1_632_221, -267_643, 84_934, 424_498])
        #expect(scale.lower < 0 && scale.upper > 0)
        #expect(scale.ticks.contains(0))
    }

    @Test func valuesThatReachZeroStartAtZero() {
        let scale = ChartMath.yScale([48_548, 30_000, 12_000, 0])
        #expect(scale.lower == 0)
    }

    @Test func boundsAreRoundAndCoverTheData() {
        // The user's Home chart: about $4K to $36K with three labels gives $0, $20K, $40K.
        let home = ChartMath.yScale([4_100, 16_987, 36_200], intervals: 2)
        #expect(home == ChartMath.Scale(lower: 0, upper: 40_000, step: 20_000))
        #expect(home.ticks == [0, 20_000, 40_000])
        let scale = ChartMath.yScale([1_234, 1_877], intervals: 4)
        #expect(scale == ChartMath.Scale(lower: 1_200, upper: 2_000, step: 200))
    }

    @Test func negativeValuesStayBelowZero() {
        let scale = ChartMath.yScale([-90_500, -80_250])
        #expect(scale.upper < 0)
        #expect(scale.lower <= -90_500)
    }

    @Test func aFlatSeriesStillGetsARange() {
        let scale = ChartMath.yScale([500, 500])
        #expect(scale.lower < 500 && scale.upper > 500)
        #expect(scale.lower >= 0)
        #expect(ChartMath.yScale([]).domain == 0...1)
        let single = ChartMath.yScale([1_234])
        #expect(single.lower < 1_234 && single.upper > 1_234 && single.lower >= 0)
        let zeros = ChartMath.yScale([0, 0])
        #expect(zeros.lower <= 0 && zeros.upper > 0)
        let negative = ChartMath.yScale([-800, -800, -800])
        #expect(negative.lower < -800 && negative.upper > -800 && negative.upper <= 0)
    }

    /// The share of the height between the lowest and highest value.
    private func fill(_ low: Double, _ high: Double, intervals: Int) -> Double {
        let scale = ChartMath.yScale([low, high], intervals: intervals)
        return (high - low) / (scale.upper - scale.lower)
    }

    @Test func aSmallerStepTightensTheRange() {
        // 0.9 to 2.1 in two intervals: a step of 1 (0 to 3) leaves 40%; 0.5 (0.5 to 2.5) fills 60%.
        #expect(ChartMath.yScale([0.9, 2.1], intervals: 2) == ChartMath.Scale(lower: 0.5, upper: 2.5, step: 0.5))
        #expect(ChartMath.yScale([171_770, 184_250], intervals: 2) == ChartMath.Scale(lower: 170_000, upper: 185_000, step: 5_000))
        // The Mac Home fixture keeps two-million steps: one-million steps would need five intervals.
        let fixture = ChartMath.yScale([-3_500_991, 158_336], intervals: 2)
        #expect(fixture == ChartMath.Scale(lower: -4_000_000, upper: 2_000_000, step: 2_000_000))
        #expect(fill(0.9, 2.1, intervals: 2) >= 0.6)
        #expect(fill(171_770, 184_250, intervals: 2) >= 0.6)
        #expect(fill(-3_500_991, 158_336, intervals: 2) >= 0.6)
        #expect(fill(4_100, 36_200, intervals: 2) >= 0.6)
    }

    @Test func macHomeScalesFillHalfTheHeightAndUseFewTicks() {
        // Two intervals, as on the Mac Home chart, over spans from 10 to a million at many offsets.
        var generator = SystemRandomNumberGenerator()
        var fills: [Double] = []
        for _ in 0..<5_000 {
            let low = Double.random(in: -1_000_000...1_000_000, using: &generator)
            let high = low + pow(10, Double.random(in: 1...6, using: &generator))
            let scale = ChartMath.yScale([low, high], intervals: 2)
            #expect(scale.lower <= low && scale.upper >= high)
            #expect(((scale.upper - scale.lower) / scale.step).rounded() <= 4)
            fills.append((high - low) / (scale.upper - scale.lower))
        }
        fills.sort()
        #expect(fills[0] >= 0.5)
        #expect(fills[fills.count / 2] >= 0.65)
    }

    @Test func smallerSteps() {
        #expect(ChartMath.smallerStep(10) == 5)
        #expect(ChartMath.smallerStep(5_000) == 2_500)
        #expect(ChartMath.smallerStep(250) == 200)
        #expect(ChartMath.smallerStep(2) == 1)
        #expect(ChartMath.smallerStep(1_000_000) == 500_000)
    }

    @Test func niceSteps() {
        #expect(ChartMath.niceStep(16_000) == 20_000)
        #expect(ChartMath.niceStep(1_000) == 1_000)
        #expect(ChartMath.niceStep(2_300) == 2_500)
        #expect(ChartMath.niceStep(0.03) == 0.05)
        #expect(ChartMath.niceStep(7_000) == 10_000)
    }

    // MARK: Nearest point

    @Test func nearestFindsTheClosestValue() {
        let positions: [Double] = [0, 10, 20, 30]
        #expect(ChartMath.nearest(positions, to: -5) == 0)
        #expect(ChartMath.nearest(positions, to: 4) == 0)
        #expect(ChartMath.nearest(positions, to: 5) == 0)  // a tie goes to the earlier point
        #expect(ChartMath.nearest(positions, to: 6) == 1)
        #expect(ChartMath.nearest(positions, to: 20) == 2)
        #expect(ChartMath.nearest(positions, to: 99) == 3)
        #expect(ChartMath.nearest([], to: 1) == nil)
        #expect(ChartMath.nearest([7], to: 100) == 0)
    }

    @Test func nearestMatchesALinearScan() {
        let positions = (0..<1_000).map { Double($0 * $0 % 977) }.sorted()
        for target in stride(from: -10.0, through: 990, by: 3.7) {
            let index = ChartMath.nearest(positions, to: target) ?? -1
            let best = positions.map { abs($0 - target) }.min() ?? 0
            #expect(abs(positions[index] - target) == best)
        }
    }
}
