// swiftlint:disable force_try
import Foundation
import Testing
@testable import Finlynq

@Suite(.serialized) struct AddModelTests {
    private func client() -> APIClient {
        StubProtocol.statuses = []
        StubProtocol.requests = 0
        StubProtocol.routes = [:]
        StubProtocol.sent = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config))
    }

    private func category(_ id: Int, _ name: String, type: String = "E") -> Finlynq.Category {
        let json: [String: Any] = ["id": id, "type": type, "group": "G", "name": name]
        return try! JSONDecoder().decode(Finlynq.Category.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func row(_ id: Int, _ date: String, category: Int) -> Transaction {
        let json: [String: Any] = ["id": id, "date": date, "currency": "USD", "amount": -5, "categoryId": category]
        return try! JSONDecoder().decode(Transaction.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func body(_ index: Int = 0) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: StubProtocol.sent[index].body ?? Data()) as? [String: Any]) ?? [:]
    }

    @Test func padBuildsAmount() {
        let model = AddModel()
        for key: AmountPad.Key in [.digit(1), .digit(2), .dot, .digit(5)] { model.press(key) }
        #expect(model.amountText == "12.5")
        model.press(.dot)
        #expect(model.amountText == "12.5")
        model.press(.digit(7))
        model.press(.digit(9))
        #expect(model.amountText == "12.57")
        model.press(.backspace)
        #expect(model.amountText == "12.5")
        let empty = AddModel()
        empty.press(.dot)
        #expect(empty.amountText == "0.")
    }

    @Test func expenseIsNegative() async throws {
        let api = client()
        let model = AddModel()
        model.amountText = "12.50"
        model.accountId = 4100
        model.categoryId = 8487
        model.payee = "Cafe"
        #expect(model.canSave)
        try await model.save(api: api)
        #expect(StubProtocol.sent.count == 1)
        #expect(StubProtocol.sent[0].path == "/api/transactions")
        #expect(body()["amount"] as? Double == -12.5)
        #expect(body()["categoryId"] as? Int == 8487)
    }

    @Test func incomeIsPositive() async throws {
        let api = client()
        let model = AddModel(kind: .income)
        model.amountText = "40"
        model.accountId = 4100
        model.categoryId = 8481
        try await model.save(api: api)
        #expect(body()["amount"] as? Double == 40)
    }

    @Test func transferNeedsTwoAccounts() async throws {
        let api = client()
        let model = AddModel(kind: .transfer)
        model.amountText = "100"
        model.accountId = 4100
        model.toAccountId = 4100
        #expect(!model.canSave)
        model.toAccountId = 4101
        try await model.save(api: api)
        #expect(StubProtocol.sent[0].path == "/api/transactions/transfer")
        #expect(body()["fromAccountId"] as? Int == 4100)
        #expect(body()["toAccountId"] as? Int == 4101)
        #expect(body()["enteredAmount"] as? Double == 100)
    }

    @Test func quickCategoriesByUse() {
        let all = (1...10).map { category($0, "Cat \($0)") } + [category(50, "Salary", type: "I")]
        var recent: [Transaction] = []
        // Category n is used n times, so 10 is the most used. Category 50 is income and must not appear.
        for id in 1...10 { for index in 0..<id { recent.append(row(id * 100 + index, "2026-11-01", category: id)) } }
        recent.append(row(900, "2026-11-01", category: 50))
        // An old row is outside the 90 day window.
        for index in 0..<30 { recent.append(row(1000 + index, "2025-01-01", category: 1)) }
        let now = APIDate.parse("2026-11-09")!
        let top = AddModel.quickCategories(recent: recent, all: all, kind: .expense, now: now)
        #expect(top.map(\.id) == [10, 9, 8, 7, 6, 5, 4])
        let income = AddModel.quickCategories(recent: recent, all: all, kind: .income, now: now)
        #expect(income.map(\.id) == [50])
    }

    @Test func quickCategoriesFallBackToAlphabetical() {
        let all = [category(1, "Zoo"), category(2, "Apples"), category(3, "Mango")]
        let top = AddModel.quickCategories(recent: [row(1, "2026-11-01", category: 3)], all: all, kind: .expense,
                                           now: APIDate.parse("2026-11-09")!)
        #expect(top.map(\.id) == [3, 2, 1])
    }

    @Test func saveIsSingleFlight() async throws {
        let api = client()
        let model = AddModel()
        model.amountText = "5"
        model.accountId = 1
        model.categoryId = 2
        async let first = model.save(api: api)
        async let second = model.save(api: api)
        let sent = try await [first, second]
        // Only the call that sent reports success, so the sheet can't close on the other tap.
        #expect(sent.filter { $0 }.count == 1)
        #expect(StubProtocol.sent.count == 1)
        #expect(!model.isSaving)
    }

    @Test func buyTotalIncludesFees() async throws {
        let model = AddModel(kind: .invest)
        model.operation = .buy
        model.sharesText = "5"
        model.priceText = "372.06"
        #expect(model.investTotal == 1860.30)
        model.feesText = "1.50"
        #expect(model.investTotal == 1861.80)
        model.feesText = ""
        model.accountId = 4102
        model.holdingId = 3543
        let api = client()
        try await model.save(api: api)
        #expect(StubProtocol.sent[0].path == "/api/portfolio/operations/buy")
        #expect(body()["qty"] as? Double == 5)
        #expect(body()["totalCost"] as? Double == 1860.30)
        #expect(body()["holdingId"] as? Int == 3543)
    }

    @Test func sellSendsProceedsNetOfFees() async throws {
        let model = AddModel(kind: .invest)
        model.operation = .sell
        model.sharesText = "2"
        model.priceText = "100"
        model.feesText = "1"
        model.accountId = 4102
        model.holdingId = 3543
        let api = client()
        try await model.save(api: api)
        #expect(StubProtocol.sent[0].path == "/api/portfolio/operations/sell")
        #expect(body()["totalProceeds"] as? Double == 199)
    }

    @Test func depositWithdrawAndDividendRoutes() async throws {
        let api = client()
        let deposit = AddModel(kind: .invest)
        deposit.operation = .deposit
        deposit.amountText = "250"
        deposit.accountId = 4100
        deposit.toAccountId = 4102
        try await deposit.save(api: api)
        #expect(StubProtocol.sent[0].path == "/api/portfolio/operations/deposit")
        #expect(body(0)["sourceAccountId"] as? Int == 4100)
        #expect(body(0)["destAccountId"] as? Int == 4102)

        let dividend = AddModel(kind: .invest)
        dividend.operation = .dividend
        dividend.amountText = "12"
        dividend.accountId = 4102
        try await dividend.save(api: api)
        #expect(StubProtocol.sent[1].path == "/api/portfolio/operations/income-expense")
        #expect(body(1)["incomeType"] as? String == "dividend")
    }

    @Test func investPrefillSetsFields() {
        let sell = AddModel(kind: .expense, invest: AddModel.InvestPrefill(operation: .sell, symbol: "VTI", accountId: 4102))
        #expect(sell.kind == .invest)
        #expect(sell.operation == .sell)
        #expect(sell.accountId == 4102)
        let deposit = AddModel(kind: .expense, invest: AddModel.InvestPrefill(operation: .deposit, symbol: nil, accountId: 4102))
        #expect(deposit.toAccountId == 4102)
    }

    @Test func buttonTitleNamesAmountAndCategory() {
        let model = AddModel()
        model.amountText = "12.50"
        #expect(model.buttonTitle(currency: "USD", categoryName: "Coffee") == "Add \(12.5.money("USD")) to Coffee")
        model.amountText = ""
        #expect(model.buttonTitle(currency: "USD", categoryName: nil) == "Add expense")
    }

    @Test func numberAcceptsEitherDecimalSeparator() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        #expect(AddModel.number("12,50", locale: english) == Decimal(string: "12.5"))
        #expect(AddModel.number("12.50", locale: english) == Decimal(string: "12.5"))
        #expect(AddModel.number("12,50", locale: german) == Decimal(string: "12.5"))
        // Three digits after the locale's grouping separator is a thousand.
        #expect(AddModel.number("1,234", locale: english) == 1234)
        #expect(AddModel.number("1.234", locale: german) == 1234)
        #expect(AddModel.number("1,234.56", locale: english) == Decimal(string: "1234.56"))
        #expect(AddModel.number("1.234,56", locale: german) == Decimal(string: "1234.56"))
        #expect(AddModel.number(" 7 ", locale: english) == 7)
        for bad in ["inf", "nan", "", ".", "-5", "1e3", "12abc", String(repeating: "9", count: 400)] {
            #expect(AddModel.number(bad, locale: english) == nil, "\(bad)")
        }
    }

    @Test func amountRoundsToCents() {
        let model = AddModel()
        model.locale = Locale(identifier: "en_US")
        model.amountText = "12,50"
        #expect(model.amount == 12.5)
        // Half a cent rounds up.
        model.amountText = "12.345"
        #expect(model.amount == 12.35)
        model.amountText = "0.004"
        #expect(model.amount == nil, "rounds to zero, which can't be saved")
        model.amountText = "inf"
        #expect(model.amount == nil)
    }

    @Test func saveReportsWhetherItSent() async throws {
        let api = client()
        let model = AddModel()
        #expect(try await model.save(api: api) == false, "incomplete entry sends nothing")
        model.amountText = "5"
        model.accountId = 1
        model.categoryId = 2
        #expect(try await model.save(api: api) == true)
    }

    @Test func titleNamesTheOperation() {
        #expect(AddModel().title == "New expense")
        #expect(AddModel(kind: .transfer).title == "New transfer")
        let invest = AddModel(kind: .invest)
        #expect(invest.title == "New buy")
        invest.operation = .dividend
        #expect(invest.title == "New dividend")
    }

    @Test func didSaveBumpsRevisionAndReloadsAccounts() async throws {
        let api = client()
        StubProtocol.routes["GET /api/accounts"] = Data(#"""
        [{"id":4100,"type":"A","group":"Banks","currency":"USD","archived":false,"isInvestment":false,"name":"Chequing"}]
        """#.utf8)
        StubProtocol.routes["GET /api/categories"] = Data("[]".utf8)
        let session = Session(api: api)
        #expect(session.revision == 0)
        await session.didSave()
        #expect(session.revision == 1)
        #expect(session.accounts.map(\.id) == [4100])
    }

    @MainActor @Test func fixtureModeNeverTouchesTheKeychain() {
        var touched = 0
        let real = Keychain.calls
        let realOff = Keychain.isOff
        defer { Keychain.calls = real; Keychain.isOff = realOff }
        Keychain.calls = .init(add: { _ in touched += 1; return errSecSuccess },
                               copy: { _ in touched += 1; return nil },
                               delete: { _ in touched += 1; return errSecSuccess })
        let creds = Credentials(server: "https://example.test", username: "me", password: "pw")

        Keychain.isOff = { true }
        Keychain.save(creds)
        #expect(Keychain.load() == nil)
        Keychain.delete()
        let session = Session(api: client())
        #expect(session.savedServer == Session.defaultServer)
        #expect(session.savedUsername == "demo")
        #expect(touched == 0)

        // The same calls reach the seam when fixtures are off, so the zero above means something.
        Keychain.isOff = { false }
        Keychain.save(creds)
        _ = Keychain.load()
        Keychain.delete()
        #expect(touched == 4, "save deletes first, then adds; load copies; delete deletes")
    }

    @Test func positionDecodesNullName() throws {
        let json = Data(#"""
        [{"id":1,"accountId":4102,"name":null,"symbol":null,"assetType":"stock"},
         {"id":2,"accountId":4102,"name":null,"symbol":"VTI","assetType":"stock"},
         {"id":3,"accountId":4102,"name":"Gold","symbol":null,"assetType":"stock"}]
        """#.utf8)
        let positions = try JSONDecoder().decode([PortfolioOverview.Position].self, from: json)
        #expect(positions.map(\.label) == ["Holding", "VTI", "Gold"])
    }
}

// swiftlint:enable force_try
