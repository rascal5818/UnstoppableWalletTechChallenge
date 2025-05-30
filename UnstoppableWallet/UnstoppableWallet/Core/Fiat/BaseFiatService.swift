import Combine
import Foundation
import MarketKit
import RxSwift

class BaseFiatService {
    private var disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    private var queue = DispatchQueue(label: "\(AppConfig.label).base-fiat-service", qos: .userInitiated)

    private let switchService: AmountTypeSwitchService
    private let currencyManager: CurrencyManager
    private let marketKit: MarketKit.Kit

    private var price: Decimal?

    private var appValueKind: AppValue.Kind?
    var token: Token? { appValueKind?.token }

    private let updatedSubject = PassthroughSubject<Void, Never>()

    var currency: Currency {
        currencyManager.baseCurrency
    }

    init(switchService: AmountTypeSwitchService, currencyManager: CurrencyManager, marketKit: MarketKit.Kit) {
        self.switchService = switchService
        self.currencyManager = currencyManager
        self.marketKit = marketKit

        subscribe(disposeBag, switchService.amountTypeObservable) { [weak self] _ in self?.updatedSubject.send() }
    }

    private func sync(coinPrice: CoinPrice?) {
        if let coinPrice, !coinPrice.expired {
            if price != coinPrice.value {
                sync(price: coinPrice.value)
            }
        } else {
            sync(price: nil)
        }
    }

    private func sync(price: Decimal?) {
        guard self.price != price else {
            return
        }
        self.price = price
        updatedSubject.send()
    }

    private func fetchRate(coin: Coin, subscribe: Bool) {
        sync(coinPrice: marketKit.coinPrice(coinUid: coin.uid, currencyCode: currency.code))

        if subscribe {
            marketKit.coinPricePublisher(coinUid: coin.uid, currencyCode: currency.code)
                .sink { [weak self] coinPrice in
                    self?.sync(coinPrice: coinPrice)
                }
                .store(in: &cancellables)
        }
    }
}

extension BaseFiatService {
    func set(token: Token?) {
        set(appValueKind: token.flatMap { .token(token: $0) })
    }

    func set(appValueKind: AppValue.Kind?) {
        self.appValueKind = appValueKind

        cancellables = Set()
        var fetching = true

        if let appValueKind {
            switch appValueKind {
            case let .token(token):
                fetchRate(coin: token.coin, subscribe: !token.isCustom)
            default:
                if let coin = appValueKind.coin {
                    fetchRate(coin: coin, subscribe: false)
                } else {
                    fetching = false
                }
            }
        } else {
            fetching = false
        }

        if !fetching {
            sync(price: nil)
        }
    }
}

extension BaseFiatService {
    private func currencyAmountInfo(amount: Decimal) -> AmountInfo? {
        guard let price else {
            return nil
        }
        return .currencyValue(currencyValue: CurrencyValue(currency: currency, value: amount * price))
    }

    private func coinAmountInfo(amount: Decimal) -> AmountInfo? {
        appValueKind.map { .appValue(appValue: AppValue(kind: $0, value: amount)) }
    }

    private func amountInfo(amount: Decimal, type: AmountTypeSwitchService.AmountType) -> AmountInfo? {
        switch type {
        case .coin: return coinAmountInfo(amount: amount)
        case .currency: return currencyAmountInfo(amount: amount)
        }
    }

    func primaryAmountInfo(amount: Decimal) -> AmountInfo? {
        amountInfo(amount: amount, type: switchService.amountType)
    }

    func secondaryAmountInfo(amount: Decimal) -> AmountInfo? {
        amountInfo(amount: amount, type: !switchService.amountType)
    }
}
