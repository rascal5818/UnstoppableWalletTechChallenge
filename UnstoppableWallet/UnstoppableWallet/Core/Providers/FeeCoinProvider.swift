import MarketKit

class FeeCoinProvider {
    private let marketKit: Kit

    init(marketKit: Kit) {
        self.marketKit = marketKit
    }
}

extension FeeCoinProvider {
    func feeToken(token: Token) -> Token? {
        switch token.type {
        case .eip20:
            let query = TokenQuery(blockchainType: token.blockchainType, tokenType: .native)
            return try? marketKit.token(query: query)
        default:
            return nil
        }
    }
}
