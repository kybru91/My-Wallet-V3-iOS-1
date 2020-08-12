//
//  AppSettingsProtocol.swift
//  Blockchain
//
//  Created by Daniel Huri on 22/06/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift
import ToolKit

public protocol AppSettingsAPI: class {
    var sharedKey: String? { get set }
    var guid: String? { get set }
}

extension AppSettingsAPI {
    /// Streams the GUID if exists
    public var guid: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.guid)
        }
    }

    /// Streams the shared key if exists
    public var sharedKey: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.sharedKey)
        }
    }
}

public protocol AppSettingsAuthenticating: class {
    var pin: String? { get set }
    var pinKey: String? { get set }
    var biometryEnabled: Bool { get set }
    var passwordPartHash: String? { get set }
    var encryptedPinPassword: String? { get set }
}

extension AppSettingsAuthenticating {
    public var pin: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.pin)
        }
    }

    public var pinKey: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.pinKey)
        }
    }

    public var biometryEnabled: Single<Bool> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.biometryEnabled)
        }
    }

    public var passwordPartHash: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.passwordPartHash)
        }
    }

    public var encryptedPinPassword: Single<String?> {
        Single.deferred { [weak self] in
            guard let self = self else {
                return .error(ToolKitError.nullReference(Self.self))
            }
            return .just(self.encryptedPinPassword)
        }
    }
}
