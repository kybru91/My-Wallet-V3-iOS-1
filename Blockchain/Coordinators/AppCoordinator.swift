// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import AnalyticsKit
import DashboardUIKit
import DIKit
import InterestKit
import InterestUIKit
import KYCUIKit
import PlatformKit
import PlatformUIKit
import RxSwift
import SettingsKit
import SettingsUIKit
import ToolKit
import WalletPayloadKit

/// TODO: This class should be refactored so any view would load
/// as late as possible and also would be deallocated when is no longer in use
/// TICKET: IOS-2619
@objc class AppCoordinator: NSObject,
                            Coordinator,
                            MainFlowProviding,
                            BackupFlowStarterAPI,
                            SettingsStarterAPI,
                            TabControllerManagerProvider,
                            LoggedInReloadAPI,
                            ClearOnLogoutAPI {

    // MARK: - Properties

    @Inject @objc static var shared: AppCoordinator

    // MARK: - Services

    /// Onboarding router
    @Inject var onboardingRouter: OnboardingRouter

    weak var window: UIWindow!

    @Inject private var authenticationCoordinator: AuthenticationCoordinator
    @Inject private var blockchainSettings: BlockchainSettings.App
    @Inject private var walletManager: WalletManager
    @Inject private var loadingViewPresenter: LoadingViewPresenting
    @LazyInject private var appFeatureConfigurator: AppFeatureConfigurator
    @LazyInject private var credentialsStore: CredentialsStoreAPI
    @LazyInject private var walletUpgradeService: WalletUpgradeServicing
    @LazyInject private var reactiveWallet: ReactiveWalletAPI
    @LazyInject private var secondPasswordPrompter: SecondPasswordPromptable
    @LazyInject private var recorder: AnalyticsEventRecording
    @LazyInject private var secureChannelRouter: SecureChannelRouting

    @Inject var airdropRouter: AirdropRouterAPI
    private var settingsRouterAPI: SettingsRouterAPI?
    private var buyRouter: PlatformUIKit.RouterAPI!
    private var sellRouter: PlatformUIKit.SellRouter!
    private var backupRouter: DashboardUIKit.BackupRouterAPI?

    // MARK: - UIViewController Properties

    @objc var slidingViewController: ECSlidingViewController!
    @objc var tabControllerManager: TabControllerManager?
    private(set) var sideMenuViewController: SideMenuViewController!
    private weak var accountsAndAddressesNavigationController: AccountsAndAddressesNavigationController?
    private let disposeBag = DisposeBag()

    // MARK: NSObject

    override init() {
        super.init()
        self.walletManager.accountInfoAndExchangeRatesDelegate = self
        self.walletManager.backupDelegate = self
        self.walletManager.historyDelegate = self
        observeSymbolChanges()
    }

    // MARK: Public Methods

    /// Called by AuthenticationCoordinator after wallet loads, this will set the correct view controller as root of the window
    /// and then call the completion block.
    func startAfterWalletAuthentication(completion: @escaping () -> Void) {
        // Sets view controller as rootViewController of the window
        setupMainFlow()
            .observeOn(MainScheduler.asyncInstance)
            .subscribe(
                onSuccess: { [weak self] rootViewController in
                    self?.setRootViewController(rootViewController, animated: true, completion: completion)
                }
            )
            .disposed(by: disposeBag)
    }

    func syncPinKeyWithICloud() {
        // In order to login to wallet, we need to know:
        // GUID                 - To look up the wallet
        // SharedKey            - To be able to read/write to the wallet db record (payload, settings, etc)
        // EncryptedPinPassword - To decrypt the wallet
        // PinKey               - Used in conjunction with the user's PIN to retrieve decryption key to the EncryptedPinPassword (EncryptedWalletPassword)
        // PIN                  - Provided by the user or retrieved from secure enclave if Face/TouchID is enabled

        // In this method, we backup/restore the pinKey - which is essentially the identifier of the PIN.
        // Upon successful PIN authentication, we will backup/restore the remaining wallet details: guid, sharedKey, encryptedPinPassword.
        // The backup/restore of guid and sharedKey requires an encryption/decryption step when backing up and restoring respectively.
        // The key used to encrypt/decrypt the guid and sharedKey is provided in the response to a successful PIN auth attempt.

        guard !blockchainSettings.isPairedWithWallet else {
            // Wallet is Paired, we do not need to restore.
            // We will back up after pin authentication
            return
        }

        if blockchainSettings.pinKey == nil,
            blockchainSettings.encryptedPinPassword == nil,
            blockchainSettings.guid == nil,
            blockchainSettings.sharedKey == nil {

            credentialsStore.synchronize()

            // Attempt to restore the pinKey from iCloud
            if let pinData = credentialsStore.pinData() {
                blockchainSettings.pinKey = pinData.pinKey
                blockchainSettings.encryptedPinPassword = pinData.encryptedPinPassword
            }
        }
    }

    @objc func start() {
        appFeatureConfigurator.initialize()

        // Try to restore wallet details from iCloud
        syncPinKeyWithICloud()

        if blockchainSettings.guid != nil, blockchainSettings.sharedKey != nil {
            // Original flow
            AuthenticationCoordinator.shared.start()
        } else if blockchainSettings.pinKey != nil, blockchainSettings.encryptedPinPassword != nil {
            // iCloud restoration flow
            AuthenticationCoordinator.shared.start()
        } else {
            onboardingRouter.start()
        }
    }

    @discardableResult
    func setupMainFlow() -> Single<UIViewController> {
        reactiveWallet
            .waitUntilInitializedSingle
            .flatMap(weak: self) { (self, _) in
                self.secondPasswordPrompter.secondPasswordIfNeeded(type: .login)
            }
            .flatMap(weak: self) { (self, _) -> Single<Bool> in
                self.walletUpgradeService.needsWalletUpgrade
                    .catchErrorJustReturn(false)
            }
            .observeOn(MainScheduler.asyncInstance)
            .map(weak: self) { (self, needsWalletUpgrade) in
                if needsWalletUpgrade {
                    return self.setupWalletUpgrade(completion: { [weak self] in
                        guard let self = self else { return }
                        self.window.setRootViewController(self.setupLoggedInFlow())
                    })
                } else {
                    return self.setupLoggedInFlow()
                }
            }
    }

    func showSettingsView() {
        let router: SettingsRouterAPI = resolve()
        settingsRouterAPI = router
        router.presentSettings()
    }

    @objc func closeSideMenu() {
        guard let slidingViewController = slidingViewController else {
            return
        }
        guard slidingViewController.currentTopViewPosition != .centered else {
            return
        }
        slidingViewController.resetTopView(animated: true)
    }

    /// Reloads contained view controllers
    @objc func reload() {
        accountsAndAddressesNavigationController?.reload()
        sideMenuViewController?.reload()

        NotificationCenter.default.post(name: Constants.NotificationKeys.reloadToDismissViews, object: nil)

        // Legacy code for generating new addresses
        NotificationCenter.default.post(name: Constants.NotificationKeys.newAddress, object: nil)
    }

    /// Method to "cleanup" state when the app is backgrounded.
    func cleanupOnAppBackgrounded() {

        /// Keep going only if the user is logged in
        guard slidingViewController != nil else {
            return
        }
        tabControllerManager?.showDashboard()
        closeSideMenu()
    }

    // MARK: Private Methods

    private func reloadAfterMultiAddressResponse() {
        guard tabControllerManager != nil, tabControllerManager!.tabViewController.isViewLoaded else {
            // Nothing to reload
            return
        }
        accountsAndAddressesNavigationController?.reload()
        sideMenuViewController?.reload()

        NotificationCenter.default.post(name: Constants.NotificationKeys.reloadToDismissViews, object: nil)
        NotificationCenter.default.post(name: Constants.NotificationKeys.newAddress, object: nil)
        NotificationCenter.default.post(name: Constants.NotificationKeys.multiAddressResponseReload, object: nil)
    }

    private func setRootViewController(_ rootViewController: UIViewController, animated: Bool, completion: @escaping () -> Void) {
        // Sets root view controller
        window.setRootViewController(rootViewController)
        // Animate if needed
        if animated {
            // Animate with `completion` block.
            UIView.transition(
                with: window,
                duration: 0.3,
                options: .transitionCrossDissolve,
                animations: nil,
                completion: { _ in completion() }
            )
        } else {
            // Call `completion` block.
            completion()
        }
    }

    private func setupWalletUpgrade(completion: @escaping () -> Void) -> UIViewController {
        let interactor = WalletUpgradeInteractor(completion: completion)
        let presenter = WalletUpgradePresenter(interactor: interactor)
        let viewController = WalletUpgradeViewController(presenter: presenter)
        return viewController
    }

    private func setupLoggedInFlow() -> UIViewController {
        self.setupTabControllerManager()
        self.setupSideMenuViewController()
        let viewController = ECSlidingViewController()
        viewController.underLeftViewController = self.sideMenuViewController
        viewController.topViewController = self.tabControllerManager?.tabViewController
        self.slidingViewController = viewController
        sideMenuViewController.provideTabControllerManager = { [weak tabControllerManager] in
            tabControllerManager
        }
        sideMenuViewController.provideSlidingViewController = { [weak slidingViewController] in
            slidingViewController
        }
        sideMenuViewController?.peekPadding = viewController.anchorRightPeekAmount
        self.tabControllerManager?.tabViewController.sideMenuGesture = viewController.panGesture
        self.tabControllerManager?.tabViewController.loadViewIfNeeded()
        self.tabControllerManager?.showDashboard()
        return viewController
    }

    private func setupSideMenuViewController() {
        let viewController = SideMenuViewController.makeFromStoryboard()
        viewController.delegate = self
        viewController.createGestureRecognizers = { [weak self] in
            guard let self = self else { return nil }
            return (
                UITapGestureRecognizer(
                    target: self,
                    action: #selector(AppCoordinator.toggleSideMenu)
                ),
                UITapGestureRecognizer(
                    target: self,
                    action: #selector(AppCoordinator.toggleSideMenu)
                )
            )
        }
        self.sideMenuViewController = viewController
    }

    private func setupTabControllerManager() {
        self.tabControllerManager = TabControllerManager()
    }

    /// Observes symbol changes so that view controllers can reflect the new symbol
    private func observeSymbolChanges() {
        BlockchainSettings.App.shared.onSymbolLocalChanged = { [weak self] _ in
            self?.accountsAndAddressesNavigationController?.reload()
            self?.sideMenuViewController?.reload()
        }
    }
}

extension AppCoordinator: SideMenuViewControllerDelegate {
    func sideMenuViewController(_ viewController: SideMenuViewController, didTapOn item: SideMenuItem) {
        switch item {
        case .backup:
            startBackupFlow()
        case .accountsAndAddresses:
            handleAccountsAndAddresses()
        case .settings:
            handleSettings()
        case .webLogin:
            handleWebLogin()
        case .support:
            handleSupport()
        case .airdrops:
            handleAirdrops()
        case .logout:
            handleLogout()
        case .buy:
            handleBuyCrypto()
        case .sell:
            handleSellCrypto()
        case .exchange:
            handleExchange()
        case .secureChannel:
            handleSecureChannel()
        case .lockbox:
            let lockboxViewController = LockboxViewController.makeFromStoryboard()
            lockboxViewController.modalPresentationStyle = .fullScreen
            lockboxViewController.modalTransitionStyle = .coverVertical
            UIApplication.shared.keyWindow?.rootViewController?.topMostViewController?.present(lockboxViewController, animated: true)
        }
    }

    private func handleAirdrops() {
        airdropRouter.presentAirdropCenterScreen()
    }

    struct SecureChannelQRCodeTextViewModel: QRCodeScannerTextViewModel {
        private typealias LocalizedString = LocalizationConstants.SecureChannel.QRCode
        let headerText: String = LocalizedString.header
        let subtitleText: String? = LocalizedString.subtitle
    }

    private func handleSecureChannel() {
        let parser = SecureChannelQRCodeParser()
        let textViewModel = SecureChannelQRCodeTextViewModel()
        let builder = QRCodeScannerViewControllerBuilder(
            parser: parser,
            textViewModel: textViewModel,
            completed: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let string):
                    self.secureChannelRouter.didScanPairingQRCode(msg: string)
                case .failure(let error):
                    Logger.shared.debug(String(describing: error))
                    AlertViewPresenter.shared
                        .standardError(message: String(describing: error))
                }
            }
        )
        guard let viewController = builder.build() else {
            // No camera access, an alert will be displayed automatically.
            return
        }
        UIApplication.shared.topMostViewController?.present(
            viewController,
            animated: true
        )
    }

    func startBackupFlow() {
        let router: DashboardUIKit.BackupRouterAPI = resolve()
        backupRouter = router
        router.start()
    }

    private func createAccountsAndAddressesViewController() -> UIViewController {
        let storyboard = UIStoryboard(name: "AccountsAndAddresses", bundle: nil)
        let viewController = storyboard.instantiateViewController(
            withIdentifier: "AccountsAndAddressesNavigationController"
        ) as! AccountsAndAddressesNavigationController
        viewController.modalPresentationStyle = .fullScreen
        viewController.modalTransitionStyle = .coverVertical
        self.accountsAndAddressesNavigationController = viewController
        return viewController
    }

    private func handleAccountsAndAddresses() {
        UIApplication.shared.keyWindow?.rootViewController?.topMostViewController?.present(
            createAccountsAndAddressesViewController(),
            animated: true
        )
    }

    private func handleSettings() {
        showSettingsView()
    }

    private func handleExchange() {
        guard let tabViewController = tabControllerManager?.tabViewController else { return }
        ExchangeCoordinator.shared.start(from: tabViewController)
    }

    private func handleWebLogin() {
        let presenter = WebLoginScreenPresenter()
        let viewController = WebLoginScreenViewController(presenter: presenter)
        let navigationController = UINavigationController(rootViewController: viewController)
        UIApplication.shared.topMostViewController?.present(
            navigationController,
            animated: true
        )
    }

    private func handleSupport() {
        let title = String(format: LocalizationConstants.openArg, Constants.Url.blockchainSupport)
        let alert = UIAlertController(
            title: title,
            message: LocalizationConstants.youWillBeLeavingTheApp,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: LocalizationConstants.continueString, style: .default) { _ in
                guard let url = URL(string: Constants.Url.blockchainSupport) else { return }
                UIApplication.shared.open(url)
            }
        )
        alert.addAction(
            UIAlertAction(title: LocalizationConstants.cancel, style: .cancel)
        )
        UIApplication.shared.keyWindow?.rootViewController?.topMostViewController?.present(
            alert,
            animated: true
        )
    }

    private func handleLogout() {
        let alert = UIAlertController(
            title: LocalizationConstants.SideMenu.logout,
            message: LocalizationConstants.SideMenu.logoutConfirm,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: LocalizationConstants.okString, style: .default) { _ in
                AuthenticationCoordinator.shared.logout()
            }
        )
        alert.addAction(UIAlertAction(title: LocalizationConstants.cancel, style: .cancel))
        UIApplication.shared.keyWindow?.rootViewController?.topMostViewController?.present(
            alert,
            animated: true
        )
    }

    func clearOnLogout() {
        tabControllerManager = nil
        slidingViewController = nil
        sideMenuViewController = nil
    }

    /// Starts Buy Crypto flow.
    func handleBuyCrypto(currency: CryptoCurrency = .bitcoin) {
        let builder = PlatformUIKit.Builder(
            stateService: PlatformUIKit.StateService()
        )
        buyRouter = PlatformUIKit.Router(builder: builder, currency: currency)
        buyRouter.start()
    }

    /// Starts Sell Crypto flow
    @objc func handleSellCrypto() {
        let accountSelectionService = AccountSelectionService()
        let interactor = SellRouterInteractor(
            accountSelectionService: accountSelectionService
        )
        let builder = PlatformUIKit.SellBuilder(
            accountSelectionService: accountSelectionService,
            routerInteractor: interactor
        )
        sellRouter = PlatformUIKit.SellRouter(builder: builder)
        sellRouter.load()
    }

    func startSimpleBuyAtLogin() {
        let stateService = PlatformUIKit.StateService()
        guard !stateService.cache.value[.hasShownIntroScreen] else {
            return
        }

        let builder = PlatformUIKit.Builder(
            stateService: stateService
        )

        buyRouter = PlatformUIKit.Router(builder: builder)
        buyRouter.start()
    }

    func showFundTrasferDetails(fiatCurrency: FiatCurrency, isOriginDeposit: Bool) {
        let stateService = PlatformUIKit.StateService()
        let builder = PlatformUIKit.Builder(
            stateService: stateService
        )

        buyRouter = PlatformUIKit.Router(builder: builder)
        buyRouter.setup(startImmediately: false)
        stateService.showFundsTransferDetails(
            for: fiatCurrency,
            isOriginDeposit: isOriginDeposit
        )
    }
}

// MARK: - DrawerRouting

extension AppCoordinator: DrawerRouting {
    // Shows the side menu (i.e. ECSlidingViewController)
    @objc func toggleSideMenu() {
        // If the sideMenu is not shown, show it
        if slidingViewController.currentTopViewPosition == .centered {
            slidingViewController.anchorTopViewToRight(animated: true)
        } else {
            slidingViewController.resetTopView(animated: true)
        }
    }
}

extension AppCoordinator: WalletAccountInfoAndExchangeRatesDelegate {
    func didGetAccountInfoAndExchangeRates() {
        loadingViewPresenter.hide()
        reloadAfterMultiAddressResponse()
    }
}

extension AppCoordinator: WalletBackupDelegate {
    func didBackupWallet() {
        walletManager.wallet.getHistoryForAllAssets()
    }

    func didFailBackupWallet() {
        walletManager.wallet.getHistoryForAllAssets()
    }
}

extension AppCoordinator: WalletHistoryDelegate {
    func didFailGetHistory(error: String?) {
        guard let errorMessage = error, errorMessage.count > 0 else {
            AlertViewPresenter.shared.standardError(message: LocalizationConstants.Errors.noInternetConnectionPleaseCheckNetwork)
            return
        }
        recorder.record(event: AnalyticsEvents.AppCoordinatorEvent.btcHistoryError(errorMessage))
        AlertViewPresenter.shared.standardError(message: LocalizationConstants.Errors.balancesGeneric)
    }

    func didFetchBitcoinCashHistory() {
        loadingViewPresenter.hide()
        reload()
    }
}

// MARK: - TabSwapping

extension AppCoordinator: TabSwapping {
    func deposit(into account: BlockchainAccount) {
        tabControllerManager?.deposit(into: account)
    }

    func withdraw(from account: BlockchainAccount) {
        tabControllerManager?.withdraw(from: account)
    }

    func send(from account: BlockchainAccount) {
        tabControllerManager?.send(from: account)
    }

    func switchToSend() {
        tabControllerManager?.showSend()
    }

    func switchTabToSwap() {
        tabControllerManager?.showSwap()
    }

    func switchTabToReceive() {
        tabControllerManager?.showReceive()
    }

    func switchToActivity() {
        tabControllerManager?.showTransactions()
    }

    func switchToActivity(for currencyType: CurrencyType) {
        tabControllerManager?.showTransactions()
    }
}

extension AppCoordinator: CurrencyRouting {
    func toSend(_ currency: CurrencyType) {
        tabControllerManager?.showSend(cryptoCurrency: currency.cryptoCurrency!)
    }

    func toReceive(_ currency: CurrencyType) {
        tabControllerManager?.showReceive()
    }
}

extension AppCoordinator: CashIdentityVerificationAnnouncementRouting {
    func showCashIdentityVerificationScreen() {
        let presenter = CashIdentityVerificationPresenter()
        let controller = CashIdentityVerificationViewController(presenter: presenter)
        tabControllerManager?.tabViewController.showCashIdentityVerificatonController(controller)
    }
}

extension AppCoordinator: InterestIdentityVerificationAnnouncementRouting {
    func showInterestDashboardAnnouncementScreen(isKYCVerfied: Bool) {
        var presenter: InterestDashboardAnnouncementPresenting
        let router = InterestDashboardAnnouncementRouter(
            navigationRouter: NavigationRouter()
        )
        if isKYCVerfied {
            presenter = InterestDashboardAnnouncementScreenPresenter(
                router: router
            )
        } else {
            presenter = InterestIdentityVerificationScreenPresenter(
                router: router
            )
        }
        let controller = InterestDashboardAnnouncementViewController(presenter: presenter)
        tabControllerManager?.tabViewController.showInterestIdentityVerificationScreen(controller)
    }
}
