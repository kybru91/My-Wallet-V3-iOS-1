//
//  AssetAction+AccessibilityPrefix.swift
//  TransactionUIKit
//
//  Created by Dimitrios Chatzieleftheriou on 20/04/2021.
//  Copyright © 2021 Blockchain Luxembourg S.A. All rights reserved.
//

import PlatformKit

extension AssetAction {

    /// A `String` used as a prefic for accessibility identifiers.
    /// - Note: This is includes a `.` (dot) at the end of the prefix
    var accessibilityPrefix: String {
        switch self {
        case .deposit:
            return "Deposit."
        case .receive:
            return "Receive."
        case .sell:
            return "Sell."
        case .send:
            return "Send."
        case .swap:
            return "Swap."
        case .viewActivity:
            return "ViewActivity."
        case .withdraw:
            return "Withdraw."
        }
    }
}