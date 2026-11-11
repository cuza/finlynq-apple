import Foundation
import LocalAuthentication
import Testing
@testable import Finlynq

struct SettingsModelTests {
    @Test func biometryLabelNamesTheHardware() {
        #expect(Biometrics.name(for: .faceID) == "Face ID")
        #expect(Biometrics.name(for: .touchID) == "Touch ID")
        #expect(Biometrics.name(for: .opticID) == "Optic ID")
        #if os(macOS)
        #expect(Biometrics.name(for: .none) == "Password")
        #else
        #expect(Biometrics.name(for: .none) == "Passcode")
        #endif
    }

    @Test func idleLockAfterTheLimitOnly() {
        let left = Date(timeIntervalSince1970: 1_000_000)
        #expect(!Session.idleTooLong(since: left, now: left.addingTimeInterval(5 * 60), minutes: 5))
        #expect(Session.idleTooLong(since: left, now: left.addingTimeInterval(5 * 60 + 1), minutes: 5))
        #expect(!Session.idleTooLong(since: nil, now: left.addingTimeInterval(3600), minutes: 5), "never left")
        #expect(!Session.idleTooLong(since: left, now: left.addingTimeInterval(86_400), minutes: 0), "Never")
    }

    @Test func rulesRunHighestPriorityFirstThenOldest() throws {
        let json = """
        [{"id":3,"name":"c","conditions":{"all":[]},"actions":[],"isActive":true,"priority":10},
         {"id":1,"name":"a","conditions":{"all":[]},"actions":[],"isActive":true,"priority":100},
         {"id":2,"name":"b","conditions":{"all":[]},"actions":[],"isActive":true,"priority":100},
         {"id":4,"name":"d","conditions":{"all":[]},"actions":[],"isActive":false,"priority":50}]
        """
        let rules = try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
        #expect(RuleText.sorted(rules).map(\.id) == [1, 2, 4, 3])
    }

    @Test func rateLineAsQuotedAndInverted() {
        #expect(RateText.line(code: "CAD", display: "USD", rate: 0.72, inverted: false) == "1 CAD = 0.72 USD")
        #expect(RateText.line(code: "CAD", display: "USD", rate: 0.8, inverted: true) == "1 USD = 1.25 CAD")
        #expect(RateText.line(code: "CAD", display: "USD", rate: 0, inverted: false).isEmpty)
    }
}
