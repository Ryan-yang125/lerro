import Foundation

/// Account balance reported by `GET /user/balance`.
public struct DeepSeekBalance: Equatable, Sendable {
    public var isAvailable: Bool
    /// CNY when the account has a CNY balance, otherwise the first reported currency.
    public var total: Decimal
    /// "CNY" or "USD".
    public var currencyCode: String

    public init(isAvailable: Bool, total: Decimal, currencyCode: String) {
        self.isAvailable = isAvailable
        self.total = total
        self.currencyCode = currencyCode
    }

    public var isEmpty: Bool {
        !isAvailable || total <= 0
    }

    /// Parses the response body of `GET /user/balance`; nil when the shape is unrecognized.
    public static func parse(_ data: Data) -> DeepSeekBalance? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return nil
        }
        let infos = response.balanceInfos
        guard let info = infos.first(where: { $0.currency.uppercased() == "CNY" }) ?? infos.first else {
            return DeepSeekBalance(isAvailable: response.isAvailable, total: 0, currencyCode: "CNY")
        }
        guard let total = Decimal(
            string: info.totalBalance.trimmingCharacters(in: .whitespacesAndNewlines),
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return nil
        }
        return DeepSeekBalance(
            isAvailable: response.isAvailable,
            total: total,
            currencyCode: info.currency.uppercased()
        )
    }

    private struct Response: Decodable {
        struct Info: Decodable {
            let currency: String
            let totalBalance: String

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance = "total_balance"
            }
        }

        let isAvailable: Bool
        let balanceInfos: [Info]

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }
}

public enum DeepSeekLinks {
    public static let platform = URL(string: "https://platform.deepseek.com")!
    public static let topUp = URL(string: "https://platform.deepseek.com/top_up")!
    public static let apiKeys = URL(string: "https://platform.deepseek.com/api_keys")!
}
