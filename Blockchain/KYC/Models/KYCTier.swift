//
//  KYC.Tier.swift
//  Blockchain
//
//  Created by Chris Arriola on 12/9/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation
import PlatformKit

extension KYC.Tier {
    static let lockedAnalyticsKey: String = "kyc_tiers_locked"
    
    var headline: String? {
        switch self {
        case .tier0:
            return nil
        case .tier1:
            return nil
        case .tier2:
            return LocalizationConstants.KYC.freeCrypto
        }
    }
    
    var tierDescription: String {
        switch self {
        case .tier0:
            return "Tier Zero Verification"
        case .tier1:
            return LocalizationConstants.KYC.tierOneVerification
        case .tier2:
            return LocalizationConstants.KYC.tierTwoVerification
        }
    }
    
    var requirementsDescription: String {
        switch self {
        case .tier0:
            return ""
        case .tier1:
            return LocalizationConstants.KYC.tierOneRequirements
        case .tier2:
            return LocalizationConstants.KYC.tierTwoRequirements
        }
    }
    
    var limitTimeframe: String {
        switch self {
        case .tier0:
            return "locked"
        case .tier1:
            return LocalizationConstants.KYC.annualSwapLimit
        case .tier2:
            return LocalizationConstants.KYC.dailySwapLimit
        }
    }
    
    var duration: String {
        switch self {
        case .tier0:
            return "0 minutes"
        case .tier1:
            return LocalizationConstants.KYC.takesThreeMinutes
        case .tier2:
            return LocalizationConstants.KYC.takesTenMinutes
        }
    }
    
    var startAnalyticsKey: String {
        switch self {
        case .tier0:
            return "kyc_tier0_start"
        case .tier1:
            return "kyc_tier1_start"
        case .tier2:
            return "kyc_tier2_start"
        }
    }
    
    var completionAnalyticsKey: String {
        switch self {
        case .tier0:
            /// You should never be able to actually
            /// complete `tier0` since it's not actually
            /// a thing.
            return ""
        case .tier1:
            return "kyc_tier1_complete"
        case .tier2:
            return "kyc_tier2_complete"
        }
    }
}
