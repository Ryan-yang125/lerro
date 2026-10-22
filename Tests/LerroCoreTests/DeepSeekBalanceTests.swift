import Foundation
import Testing
@testable import LerroCore

@Suite("DeepSeek balance")
struct DeepSeekBalanceTests {
    @Test("Parses a CNY balance from the official response")
    func parsesCNY() throws {
        let balance = try #require(DeepSeekBalance.parse(Data(#"""
        {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"8.42","granted_balance":"1.00","topped_up_balance":"7.42"}]}
        """#.utf8)))

        #expect(balance == DeepSeekBalance(isAvailable: true, total: Decimal(string: "8.42")!, currencyCode: "CNY"))
        #expect(!balance.isEmpty)
    }

    @Test("Prefers CNY over other currencies and falls back to the first entry")
    func currencyPreference() throws {
        let both = try #require(DeepSeekBalance.parse(Data(#"""
        {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"3.00"},{"currency":"CNY","total_balance":"20.00"}]}
        """#.utf8)))
        #expect(both.currencyCode == "CNY")
        #expect(both.total == 20)

        let usdOnly = try #require(DeepSeekBalance.parse(Data(#"""
        {"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"3.50"}]}
        """#.utf8)))
        #expect(usdOnly.currencyCode == "USD")
        #expect(usdOnly.total == Decimal(string: "3.5")!)
    }

    @Test("A zero or unavailable balance is empty")
    func emptiness() throws {
        let zero = try #require(DeepSeekBalance.parse(Data(#"""
        {"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0.00"}]}
        """#.utf8)))
        #expect(zero.isEmpty)

        let none = try #require(DeepSeekBalance.parse(Data(#"{"is_available":false,"balance_infos":[]}"#.utf8)))
        #expect(none.isEmpty)
        #expect(none.total == 0)
        #expect(none.currencyCode == "CNY")

        #expect(DeepSeekBalance(isAvailable: false, total: 5, currencyCode: "CNY").isEmpty)
        #expect(DeepSeekBalance(isAvailable: true, total: 0.01, currencyCode: "CNY").isEmpty == false)
    }

    @Test("Unrecognized bodies return nil")
    func rejectsMalformedBodies() {
        #expect(DeepSeekBalance.parse(Data("not-json".utf8)) == nil)
        #expect(DeepSeekBalance.parse(Data("{}".utf8)) == nil)
        #expect(DeepSeekBalance.parse(Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"abc"}]}"#.utf8)) == nil)
    }

    @Test("Links point at the DeepSeek platform")
    func links() {
        #expect(DeepSeekLinks.platform.absoluteString == "https://platform.deepseek.com")
        #expect(DeepSeekLinks.topUp.absoluteString == "https://platform.deepseek.com/top_up")
        #expect(DeepSeekLinks.apiKeys.absoluteString == "https://platform.deepseek.com/api_keys")
    }
}
