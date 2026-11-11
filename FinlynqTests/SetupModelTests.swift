import Testing
@testable import Finlynq

struct SetupModelTests {
    @Test func stepsAdvanceAndSkip() {
        var model = SetupModel()
        #expect(model.step == .currency)
        #expect(model.previous == nil)
        #expect(model.progress == "Step 1 of 4")

        model.advance()
        #expect(model.step == .accounts)
        #expect(model.previous == .currency)

        // Skip moves on the same way, without saving the step.
        model.advance()
        #expect(model.step == .importData)
        model.back()
        #expect(model.step == .accounts)

        model.advance()
        model.advance()
        #expect(model.step == .budget)
        #expect(model.progress == "Step 4 of 4")
        #expect(!model.isFinished)

        model.advance()
        #expect(model.isFinished)
        #expect(model.step == .budget, "the last step stays put once the flow is finished")
    }

    @Test func backStopsAtTheFirstStep() {
        var model = SetupModel()
        model.back()
        #expect(model.step == .currency)
    }

    @Test func budgetSeedsKeepPresetOrderAndSkipZero() {
        var model = SetupModel()
        #expect(model.budgetSeeds.map(\.name) == SetupModel.budgetPresets.map(\.name))
        model.budget["Groceries"] = 0
        model.budget["Utilities"] = 99.5
        let seeds = model.budgetSeeds
        #expect(!seeds.map(\.name).contains("Groceries"))
        #expect(seeds.last?.name == "Utilities")
        #expect(seeds.last?.amount == 99.5)
    }
}
