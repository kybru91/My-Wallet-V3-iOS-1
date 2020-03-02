//
//  AccountBalanceFetching.swift
//  PlatformKit
//
//  Created by Daniel Huri on 12/08/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import RxRelay
import RxSwift
import RxCocoa

/// This protocol defines a single responsibility requirement for an account balance fetching
public protocol AccountBalanceFetching: class {
    var balanceType: BalanceType { get }
    var balance: Single<CryptoValue> { get }
    var balanceObservable: Observable<CryptoValue> { get }
    var balanceFetchTriggerRelay: PublishRelay<Void> { get }
}

public protocol CustodialAccountBalanceFetching: AccountBalanceFetching {
    /// Indicates, based on the data provided by the API, if the user has funded this account in the past.
    var isFunded: Single<Bool> { get }
}
