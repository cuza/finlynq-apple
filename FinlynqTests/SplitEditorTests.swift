import Testing
@testable import Finlynq

struct SplitEditorTests {
    @Test func balancedOnlyWhenSumsMatch() {
        #expect(SplitDraft.isBalanced(total: -142.80, amounts: [112.80, 30.00]))
        #expect(!SplitDraft.isBalanced(total: -142.80, amounts: [112.80, 30.01]))
        #expect(!SplitDraft.isBalanced(total: 142.80, amounts: [112.79, 30.00]))
        #expect(!SplitDraft.isBalanced(total: 142.80, amounts: []))
    }

    @Test func floatingPointSumsStillBalance() {
        #expect(SplitDraft.isBalanced(total: 0.3, amounts: [0.1, 0.2]))
    }

    @Test func inputsCarryTheParentSign() {
        let drafts = [SplitDraft(categoryId: 1, amount: 112.80, note: "a"), SplitDraft(categoryId: 2, amount: 30, note: "")]
        #expect(SplitDraft.inputs(drafts, total: -142.80).map(\.amount) == [-112.80, -30])
        #expect(SplitDraft.inputs(drafts, total: 142.80).map(\.amount) == [112.80, 30])
    }
}
