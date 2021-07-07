// Copyright © Blockchain Luxembourg S.A. All rights reserved.
import Combine
import DIKit
import NetworkKit
import RxSwift
import ToolKit

public enum KYCTierServiceError: Error {
    case networkError(NetworkError)
    case other(Error)
}

public protocol KYCTiersServiceAPI: AnyObject {

    /// Returns the cached tiers. Fetches them if they are not already cached
    var tiers: Single<KYC.UserTiers> { get }

    /// Fetches the tiers from remote
    func fetchTiers() -> Single<KYC.UserTiers>

    /// Fetches the tiers from remote
    func fetchTiersPublisher() -> AnyPublisher<KYC.UserTiers, KYCTierServiceError>

    /// Fetches the Simplified Due Diligence Eligibility Status returning the whole response
    func simplifiedDueDiligenceEligibility(for tier: KYC.Tier) -> AnyPublisher<SimplifiedDueDiligenceResponse, Never>

    /// Fetches Simplified Due Diligence Eligibility Status
    func checkSimplifiedDueDiligenceEligibility() -> AnyPublisher<Bool, Never>

    /// Fetches Simplified Due Diligence Eligibility Status
    func checkSimplifiedDueDiligenceEligibility(for tier: KYC.Tier) -> AnyPublisher<Bool, Never>

    /// Fetches the Simplified Due Diligence Verification Status. It pools the API until a valid result is available. If the check fails, it returns `false`.
    func checkSimplifiedDueDiligenceVerification(for tier: KYC.Tier, pollUntilComplete: Bool) -> AnyPublisher<Bool, Never>

    /// Checks if the current user is SDD Verified
    func checkSimplifiedDueDiligenceVerification(pollUntilComplete: Bool) -> AnyPublisher<Bool, Never>
}

final class KYCTiersService: KYCTiersServiceAPI {

    // MARK: - Exposed Properties
    var tiers: Single<KYC.UserTiers> {
        Single.create(weak: self) { (self, observer) -> Disposable in
            guard case .success = self.semaphore.wait(timeout: .now() + .seconds(30)) else {
                observer(.error(ToolKitError.timedOut))
                return Disposables.create()
            }
            let disposable = self.cachedTiers.valueSingle
                .subscribe { event in
                    switch event {
                    case .success(let value):
                        observer(.success(value))
                    case .error(let value):
                        observer(.error(value))
                    }
                }

            return Disposables.create {
                disposable.dispose()
                self.semaphore.signal()
            }
        }
        .subscribeOn(scheduler)
    }

    // MARK: - Private Properties
    private let client: KYCClientAPI
    private let featureFlagsService: InternalFeatureFlagServiceAPI
    private let cachedTiers = CachedValue<KYC.UserTiers>(configuration: .onSubscription())
    private let semaphore = DispatchSemaphore(value: 1)
    private let scheduler = SerialDispatchQueueScheduler(qos: .default)

    // MARK: - Setup
    init(
        client: KYCClientAPI = resolve(),
        featureFlagsService: InternalFeatureFlagServiceAPI = resolve()
    ) {
        self.client = client
        self.featureFlagsService = featureFlagsService
        cachedTiers.setFetch(weak: self) { (self) in
            self.client.tiers()
        }
    }

    func fetchTiers() -> Single<KYC.UserTiers> {
        cachedTiers.fetchValue
    }

    func fetchTiersPublisher() -> AnyPublisher<KYC.UserTiers, KYCTierServiceError> {
        fetchTiers()
            .asPublisher()
            .mapError { error -> KYCTierServiceError in
                guard let error = error as? NetworkError else {
                    return .other(error)
                }
                return .networkError(error)
            }
            .eraseToAnyPublisher()
    }

    func simplifiedDueDiligenceEligibility(for tier: KYC.Tier) -> AnyPublisher<SimplifiedDueDiligenceResponse, Never> {
        guard featureFlagsService.isEnabled(.sddEnabled) else {
            return .just(SimplifiedDueDiligenceResponse(eligible: false, tier: KYC.Tier.tier0.rawValue))
        }
        guard tier != .tier2 else {
            // Tier2 (Gold) verified users should be treated as SDD eligible
            return .just(SimplifiedDueDiligenceResponse(eligible: true, tier: tier.rawValue))
        }
        return client.checkSimplifiedDueDiligenceEligibility()
            .replaceError(with: SimplifiedDueDiligenceResponse(eligible: false, tier: tier.rawValue))
            .eraseToAnyPublisher()
    }

    func checkSimplifiedDueDiligenceEligibility() -> AnyPublisher<Bool, Never> {
        guard featureFlagsService.isEnabled(.sddEnabled) else {
            return .just(false)
        }
        return fetchTiersPublisher()
            .flatMap { [weak self] userTiers -> AnyPublisher<Bool, KYCTierServiceError> in
                guard let self = self else {
                    return .just(false)
                }
                return self.simplifiedDueDiligenceEligibility(for: userTiers.latestApprovedTier)
                    .map(\.eligible)
                    .setFailureType(to: KYCTierServiceError.self)
                    .eraseToAnyPublisher()
            }
            .replaceError(with: false)
            .eraseToAnyPublisher()
    }

    func checkSimplifiedDueDiligenceEligibility(for tier: KYC.Tier) -> AnyPublisher<Bool, Never> {
        simplifiedDueDiligenceEligibility(for: tier)
            .map(\.eligible)
            .eraseToAnyPublisher()
    }

    func checkSimplifiedDueDiligenceVerification(for tier: KYC.Tier, pollUntilComplete: Bool) -> AnyPublisher<Bool, Never> {
        guard featureFlagsService.isEnabled(.sddEnabled) else {
            return .just(false)
        }
        guard tier > .tier0 else {
            // A Tier 0 user cannot be SDD verified. Only Tier 1+ users can be.
            return .just(false)
        }
        guard tier != .tier2 else {
            // Tier 2 (Gold) verified users should be treated as SDD verified
            return .just(true)
        }
        let timeout = Date(timeIntervalSinceNow: .minutes(2))
        func pollingHelper() -> AnyPublisher<SimplifiedDueDiligenceVerificationResponse, NabuNetworkError> {
            // Poll the API every 5 seconds until `taskComplete` is `true` or an error is returned from the upstream until timeout.
            // This should only take a couple of seconds in reality.
            client.checkSimplifiedDueDiligenceVerification()
                .flatMap { [pollingHelper] result -> AnyPublisher<SimplifiedDueDiligenceVerificationResponse, NabuNetworkError> in
                    let shouldRetry = pollUntilComplete && !result.taskComplete && Date() < timeout
                    guard shouldRetry else {
                        return .just(result)
                    }
                    return pollingHelper()
                        .delay(for: 5, scheduler: DispatchQueue.global(qos: .userInitiated))
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }

        return pollingHelper()
            .replaceError(with: SimplifiedDueDiligenceVerificationResponse(verified: false, taskComplete: true))
            .map(\.verified)
            .eraseToAnyPublisher()
    }

    func checkSimplifiedDueDiligenceVerification(pollUntilComplete: Bool) -> AnyPublisher<Bool, Never> {
        guard featureFlagsService.isEnabled(.sddEnabled) else {
            return .just(false)
        }
        return fetchTiersPublisher()
            .flatMap { [weak self] userTiers -> AnyPublisher<Bool, KYCTierServiceError> in
                guard let self = self else {
                    return .just(false)
                }
                return self.checkSimplifiedDueDiligenceVerification(
                    for: userTiers.latestApprovedTier,
                    pollUntilComplete: pollUntilComplete
                )
                .setFailureType(to: KYCTierServiceError.self)
                .eraseToAnyPublisher()
            }
            .replaceError(with: false)
            .eraseToAnyPublisher()
    }
}
