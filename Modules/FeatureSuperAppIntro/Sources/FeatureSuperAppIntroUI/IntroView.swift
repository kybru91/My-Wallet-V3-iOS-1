// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import BlockchainComponentLibrary
import BlockchainNamespace
import CoreMotion
import Foundation
import Localization
import SwiftUI

private typealias L10n = LocalizationConstants.SuperAppIntro.V2

public struct IntroView: View {
    @State private var isExternalTradingEnabled = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @ObservedObject private var motionManager: MotionManager
    private let actionTitle: String
    private let span: Double = 150
    private let appMode: AppMode
    private let learnMoreUrl = "https://support.blockchain.com/hc/en-us/articles/360029029911-Blockchain-com-Wallet-101-What-is-a-DeFi-wallet-"

    public init(
        _ appMode: AppMode,
        actionTitle: String? = nil
    ) {
        self.actionTitle = actionTitle ?? appMode.button
        self.motionManager = MotionManager()
        self.appMode = appMode
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        TagView(
                            text: appMode.tag,
                            foregroundColor: appMode.tagColor
                        )
                        .padding(.bottom, 12)
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                        Text(appMode.title)
                            .typography(.title1)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        Text(LocalizedStringKey(appMode.byline))
                            .typography(.body1)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(16)
                    VStack {
                        rows
                        Spacer()
                        Text(appMode.footer)
                            .typography(.caption1)
                            .foregroundColor(.semantic.text)
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, Spacing.padding1)
                        buttons
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                    .background(
                        Color.semantic.light
                            .clipShape(Path { path in
                                let width: CGFloat = proxy.size.width
                                let height: CGFloat = proxy.size.height
                                path.move(to: .zero)
                                path.addQuadCurve(
                                    to: CGPoint(x: width, y: 0),
                                    control: CGPoint(
                                        x: 0.25 * width + span * motionManager.roll,
                                        y: 0.4 * height + span * motionManager.pitch * 2
                                    )
                                )
                                path.addLine(to:
                                    CGPoint(x: width, y: height)
                                )
                                path.addLine(
                                    to: CGPoint(
                                        x: 0,
                                        y: height
                                    )
                                )
                                path.closeSubpath()
                            })
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: proxy.size.height)
            }
            .background(
                LinearGradient(
                    colors: appMode.gradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
            )
        }
        .bindings {
            subscribe($isExternalTradingEnabled, to: blockchain.app.is.external.brokerage)
        }
    }

    @ViewBuilder var rows: some View {
        switch appMode {
        case .pkw:
            VStack {
                row(icon: Icon.lockClosed, title: L10n.DeFi.row1)
                row(
                    icon: Icon.chartBubble,
                    title: L10n.DeFi.row2,
                    bylineImage: "logos"
                )
                row(icon: Icon.link, title: L10n.DeFi.row3)
            }
        default:
            VStack {
                row(icon: Icon.cart, title: L10n.Trading.row1)
                row(icon: Icon.bank, title: L10n.Trading.row2)
                if isExternalTradingEnabled == false {
                    row(icon: Icon.interest, title: L10n.Trading.row3)
                }
            }
        }
    }

    @ViewBuilder var buttons: some View {
        switch appMode {
        case .pkw:
            VStack(spacing: 16) {
                PrimaryWhiteButton(title: L10n.DeFi.secondaryButton) {
                    guard let url = URL(string: learnMoreUrl) else {
                        return
                    }
                    openURL(url)
                }
                PrimaryButton(title: actionTitle) {
                    dismiss()
                }
            }
        default:
            PrimaryButton(title: actionTitle) {
                dismiss()
            }
        }
    }

    @ViewBuilder
    func row(
        icon: Icon,
        title: String,
        bylineImage: String? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            icon.color(.semantic.title).small()
            VStack(alignment: .leading) {
                Text(title)
                    .typography(.paragraph2)
                    .foregroundColor(.semantic.title)
                if let bylineImage {
                    Image(bylineImage, bundle: .featureSuperAppIntro)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
    }
}

struct IntroView_Previews: PreviewProvider {
    static var previews: some View {
        IntroView(.pkw)
    }
}

class MotionManager: ObservableObject {

    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0

    private var manager: CMMotionManager

    init() {
        self.manager = CMMotionManager()
        manager.deviceMotionUpdateInterval = 1 / Double(UIScreen.main.maximumFramesPerSecond)

        var attitude = manager.deviceMotion?.attitude
        manager.startDeviceMotionUpdates(to: .main) { motionData, error in
            guard error == nil, let attitude, let motionData else {
                attitude = motionData?.attitude
                return
            }

            self.pitch = (motionData.attitude.pitch - attitude.pitch) / .pi
            self.roll = (motionData.attitude.roll - attitude.roll) / .pi
        }
    }
}

extension AppMode {

    fileprivate var tag: String {
        switch self {
        case .pkw:
            return L10n.DeFi.tag
        default:
            return L10n.Trading.tag
        }
    }

    fileprivate var title: String {
        switch self {
        case .pkw:
            return L10n.DeFi.title
        default:
            return L10n.Trading.title
        }
    }

    fileprivate var byline: String {
        switch self {
        case .pkw:
            return L10n.DeFi.byline
        default:
            return L10n.Trading.byline
        }
    }

    fileprivate var footer: String {
        switch self {
        case .pkw:
            return L10n.DeFi.footer
        default:
            return L10n.Trading.footer
        }
    }

    fileprivate var button: String {
        switch self {
        case .pkw:
            return L10n.DeFi.button
        default:
            return L10n.Trading.button
        }
    }

    fileprivate var tagColor: Color {
        switch self {
        case .pkw:
            return Color(red: 0.42, green: 0.22, blue: 0.74)
        default:
            return Color.semantic.pink
        }
    }

    fileprivate var gradient: [Color] {
        switch self {
        case .pkw:
            return [
                Color(red: 0.42, green: 0.22, blue: 0.74),
                Color(red: 0.16, green: 0.47, blue: 0.83)
            ]
        default:
            return [
                Color(red: 1.0, green: 0, blue: 0.59),
                Color(red: 0.49, green: 0.20, blue: 0.73)
            ]
        }
    }
}
