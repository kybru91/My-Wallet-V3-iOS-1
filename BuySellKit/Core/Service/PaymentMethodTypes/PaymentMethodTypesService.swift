//
//  PaymentMethodTypesService.swift
//  PlatformKit
//
//  Created by Daniel Huri on 08/04/2020.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

import DIKit
import PlatformKit
import RxRelay
import RxSwift
import ToolKit

/// The type of payment method
public enum PaymentMethodType: Equatable {

    /// A card payment method (from the user's buy data)
    case card(CardData)
    
    /// An account for an asset. Currency supports fiat
    case account(FundData)

    /// A linked account bank
    case linkedBank(LinkedBankData)
    
    /// Suggested payment methods (e.g bank-wire / card)
    case suggested(PaymentMethod)
    
    public var method: PaymentMethod.MethodType {
        switch self {
        case .card(let data):
            return .card([data.type])
        case .account(let data):
            return .funds(data.balance.base.currencyType)
        case .suggested(let method):
            return method.type
        case .linkedBank(let data):
            return .bankTransfer(data.currency.currency)
        }
    }

    public var isSuggested: Bool {
        switch self {
        case .card,
             .account,
             .linkedBank:
            return false
        case .suggested:
            return true
        }
    }
    
    var methodId: String? {
        switch self {
        case .card(let card):
            return card.identifier
        case .suggested:
            return nil
        case .linkedBank(let data):
            return data.identifier
        case .account:
            return nil
        }
    }
}

public protocol PaymentMethodTypesServiceAPI {

    /// Streams the current payment method types
    var methodTypes: Observable<[PaymentMethodType]> { get }

    /// Streams any linked card
    var cards: Observable<[CardData]> { get }

    /// Streams any linked banks
    var linkedBanks: Observable<[LinkedBankData]> { get }

    /// A `BehaviorRelay` to adjust the preferred method type
    var preferredPaymentMethodTypeRelay: BehaviorRelay<PaymentMethodType?> { get }

    /// Streams the preferred method type
    var preferredPaymentMethodType: Observable<PaymentMethodType?> { get }

    /// Fetches any linked cards and marks the given cardId as the preferred payment method
    ///
    /// - Parameter cardId: A `String` for the bank account to be preferred
    /// - Returns: A `Completable` trait indicating the action is completed
    func fetchCards(andPrefer cardId: String) -> Completable

    /// Fetches any linked banks and marks the given bankId as the preferred payment method
    ///
    /// - Parameter bankId: A `String` for the bank account to be preferred
    /// - Returns: A `Completable` trait indicating the action is completed
    func fetchLinkBanks(andPrefer bankId: String) -> Completable

    /// Clears a previously preferred payment, if needed, useful when deleting a card or linked bank.
    /// If the given id doesn't match the current payment method, this will do nothing
    func clearPreferredPaymentIfNeeded(by id: String)
}

/// A service that aggregates all the payment method types and possible methods.
final class PaymentMethodTypesService: PaymentMethodTypesServiceAPI {

    // MARK: - Exposed

    var methodTypes: Observable<[PaymentMethodType]> {
        provideMethodTypes()
    }

    var cards: Observable<[CardData]> {
        methodTypes.map { $0.cards }
    }

    var linkedBanks: Observable<[LinkedBankData]> {
        methodTypes.map { $0.linkedBanks }
    }
    
    /// Preferred payment method
    let preferredPaymentMethodTypeRelay = BehaviorRelay<PaymentMethodType?>(value: nil)
    var preferredPaymentMethodType: Observable<PaymentMethodType?> {
        Observable
            .combineLatest(
                preferredPaymentMethodTypeRelay,
                fiatCurrencyService.fiatCurrencyObservable
            )
            .flatMap(weak: self) { (self, payload) in
                let (preferredMethod, fiatCurrecy) = payload
                if let preferredMethod = preferredMethod {
                    return .just(preferredMethod)
                } else {
                    return self.methodTypes.take(1)
                        .map { (types: [PaymentMethodType]) -> [PaymentMethodType] in
                            types.filterValidForBuy(currentWalletCurrency: fiatCurrecy)
                        }
                        .map { $0.first }
                        .asObservable()
                        .catchErrorJustReturn(.none)
                }
            }
    }
    
    // MARK: - Injected

    private let enabledCurrenciesService: EnabledCurrenciesServiceAPI
    private let fiatCurrencyService: FiatCurrencyServiceAPI
    private let paymentMethodsService: PaymentMethodsServiceAPI
    private let cardListService: CardListServiceAPI
    private let balanceProvider: BalanceProviding
    private let linkedBankService: LinkedBanksServiceAPI
    private let featureConfiguring: FeatureConfiguring
    private let beneficiariesServiceUpdater: BeneficiariesServiceUpdaterAPI
    // MARK: - Setup
    
    init(enabledCurrenciesService: EnabledCurrenciesServiceAPI = resolve(),
         paymentMethodsService: PaymentMethodsServiceAPI = resolve(),
         fiatCurrencyService: FiatCurrencyServiceAPI = resolve(),
         cardListService: CardListServiceAPI = resolve(),
         balanceProvider: BalanceProviding = resolve(),
         linkedBankService: LinkedBanksServiceAPI = resolve(),
         featureConfiguring: FeatureConfiguring = resolve(),
         beneficiariesServiceUpdater: BeneficiariesServiceUpdaterAPI = resolve()) {
        self.enabledCurrenciesService = enabledCurrenciesService
        self.paymentMethodsService = paymentMethodsService
        self.fiatCurrencyService = fiatCurrencyService
        self.cardListService = cardListService
        self.balanceProvider = balanceProvider
        self.linkedBankService = linkedBankService
        self.featureConfiguring = featureConfiguring
        self.beneficiariesServiceUpdater = beneficiariesServiceUpdater
    }
        
    func fetchCards(andPrefer cardId: String) -> Completable {
        Single
            .zip(
                paymentMethodsService.paymentMethodsSingle,
                cardListService.fetchCards(),
                balanceProvider.fiatFundsBalancesSingle
            )
            .map(weak: self) { (self, payload) in
                self.merge(paymentMethods: payload.0, cards: payload.1, balances: payload.2, linkedBanks: [])
            }
            .do(onSuccess: { [weak preferredPaymentMethodTypeRelay] types in
                let card = types
                    .compactMap { type -> CardData? in
                        switch type {
                        case .card(let cardData):
                            return cardData
                        case .suggested, .account, .linkedBank:
                            return nil
                        }
                    }
                    .first
                guard let data = card else { return }
                preferredPaymentMethodTypeRelay?.accept(.card(data))
            })
            .asCompletable()
    }

    func fetchLinkBanks(andPrefer bankId: String) -> Completable {
        Single
            .zip(
                paymentMethodsService.paymentMethodsSingle,
                cardListService.cardsSingle,
                balanceProvider.fiatFundsBalancesSingle,
                linkedBankService.fetchLinkedBanks()
            )
            .map(weak: self) { (self, payload) in
                self.merge(paymentMethods: payload.0, cards: payload.1, balances: payload.2, linkedBanks: payload.3)
            }
            .map { types in
                types
                    .compactMap { type -> LinkedBankData? in
                        switch type {
                        case .linkedBank(let bankData):
                            return bankData
                        case .suggested, .account, .card:
                            return nil
                        }
                    }
                    .first(where: { $0.identifier == bankId })
            }
            .do(onSuccess: { [weak preferredPaymentMethodTypeRelay, beneficiariesServiceUpdater] linkedBank in
                guard let data = linkedBank else { return }
                beneficiariesServiceUpdater.markForRefresh()
                preferredPaymentMethodTypeRelay?.accept(.linkedBank(data))
            })
            .asCompletable()
    }

    func clearPreferredPaymentIfNeeded(by id: String) {
        if preferredPaymentMethodTypeRelay.value?.methodId == id {
            preferredPaymentMethodTypeRelay.accept(nil)
        }
    }

    // MARK: - Private
    
    private func merge(paymentMethods: [PaymentMethod],
                       cards: [CardData],
                       balances: MoneyBalancePairsCalculationStates,
                       linkedBanks: [LinkedBankData]) -> [PaymentMethodType] {
        let topCardLimit = (paymentMethods.first { $0.type.isCard })?.max
        let cardTypes = cards
            .filter { $0.state.isUsable }
            .map { card in
                var card = card
                if let limit = topCardLimit {
                    card.topLimit = limit
                }
                return card
            }
            .map { PaymentMethodType.card($0) }
        let suggestedMethods = paymentMethods
            .filter { paymentMethod -> Bool in
                switch paymentMethod.type {
                case .bankAccount,
                     .card:
                    return true
                case .bankTransfer:
                    return true
                case .funds(let currency):
                    switch currency {
                    case .crypto:
                        return true
                    case .fiat(let fiatCurrency):
                        return enabledCurrenciesService.depositEnabledFiatCurrencies.contains(fiatCurrency)
                    }
                }
            }
            .sorted()
            .map { PaymentMethodType.suggested($0) }
            
        let fundsCurrencies = Set(
            paymentMethods
                .compactMap { method -> CurrencyType? in
                    switch method.type {
                    case .funds(let currencyType):
                        return currencyType
                    default:
                        return nil
                    }
                }
        )
        
        let fundsMaxAmounts = paymentMethods
            .filter { $0.type.isFunds }
            .map { $0.max }
        
        let balances = balances.all
            .compactMap { $0.value }
            .filter { !$0.isAbsent }
            .filter { fundsCurrencies.contains($0.baseCurrency) }
            .map { balance in
                let fundTopLimit = fundsMaxAmounts.first { balance.base.currencyType == $0.currency }!
                let data = FundData(topLimit: fundTopLimit, balance: balance)
                return data
            }
            .map { PaymentMethodType.account($0) }

        let topBankTransferLimit = (paymentMethods.first { $0.type.isBankTransfer })?.max
        let activeBanks = linkedBanks.filter(\.isActive)
            .map { bank in
                var bank = bank
                if let limit = topBankTransferLimit {
                    bank.topLimit = limit
                }
                return bank
            }
            .map { PaymentMethodType.linkedBank($0) }
        
        return balances + cardTypes + activeBanks + suggestedMethods
    }

    private func provideMethodTypes() -> Observable<[PaymentMethodType]> {
        if featureConfiguring.configuration(for: .achBuyFlowEnabled).isEnabled {
            return methodTypesWithLinkedBanks()
        }
        return methodTypesWithoutLinkedBanks()
    }

    private func methodTypesWithoutLinkedBanks() -> Observable<[PaymentMethodType]> {
        Observable
            .combineLatest(
                paymentMethodsService.paymentMethods,
                cardListService.cards,
                balanceProvider.fiatFundsBalances
            )
            .map(weak: self) { (self, payload) in
                self.merge(paymentMethods: payload.0, cards: payload.1, balances: payload.2, linkedBanks: [])
            }
    }

    private func methodTypesWithLinkedBanks() -> Observable<[PaymentMethodType]> {
        Observable
            .combineLatest(
                paymentMethodsService.paymentMethods,
                cardListService.cards,
                balanceProvider.fiatFundsBalances,
                linkedBankService.linkedBanks.asObservable()
            )
            .map(weak: self) { (self, payload) in
                self.merge(paymentMethods: payload.0, cards: payload.1, balances: payload.2, linkedBanks: payload.3)
            }
    }
}

extension Array where Element == PaymentMethodType {
    
    var suggestedFunds: Set<FiatCurrency> {
        let array = compactMap { paymentMethod -> FiatCurrency? in
            guard case .suggested(let method) = paymentMethod else {
                return nil
            }
            switch method.type {
            case .bankTransfer(let currencyType):
                return FiatCurrency(code: currencyType.code)
            case .funds(let currencyType):
                guard currencyType != .fiat(.USD) else {
                    return nil
                }
                return FiatCurrency(code: currencyType.code)
            case .bankAccount, .card:
                return nil
            }
        }
        return Set(array)
    }
    
    fileprivate var cards: [CardData] {
        compactMap { paymentMethod in
            switch paymentMethod {
            case .card(let data):
                return data
            case .suggested, .account, .linkedBank:
                return nil
            }
        }
    }

    var linkedBanks: [LinkedBankData] {
        compactMap { paymentMethod in
            switch paymentMethod {
            case .linkedBank(let data):
                return data
            case .suggested, .account, .card:
                return nil
            }
        }
    }

    var accounts: [FundData] {
        compactMap { paymentMethod in
            switch paymentMethod {
            case .account(let data):
                return data
            case .suggested, .card, .linkedBank:
                return nil
            }
        }
    }
    
    /// Returns the payment methods valid for buy usage
    public func filterValidForBuy(currentWalletCurrency: FiatCurrency) -> [PaymentMethodType] {
        filter { method in
            switch method {
            case .account(let data):
                return !data.balance.base.isZero && data.balance.base.currencyType == currentWalletCurrency.currency
            case .suggested(let paymentMethod):
                switch paymentMethod.type {
                case .bankAccount:
                    return false
                case .bankTransfer:
                    return true
                case .funds(let currency):
                    return currency == currentWalletCurrency.currency
                case .card:
                    return true
                }
            case .card(let data):
                return data.state == .active
            case .linkedBank(let data):
                return data.state == .active
            }
        }
    }
}
