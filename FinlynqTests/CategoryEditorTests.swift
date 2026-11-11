import Foundation
import Testing
@testable import Finlynq

struct CategoryEditorTests {
    private func category(_ id: Int, _ name: String?, type: String = "E", group: String, note: String? = nil) throws -> Finlynq.Category {
        var json: [String: Any] = ["id": id, "type": type, "group": group]
        json["name"] = name
        json["note"] = note
        return try JSONDecoder().decode(Finlynq.Category.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func nameIsRequiredAndTrimmed() {
        var draft = CategoryDraft(groups: ["Food"])
        #expect(!draft.isValid)
        draft.name = "   "
        #expect(!draft.isValid)
        draft.name = "  Pets "
        #expect(draft.isValid)
        #expect(draft.input.name == "Pets")
    }

    @Test func newCategoryStartsAsAnExpenseInTheFirstGroup() {
        let draft = CategoryDraft(groups: ["Food", "Home"])
        #expect(draft.id == nil)
        #expect(draft.type == "E")
        #expect(draft.group == "Food")
        #expect(CategoryDraft(groups: []).group == nil, "no groups yet: type a new one")
    }

    @Test func newGroupNeedsAName() {
        var draft = CategoryDraft(groups: ["Food"])
        draft.name = "Pets"
        draft.group = nil
        #expect(!draft.isValid)
        draft.newGroup = " Animals "
        #expect(draft.isValid)
        #expect(draft.input.group == "Animals")
    }

    @Test func editingPrefillsAndSendsEveryField() throws {
        let draft = CategoryDraft(try category(8486, "Groceries", type: "E", group: "Food", note: "Weekly"))
        #expect(draft.id == 8486)
        #expect(draft.name == "Groceries")
        #expect(draft.input == CategoryInput(id: 8486, name: "Groceries", type: "E", group: "Food", note: "Weekly"))
    }

    @Test func clearingTheNoteSendsAnEmptyString() throws {
        var draft = CategoryDraft(try category(1, "Rent", group: "Home", note: "Old note"))
        draft.note = "  "
        #expect(draft.input.note == "", "the server takes a string, not null, so clearing needs \"\"")
    }

    @Test func groupsAreDistinctAndSorted() throws {
        let list = [try category(1, "a", group: "Home"), try category(2, "b", group: "Food"), try category(3, "c", group: "Home")]
        #expect(CategoryDraft.groups(list) == ["Food", "Home"])
    }

    @Test func typeNamesMatchTheServerCodes() {
        #expect(CategoriesListView.kind("E") == "Expense")
        #expect(CategoriesListView.kind("I") == "Income")
        #expect(CategoriesListView.kind("R") == "Transfer")
    }
    @Test func countLineUnderTheTitle() throws {
        let list = [try category(1, "a", group: "Home"), try category(2, "b", group: "Food"), try category(3, "c", group: "Home")]
        #expect(CategoryDraft.summary(list) == "3 categories in 2 groups")
        #expect(CategoryDraft.summary([try category(1, "a", group: "Home")]) == "1 category in 1 group")
    }

    @Test func anEmptyGroupReadsOther() {
        #expect(CategoryDraft.groupName("") == "Other")
        #expect(CategoryDraft.groupName("Food") == "Food")
    }
}
