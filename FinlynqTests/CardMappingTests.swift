import Foundation
import Testing
@testable import Finlynq

struct CardMappingTests {
    private func account(_ id: Int, _ name: String, alias: String? = nil) -> Account {
        Account(
            id: id, type: "L", group: "Credit Cards", currency: "USD", archived: false, isInvestment: false,
            name: name, alias: alias, mode: nil, csvMappingMode: nil, note: nil
        )
    }

    private var accounts: [Account] { [account(1, "Chequing"), account(2, "Visa Rewards"), account(3, "Amex 1234")] }

    @Test func savedMappingWins() {
        #expect(CardMapping.account(for: "Visa ••9999", mappings: ["Visa ••9999": 1], accounts: accounts) == 1)
    }

    @Test func mapsByLastFour() {
        // The account named "Amex 1234" has the card's last four digits.
        #expect(CardMapping.account(for: "Gold ••1234", mappings: [:], accounts: accounts) == 3)
        // A saved mapping for another name of the same card counts too.
        #expect(CardMapping.account(for: "Debit ••5678", mappings: ["Interac 5678": 1], accounts: accounts) == 1)
    }

    @Test func mapsByAccountName() {
        #expect(CardMapping.account(for: "visa rewards ••4321", mappings: [:], accounts: accounts) == 2)
    }

    @Test func unknownCardReturnsNil() {
        #expect(CardMapping.account(for: "Debit ••5678", mappings: [:], accounts: accounts) == nil)
        #expect(CardMapping.account(for: "", mappings: [:], accounts: accounts) == nil)
    }

    @Test func onlyMappingsAndLastFourArePermanent() {
        #expect(CardMapping.match(for: "Visa ••9999", mappings: ["Visa ••9999": 1], accounts: accounts)?.permanent == true)
        #expect(CardMapping.match(for: "Gold ••1234", mappings: [:], accounts: accounts)?.permanent == true)
        #expect(CardMapping.match(for: "Visa Rewards ••4321", mappings: [:], accounts: accounts)?.permanent == false)
    }

    @Test func lastFourIsAWholeFourDigitWord() {
        #expect(CardMapping.lastFour("Visa ••1234") == "1234")
        #expect(CardMapping.lastFour("Visa 2024 ••1234") == "1234")
        #expect(CardMapping.lastFour("Card 20241109") == nil, "digits inside a longer number")
        #expect(CardMapping.lastFour("Card x1234") == nil, "digits inside a word")
        // An account note with a date doesn't match the card's last four.
        let dated = [account(1, "Chequing", alias: nil)]
        #expect(CardMapping.account(for: "Debit ••2024", mappings: [:], accounts: dated) == nil)
    }

    @Test func yearInANoteIsNotLastFour() {
        let noted = [
            Account(id: 1, type: "A", group: "Banks", currency: "USD", archived: false, isInvestment: false,
                    name: "Chequing", alias: nil, mode: nil, csvMappingMode: nil, note: "Opened 2019"),
            Account(id: 2, type: "A", group: "Banks", currency: "USD", archived: false, isInvestment: false,
                    name: "Savings", alias: nil, mode: nil, csvMappingMode: nil, note: "Card 4821")
        ]
        #expect(CardMapping.account(for: "Debit ••2019", mappings: [:], accounts: noted) == nil)
        #expect(CardMapping.account(for: "Debit ••4821", mappings: [:], accounts: noted) == 2)
    }

    @Test func longestNameWinsAndTiesReturnNil() {
        let similar = [account(1, "Visa"), account(2, "Visa Travel")]
        #expect(CardMapping.account(for: "Visa Travel ••1111", mappings: [:], accounts: similar) == 2)
        let twins = [account(1, "Visa"), account(2, "Business", alias: "Visa")]
        #expect(CardMapping.account(for: "Visa ••1111", mappings: [:], accounts: twins) == nil)
    }
}

struct ApplePayAttentionTests {
    private func purchase(_ merchant: String, _ problem: CapturedPurchase.Problem) -> CapturedPurchase {
        CapturedPurchase(
            merchant: merchant, amount: 5, currency: "USD", card: "Visa", date: "2026-11-09", capturedAt: .now, problem: problem
        )
    }

    @Test func homeListsPurchasesThatNeedTheUser() {
        #expect(HomeModel.applePayItem([]) == nil)
        #expect(HomeModel.applePayItem([purchase("Pai", .notSent)]) == nil, "these send on their own")
        let item = HomeModel.applePayItem([purchase("Pai", .notSent), purchase("Pai Northern", .account)])
        #expect(item?.title == "Apple Pay purchase waiting")
        #expect(item?.subtitle == "Pai Northern: Pick an account")
        #expect(item?.route == .applePay)
    }
}
