//
//  AssetAccountRepository.swift
//  Blockchain
//
//  Created by Chris Arriola on 9/13/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import BigInt
import ToolKit
import PlatformKit
import EthereumKit
import StellarKit
import ERC20Kit

// TICKET: [IOS-2087] - Integrate PlatformKit Account Repositories and Deprecate AssetAccountRepository
/// A repository for `AssetAccount` objects
class AssetAccountRepository: AssetAccountRepositoryAPI {

    static let shared: AssetAccountRepositoryAPI = AssetAccountRepository()

    private let wallet: Wallet
    private let stellarServiceProvider: StellarServiceProvider
    private let paxAccountRepository: ERC20AssetAccountRepository<PaxToken>
    private let ethereumAccountRepository: EthereumAssetAccountRepository
    private let ethereumWalletService: EthereumWalletServiceAPI
    private let stellarAccountService: StellarAccountAPI
    private var cachedAccounts = BehaviorRelay<[AssetAccount]?>(value: nil)
    private let disposables = CompositeDisposable()

    init(
        wallet: Wallet = WalletManager.shared.wallet,
        stellarServiceProvider: StellarServiceProvider = StellarServiceProvider.shared,
        paxServiceProvider: PAXServiceProvider = PAXServiceProvider.shared,
        ethereumServiceProvider: ETHServiceProvider = ETHServiceProvider.shared
    ) {
        self.wallet = wallet
        self.paxAccountRepository = paxServiceProvider.services.assetAccountRepository
        self.ethereumWalletService = paxServiceProvider.services.walletService
        self.stellarServiceProvider = stellarServiceProvider
        self.stellarAccountService = stellarServiceProvider.services.accounts
        self.ethereumAccountRepository = ethereumServiceProvider.services.assetAccountRepository
    }

    deinit {
        disposables.dispose()
    }

    // MARK: Public Properties

    var accounts: Single<[AssetAccount]> {
        guard let value = cachedAccounts.value else {
            return fetchAccounts()
        }
        return .just(value)
    }

    var fetchETHHistoryIfNeeded: Single<Void> {
        return ethereumWalletService.fetchHistoryIfNeeded
    }

    // MARK: Public Methods

    func accounts(for assetType: AssetType) -> Single<[AssetAccount]> {
        return accounts(for: assetType, fromCache: true)
    }

    func accounts(for assetType: AssetType, fromCache: Bool) -> Single<[AssetAccount]> {
        guard wallet.isInitialized() else {
            return .just([])
        }

        switch assetType {
        case .pax:
            return paxAccount(fromCache: fromCache)
        case .ethereum:
            return ethereumAccount(fromCache: fromCache)
        case .stellar:
            return stellarAccount(fromCache: fromCache)
        case .bitcoin,
             .bitcoinCash:
            return legacyAddress(assetType: assetType, fromCache: fromCache)
        }
    }

    func nameOfAccountContaining(address: String, currencyType: CryptoCurrency) -> Single<String> {
        return accounts
            .flatMap { output -> Single<String> in
                guard let result = output.first(where: { $0.address.address == address && $0.balance.currencyType == currencyType }) else {
                    return .error(NSError())
                }
                return .just(result.name)
            }
    }

    func fetchAccounts() -> Single<[AssetAccount]> {
        let observables: [Observable<[AssetAccount]>] = AssetType.all.map {
            accounts(for: $0, fromCache: false).asObservable()
        }
        return Single.create { observer -> Disposable in
            let disposable = Observable.zip(observables)
                .subscribeOn(MainScheduler.asyncInstance)
                .map({ $0.flatMap({ return $0 })})
                .subscribe(onNext: { [weak self] output in
                    guard let self = self else { return }
                    self.cachedAccounts.accept(output)
                    observer(.success(output))
                })
            self.disposables.insertWithDiscardableResult(disposable)
            return Disposables.create()
        }
    }

    func defaultAccount(for assetType: AssetType) -> Single<AssetAccount?> {
        switch assetType {
        case .ethereum:
            return accounts(for: assetType, fromCache: false).map { $0.first }
        case .stellar:
            let account: AssetAccount? = stellarAccountService.currentAccount?.assetAccount
            return .just(account)
        case .pax:
            return accounts(for: .pax, fromCache: false).map { $0.first }
        case .bitcoin,
             .bitcoinCash:
            let index = wallet.getDefaultAccountIndex(for: assetType.legacy)
            let account: AssetAccount? = AssetAccount.create(assetType: assetType, index: index, wallet: wallet)
            return .just(account)
        }
    }

    // MARK: Private Methods

    private func stellarAccount(fromCache: Bool) -> Single<[AssetAccount]> {
        if fromCache {
            return cachedAccount(assetType: .stellar)
        } else {
            return stellarAccountService
                .currentStellarAccountAsSingle(fromCache: false)
                .map { account in
                    guard let account = account else {
                        return []
                    }
                    return [account.assetAccount]
                }
                .catchError { error -> Single<[AssetAccount]> in
                    /// Should Horizon go down or should we have an error when
                    /// retrieving the user's account details, we just want to return
                    /// a `Maybe.empty()`. If we return an error, the user will not be able
                    /// to see any of their available accounts in `Swap`.
                    guard error is StellarServiceError else {
                        return .error(error)
                    }
                    return .just([])
                }
        }
    }

    private func paxAccount(fromCache: Bool) -> Single<[AssetAccount]> {
        return paxAccountRepository
            .currentAssetAccountDetails(fromCache: fromCache)
            .flatMap {
                let account = AssetAccount(
                    index: 0,
                    address: AssetAddressFactory.create(
                        fromAddressString: $0.account.accountAddress,
                        assetType: .pax
                    ),
                    balance: $0.balance,
                    name: $0.account.name
                )
                return .just([account])
        }
    }

    private func cachedAccount(assetType: AssetType) -> Single<[AssetAccount]> {
        return accounts.flatMap { result -> Single<[AssetAccount]> in
            let cached = result.filter { $0.address.assetType == assetType }
            return .just(cached)
        }
    }

    private func ethereumAccount(fromCache: Bool) -> Single<[AssetAccount]> {
        guard !fromCache else {
            return cachedAccount(assetType: .ethereum)
        }

        guard let ethereumAddress = self.wallet.getEtherAddress(), self.wallet.hasEthAccount() else {
            Logger.shared.debug("This wallet has no ethereum address.")
            return .just([])
        }

        let fallback = EthereumAssetAccount(
            walletIndex: 0,
            accountAddress: ethereumAddress,
            name: LocalizationConstants.myEtherWallet
        )
        let details = EthereumAssetAccountDetails(
            account: fallback,
            balance: .etherZero,
            nonce: 0
        )

        return ethereumAccountRepository.assetAccountDetails
            .catchErrorJustReturn(details)
            .flatMap { details -> Single<[AssetAccount]> in
                let account = AssetAccount(
                    index: 0,
                    address: AssetAddressFactory.create(
                        fromAddressString: details.account.accountAddress,
                        assetType: .ethereum
                    ),
                    balance: details.balance,
                    name: LocalizationConstants.myEtherWallet
                )
                return .just([account].compactMap { $0 })
            }
    }

    // Handle BTC and BCH
    // TODO pull in legacy addresses.
    // TICKET: IOS-1290
    private func legacyAddress(assetType: AssetType, fromCache: Bool) -> Single<[AssetAccount]> {
        if fromCache {
            return cachedAccount(assetType: assetType)
        } else {
            let activeAccountsCount: Int32 = wallet.getActiveAccountsCount(assetType.legacy)
            /// Must have at least one address
            guard activeAccountsCount > 0 else {
                return .just([])
            }
            let result: [AssetAccount] = Array(0..<activeAccountsCount)
                .map { wallet.getIndexOfActiveAccount($0, assetType: assetType.legacy) }
                .compactMap { AssetAccount.create(assetType: assetType, index: $0, wallet: wallet) }
            return .just(result)
        }
    }
}

extension AssetAccount {

    /// Creates a new AssetAccount. This method only supports creating an AssetAccount for
    /// BTC or BCH. For ETH, use `defaultEthereumAccount`.
    fileprivate static func create(assetType: AssetType, index: Int32, wallet: Wallet) -> AssetAccount? {
        guard let address = wallet.getReceiveAddress(forAccount: index, assetType: assetType.legacy) else {
            return nil
        }
        let name = wallet.getLabelForAccount(index, assetType: assetType.legacy)
        let balanceFromWalletObject = wallet.getBalanceForAccount(index, assetType: assetType.legacy)
        let balance: CryptoValue
        if assetType == .bitcoin || assetType == .bitcoinCash {
            let balanceLong = balanceFromWalletObject as? CUnsignedLongLong ?? 0
            let balanceDecimal = Decimal(balanceLong) / Decimal(Constants.Conversions.satoshi)
            let balanceString = (balanceDecimal as NSDecimalNumber).description(withLocale: Locale.current)
            let balanceBigUInt = BigUInt(balanceString, decimals: assetType.cryptoCurrency.maxDecimalPlaces) ?? 0
            let balanceBigInt = BigInt(balanceBigUInt)
            balance = CryptoValue.createFromMinorValue(balanceBigInt, assetType: assetType.cryptoCurrency)
        } else {
            let balanceString = balanceFromWalletObject as? String ?? "0"
            balance = CryptoValue.createFromMajorValue(string: balanceString, assetType: assetType.cryptoCurrency) ?? CryptoValue.zero(assetType: assetType.cryptoCurrency)
        }
        return AssetAccount(
            index: index,
            address: AssetAddressFactory.create(fromAddressString: address, assetType: assetType),
            balance: balance,
            name: name ?? ""
        )
    }
}
