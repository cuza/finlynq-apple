import Testing
@testable import Finlynq

struct CategoryBarTests {
    @Test func fractionsLeaveRemainder() {
        let amounts = [1450.0, 1042, 186, 540]
        let fractions = CategoryBar.fractions(amounts, total: 4500)
        let expected = [0.3222, 0.2316, 0.0413, 0.12]
        for (got, want) in zip(fractions, expected) { #expect(abs(got - want) < 0.0001) }
        #expect(abs(CategoryBar.remainder(amounts, total: 4500) - 0.2849) < 0.0001)
    }

    @Test func fractionsWhenOverspent() {
        #expect(CategoryBar.fractions([300, 300], total: 400) == [0.5, 0.5])
        #expect(CategoryBar.remainder([300, 300], total: 400) == 0)
    }

    @Test func fractionsWithZeroTotal() {
        #expect(CategoryBar.fractions([10, 20], total: 0) == [0, 0])
        #expect(CategoryBar.remainder([10, 20], total: 0) == 0)
    }

    @Test func negativeAmountsClampToZero() {
        #expect(CategoryBar.fractions([-50, 100], total: 200) == [0, 0.5])
    }
}
