// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import PlatformKit

extension StellarHistoricalTransaction {
    var activityItemEvent: TransactionalActivityItemEvent {
        .init(
            identifier: identifier,
            transactionHash: transactionHash,
            creationDate: createdAt,
            status: .complete,
            type: direction == .debit ? .receive : .send,
            amount: amount,
            fee: fee
        )
    }
}