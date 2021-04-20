//
//  UpdateWalletInformationClient.swift
//  PlatformKit
//
//  Created by Daniel on 29/06/2020.
//  Copyright © 2020 Blockchain Luxembourg S.A. All rights reserved.
//

import Combine
import DIKit
import NetworkKit

public protocol UpdateWalletInformationClientAPI: AnyObject {
    
    func updateWalletInfo(
        jwtToken: String
    ) -> AnyPublisher<EmptyNetworkResponse, NabuNetworkError>
}

final class UpdateWalletInformationClient: UpdateWalletInformationClientAPI {
     
    private enum Path {
        static let updateWalletInfo = [ "users", "current", "walletInfo" ]
    }
     
    // MARK: - Properties
     
    private let requestBuilder: RequestBuilder
    private let networkAdapter: NetworkAdapterAPI

     // MARK: - Setup
      
    init(networkAdapter: NetworkAdapterAPI = resolve(tag: DIKitContext.retail),
         requestBuilder: RequestBuilder = resolve(tag: DIKitContext.retail)) {
        self.networkAdapter = networkAdapter
        self.requestBuilder = requestBuilder
    }
    
    func updateWalletInfo(
        jwtToken: String
    ) -> AnyPublisher<EmptyNetworkResponse, NabuNetworkError> {
        let payload = JWTPayload(jwt: jwtToken)
        let request = requestBuilder.put(
            path: Path.updateWalletInfo,
            body: try? payload.encode(),
            authenticated: true
        )!
        return networkAdapter.perform(request: request)
    }
}
