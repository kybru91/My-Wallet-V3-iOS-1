// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import PlatformKit
import PlatformUIKit

extension CryptoCurrency {

    /// The legacy representation of `CryptoCurrency`
    var legacy: LegacyAssetType {
        switch self {
        case .aave:
            return .aave
        case .algorand:
            return .algorand
        case .bitcoin:
            return .bitcoin
        case .bitcoinCash:
            return .bitcoinCash
        case .ethereum:
            return .ether
        case .pax:
            return .pax
        case .polkadot:
            return .polkadot
        case .stellar:
            return .stellar
        case .tether:
            return .tether
        case .wDGLD:
            return .WDGLD
        case .yearnFinance:
            return .yearnFinance
        }
    }

    /// Returns `true` if an asset's addresses can be reused
    var shouldAddressesBeReused: Bool {
        switch self {
        case .bitcoin,
             .bitcoinCash:
            return false
        case .aave,
             .algorand,
             .ethereum,
             .pax,
             .polkadot,
             .stellar,
             .tether,
             .wDGLD,
             .yearnFinance:
            return true
        }
    }

    init(legacyAssetType: LegacyAssetType) {
        switch legacyAssetType {
        case .aave:
            self = .aave
        case .algorand:
            self = .algorand
        case .bitcoin:
            self = .bitcoin
        case .bitcoinCash:
            self = .bitcoinCash
        case .ether:
            self = .ethereum
        case .pax:
            self = .pax
        case .polkadot:
            self = .polkadot
        case .stellar:
            self = .stellar
        case .tether:
            self = .tether
        case .WDGLD:
            self = .wDGLD
        case .yearnFinance:
            self = .yearnFinance
        }
    }
}