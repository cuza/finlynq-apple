import Foundation

/// Picks the account for a Wallet card name such as "Visa Rewards ••1234".
nonisolated enum CardMapping {
    /// The account id for a card, or nil when nothing matches or two accounts tie, so the purchase waits for the
    /// user to pick.
    static func account(for cardName: String, mappings: [String: Int], accounts: [Account]) -> Int? {
        match(for: cardName, mappings: mappings, accounts: accounts)?.id
    }

    /// Tries, in order: the saved mapping for this exact card name; the one saved card or open account (name, alias
    /// or note) with the card's last four digits; the account with the longest name inside the card name.
    /// `permanent` is true for the first two, which are safe to save for the card; a name guess is used once only.
    static func match(for cardName: String, mappings: [String: Int], accounts: [Account]) -> (id: Int, permanent: Bool)? {
        if let id = mappings[cardName] { return (id, true) }
        let open = accounts.filter { !$0.archived && !$0.isInvestment }
        if let digits = lastFour(cardName) {
            let saved = Set(mappings.filter { lastFour($0.key) == digits }.values)
            if saved.count == 1, let id = saved.first { return (id, true) }
            // A note often holds a year ("opened 2019"), so a note's 19xx or 20xx never counts as last four digits.
            let isYear = (1900...2099).contains(Int(digits) ?? 0)
            let named = open.filter { account in
                let fields = [account.name, account.alias] + (isYear ? [] : [account.note])
                return fields.contains { $0.map(words)?.contains(digits) == true }
            }
            if named.count == 1 { return (named[0].id, true) }
        }
        let card = cardName.lowercased()
        let byName = open.compactMap { account -> (id: Int, length: Int)? in
            let names = [account.name, account.alias].compactMap { $0?.lowercased() }.filter { !$0.isEmpty && card.contains($0) }
            return names.map(\.count).max().map { (account.id, $0) }
        }
        guard let longest = byName.map(\.length).max() else { return nil }
        let best = byName.filter { $0.length == longest }
        return best.count == 1 ? (best[0].id, false) : nil
    }

    /// The last four-digit word, e.g. "1234" in "Visa ••1234". Digits inside a longer number or word don't count.
    static func lastFour(_ text: String) -> String? {
        words(text).last { $0.count == 4 && $0.allSatisfy { ("0"..."9").contains($0) } }
    }

    /// Runs of letters and digits.
    private static func words(_ text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}
