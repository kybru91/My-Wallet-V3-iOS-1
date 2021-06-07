// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Combine
import DIKit
import RxSwift
import ToolKit

public final class Coincore {

    // MARK: - Public Properties

    public var allAccounts: Single<AccountGroup> {
        reactiveWallet.waitUntilInitializedSingle
            .flatMap(weak: self) { (self, _) in
                Single.zip(
                    self.allAssets.map { asset in asset.accountGroup(filter: .all) }
                )
            }
            .map { accountGroups -> [SingleAccount] in
                accountGroups.map { $0.accounts }.reduce([SingleAccount](), +)
            }
            .map { accounts -> AccountGroup in
                AllAccountsGroup(accounts: accounts)
            }
    }

    // MARK: - Private Properties

    private var allAssets: [Asset] {
        [fiatAsset] + sortedCryptoAssets
    }

    private var sortedCryptoAssets: [CryptoAsset] {
        cryptoAssets.sorted(by: { $0.key < $1.key }).map { $0.value }
    }

    private let cryptoAssets: [CryptoCurrency: CryptoAsset]
    private let fiatAsset: FiatAsset
    private let reactiveWallet: ReactiveWalletAPI

    // MARK: - Setup

    init(cryptoAssets: [CryptoCurrency: CryptoAsset],
         fiatAsset: FiatAsset = FiatAsset(),
         reactiveWallet: ReactiveWalletAPI = resolve()) {
        self.cryptoAssets = cryptoAssets
        self.fiatAsset = fiatAsset
        self.reactiveWallet = reactiveWallet
    }

    /// Gives a chance for all assets to initialize themselves.
    public func initialize() -> Completable {
        var completables = cryptoAssets
            .values
            .map { asset -> Completable in
                asset.initialize()
            }
        completables.append(fiatAsset.initialize())
        return Completable.concat(completables)
    }

    public subscript(cryptoCurrency: CryptoCurrency) -> CryptoAsset? {
        guard let asset = cryptoAssets[cryptoCurrency] else {
            fatalError("Unknown crypto currency.")
        }
        return asset
    }

    /// We are looking for targets of our action.
    /// Action is considered what the source account wants to do.
    public func getTransactionTargets(
        sourceAccount: BlockchainAccount,
        action: AssetAction
    ) -> Single<[SingleAccount]> {
        switch action {
        case .swap:
            guard let cryptoAccount = sourceAccount as? CryptoAccount else {
                fatalError("Expected CryptoAccount: \(sourceAccount)")
            }
            return allAccounts
                .map(\.accounts)
                .map { (accounts) -> [SingleAccount] in
                    accounts.filter { destinationAccount -> Bool in
                        Self.getActionFilter(
                            sourceAccount: cryptoAccount,
                            destinationAccount: destinationAccount,
                            action: action
                        )
                    }
                }
        case .send:
            guard let cryptoAccount = sourceAccount as? CryptoAccount else {
                fatalError("Expected CryptoAccount: \(sourceAccount)")
            }
            guard let sourceCryptoAsset = cryptoAssets[cryptoAccount.asset] else {
                fatalError("CryptoAsset unavailable for sourceAccount: \(sourceAccount)")
            }
            return Single
                .zip(
                    sourceCryptoAsset.transactionTargets(account: cryptoAccount),
                    fiatAsset.accountGroup(filter: .all).map(\.accounts)
                )
                .map(+)
                .map { (accounts) -> [SingleAccount] in
                    accounts.filter { destinationAccount -> Bool in
                        Self.getActionFilter(
                            sourceAccount: cryptoAccount,
                            destinationAccount: destinationAccount,
                            action: action
                        )
                    }
                }
        case .deposit,
             .receive,
             .sell,
             .viewActivity,
             .withdraw:
            unimplemented("\(action) is not supported.")
        }
    }

    private static func getActionFilter(sourceAccount: CryptoAccount, destinationAccount: SingleAccount, action: AssetAction) -> Bool {
        switch action {
        case .sell:
            return destinationAccount is FiatAccount
        case .swap:
            return destinationAccount is CryptoAccount
                && destinationAccount.currencyType != sourceAccount.currencyType
                && !(destinationAccount is FiatAccount)
                && !(destinationAccount is CryptoInterestAccount)
                && (sourceAccount is TradingAccount ? destinationAccount is TradingAccount : true)
        case .send:
            return !(destinationAccount is FiatAccount)
                && !(destinationAccount is CryptoInterestAccount)
        case .deposit,
             .receive,
             .viewActivity,
             .withdraw:
            return false
        }
    }
}

// MARK: - Combine Related Methods

extension Coincore {
    /// Gives a chance for all assets to initialize themselves.
    /// - Note: Uses the `initialize` method and converts it to a publisher.
    public func initializePublisher() -> AnyPublisher<Never, Never> {
        initialize()
            .asPublisher()
            .catch { error -> AnyPublisher<Never, Never> in
                impossible()
            }
            .ignoreFailure()
    }
}
