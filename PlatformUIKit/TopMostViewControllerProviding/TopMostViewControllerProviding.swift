//
//  TopMostViewControllerProviding.swift
//  PlatformKit
//
//  Created by Daniel Huri on 27/11/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

/// A provider protocol for top most view controller
public protocol TopMostViewControllerProviding: class {
    var topMostViewController: UIViewController? { get }
}

// MARK: - UIApplication

extension UIApplication: TopMostViewControllerProviding {
    public var topMostViewController: UIViewController? {
        keyWindow?.topMostViewController
    }
}

// MARK: - UIWindow

extension UIWindow: TopMostViewControllerProviding {
    public var topMostViewController: UIViewController? {
        rootViewController?.topMostViewController
    }
}

// MARK: - UIViewController

extension UIViewController: TopMostViewControllerProviding {

    /// Returns the top-most visibly presented UIViewController in this UIViewController's hierarchy
    @objc
    public var topMostViewController: UIViewController? {
        if self is UIAlertController {
            return presentedViewController?.topMostViewController
        } else if self is UINavigationController {
            return self
        } else {
            return presentedViewController?.topMostViewController ?? self
        }
    }
}
