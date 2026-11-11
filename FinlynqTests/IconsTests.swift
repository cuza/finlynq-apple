import Foundation
import SwiftUI
import Testing
@testable import Finlynq

/// Category icons come from whole words in the name: a key matches a word that starts with it, first entry wins.
struct IconsTests {
    @Test func childcareIsTheChildIconNotTheCarOrEducation() {
        #expect(Icons.category("Childcare & Education").0 == "figure.and.child.holdhands")
    }

    @Test func keysMatchTheStartOfAWordOnly() {
        #expect(Icons.category("Parent") == Icons.fallback, "not \"rent\"")
        #expect(Icons.category("Gas").0 == "fuelpump.fill")
        #expect(Icons.category("Groceries").0 == "cart.fill")
    }

    @Test func softwareAndHostingIsTheServer() {
        #expect(Icons.category("Software & Hosting") == ("server.rack", .cyan))
        #expect(Icons.category("SaaS").0 == "server.rack")
        #expect(Icons.category("Cloud storage").0 == "server.rack")
    }

    @Test func personalCareIsHealthNotTheCar() {
        #expect(Icons.category("Health & Personal Care").0 == "cross.case.fill")
        #expect(Icons.category("Personal care").0 == "cross.case.fill")
    }

    @Test func unknownNamesGetTheOneFallback() {
        #expect(Icons.fallback == ("tag.fill", .gray))
        #expect(Icons.category("Zzz") == Icons.fallback)
        #expect(Icons.category(nil) == Icons.fallback)
    }
    @Test func shortKeysMatchWholeWordsOnly() {
        #expect(Icons.category("Credit card fees").0 == "creditcard.trianglebadge.exclamationmark")
        #expect(Icons.category("Pet care").0 == "pawprint.fill")
        #expect(Icons.category("Petrol").0 == "fuelpump.fill")
        #expect(Icons.category("Gasoline").0 == "fuelpump.fill")
        #expect(Icons.category("Autopay") == Icons.fallback)
        #expect(Icons.category("Car payment").0 == "car.fill")
        #expect(Icons.category("Carwash").0 == "car.fill")
        #expect(Icons.category("Petty cash").0 != "pawprint.fill")
        #expect(Icons.category("Cardio").0 != "car.fill")
        #expect(Icons.category("Home insurance").0 == "house.fill")
        #expect(Icons.category("Homeowners").0 == "house.fill")
    }

    @Test func transferCategoriesAlwaysGetTheArrows() throws {
        let json = #"{"id":1,"type":"R","group":"Adjustments","name":"Opening Balance"}"#
        let transfer = try JSONDecoder().decode(Finlynq.Category.self, from: Data(json.utf8))
        #expect(Icons.category(transfer) == ("arrow.left.arrow.right", .blue))
        #expect(Icons.category("Rent", type: "E").0 == "house.fill")
    }

    @Test func billsFallBackToTheCategoryFallback() {
        #expect(Icons.bill(name: "Zzz", category: nil, isLoan: false) == (Icons.fallback.0, Icons.fallback.1))
    }
}
