import SwiftUI

/// Picks an SF Symbol and colour from free-text category and account names.
enum Icons {
    // ponytail: keyword match on names; add an icon field if Finlynq ever stores one per category.
    private struct Entry {
        let keys: [String]
        let symbol: String
        let color: Color

        init(_ keys: [String], _ symbol: String, _ color: Color) {
            self.keys = keys
            self.symbol = symbol
            self.color = color
        }
    }

    /// In priority order: the first entry with a matching key wins. A key matches a word that starts with it; a key
    /// ending in a space matches only that whole word ("car " is not "card", "pet " is not "petrol").
    private static let categories: [Entry] = [
        Entry(["grocer", "supermarket"], "cart.fill", .green),
        Entry(["dining", "restaurant", "food", "coffee", "takeout"], "fork.knife", .orange),
        Entry(["fuel", "gas ", "gasoline", "petrol"], "fuelpump.fill", .red),
        Entry(["transit", "transport", "taxi", "uber", "parking"], "bus.fill", .blue),
        Entry(["health", "medical", "pharma", "dental", "doctor", "personal care"], "cross.case.fill", .pink),
        Entry(["childcare", "child", "kid ", "kids ", "baby"], "figure.and.child.holdhands", .orange),
        Entry(["car ", "cars ", "carwash", "auto ", "automotive", "vehicle"], "car.fill", .indigo),
        Entry(["rent", "mortgage", "housing", "home"], "house.fill", .brown),
        Entry(["utilit", "electric", "hydro", "water"], "bolt.fill", .yellow),
        Entry(["software", "hosting", "saas", "cloud"], "server.rack", .cyan),
        Entry(["internet", "phone", "mobile", "telecom"], "wifi", .cyan),
        Entry(["insurance"], "shield.fill", .teal),
        Entry(["fitness", "gym", "sport"], "figure.run", .mint),
        Entry(["entertain", "movie", "music", "stream", "game"], "tv.fill", .purple),
        Entry(["subscription"], "repeat", .purple),
        Entry(["travel", "flight", "hotel", "vacation"], "airplane", .blue),
        Entry(["shop", "cloth", "amazon", "retail"], "bag.fill", .pink),
        Entry(["gift", "donation", "charity"], "gift.fill", .red),
        Entry(["educat", "school", "tuition", "book ", "books ", "bookstore"], "book.fill", .indigo),
        Entry(["pet ", "pets "], "pawprint.fill", .brown),
        Entry(["tax"], "building.columns.fill", .gray),
        Entry(["fee ", "fees ", "bank charge"], "creditcard.trianglebadge.exclamationmark", .gray),
        Entry(["interest", "loan"], "percent", .gray),
        Entry(["salary", "payroll", "wage", "paycheck"], "briefcase.fill", .green),
        Entry(["dividend", "invest"], "chart.line.uptrend.xyaxis", .purple)
    ]

    /// The icon for a category no key matches, on every screen.
    static let fallback = ("tag.fill", Color.gray)

    static func transaction(_ transaction: Transaction) -> (String, Color) {
        if transaction.isTransfer || transaction.categoryType == "R" { return ("arrow.left.arrow.right", .blue) }
        if transaction.portfolioHoldingId != nil { return ("chart.line.uptrend.xyaxis", .purple) }
        return category(transaction.categoryName)
    }

    /// Symbol and colour for a category name, or `fallback` when no key matches.
    static func category(_ name: String?) -> (String, Color) { match(name) ?? fallback }

    /// Two arrows for a transfer category (type R), otherwise the icon its name picks.
    static func category(_ name: String?, type: String) -> (String, Color) {
        type == "R" ? ("arrow.left.arrow.right", .blue) : category(name)
    }

    static func category(_ category: Category) -> (String, Color) { Self.category(category.name, type: category.type) }

    /// The first entry with a key that starts a word of the name. "Parent" doesn't match "rent", and
    /// "Childcare" doesn't match "car".
    private static func match(_ name: String?) -> (String, Color)? {
        let words = (name ?? "").lowercased().split { !$0.isLetter }
        // A space around each word, so " " + key only matches at the start of a word, also for two-word keys,
        // and a key ending in a space only matches a whole word.
        let text = " " + words.joined(separator: " ") + " "
        return categories.first(where: { $0.keys.contains { text.contains(" " + $0) } }).map { ($0.symbol, $0.color) }
    }

    /// Tile symbol and colour for a bill: a car or banknote for a loan, a TV for streaming, a bolt for utilities,
    /// else the category's icon (or the fallback).
    static func bill(name: String, category: String?, isLoan: Bool) -> (symbol: String, tint: Color) {
        let text = "\(name) \(category ?? "")".lowercased()
        if isLoan { return (text.contains("car") || text.contains("auto") ? "car.fill" : "banknote.fill", .orange) }
        let streaming = ["netflix", "stream", "disney", "prime video", "crave", "hulu", "youtube", "apple tv"]
        if streaming.contains(where: text.contains) { return ("tv", .purple) }
        let utilities = ["utilit", "hydro", "electric", "power", "water"]
        if utilities.contains(where: text.contains) { return ("bolt.fill", .yellow) }
        return Self.category(category)
    }

    static func account(group: String, isLiability: Bool, isInvestment: Bool) -> String {
        let lowered = group.lowercased()
        if isInvestment { return "chart.line.uptrend.xyaxis" }
        if lowered.contains("mortgage") { return "house.fill" }
        if lowered.contains("loan") { return "doc.text.fill" }
        if lowered.contains("credit") || isLiability { return "creditcard.fill" }
        if lowered.contains("cash") { return "banknote.fill" }
        if lowered.contains("saving") { return "dollarsign.bank.building.fill" }
        return "building.columns.fill"
    }
}
