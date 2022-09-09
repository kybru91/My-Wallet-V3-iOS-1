// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Foundation

extension KYC {
    public struct UserTier: Decodable, Equatable {

        public let tier: KYC.Tier
        public let name: String
        public let state: KYC.Tier.State
        public let limits: KYC.UserTier.Limits?

        enum CodingKeys: String, CodingKey {
            case tier = "index"
            case name
            case state
            case limits
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            tier = (try? values.decode(KYC.Tier.self, forKey: .tier)) ?? .tier0
            name = try values.decode(String.self, forKey: .name)
            state = try values.decode(KYC.Tier.State.self, forKey: .state)
            limits = try values.decodeIfPresent(KYC.UserTier.Limits.self, forKey: .limits)
        }

        public init(tier: KYC.Tier, state: KYC.Tier.State) {
            self.tier = tier
            self.state = state
            name = "Tier \(tier.rawValue)"
            limits = nil
        }
    }
}