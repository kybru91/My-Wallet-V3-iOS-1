// Copyright © Blockchain Luxembourg S.A. All rights reserved.

/// Provides a clearing mechanism upon forgetting a wallet
protocol ClearOnLogoutAPI {
    func clearOnLogout()
}

/// An empty implementation of `ClearOnLogoutAPI` for compatibility purposes with older codebase
/// - note:
/// For context AppCoordinator method `clearOnLogout` was called from `WalletManager`'s `forgetWallet` method
/// There's no need to do that with the newer `ComposableArchitecture` codebase
final class EmptyClearOnLogout: ClearOnLogoutAPI {
    func clearOnLogout() {}
}
