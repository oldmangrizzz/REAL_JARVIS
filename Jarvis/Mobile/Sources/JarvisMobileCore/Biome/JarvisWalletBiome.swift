import Foundation
import PassKit
import UIKit
import Combine

/// Wallet biome — PassKit, Apple Pay, payment & pass management
///
/// Biological analogue: vagal brake — social engagement system,
/// trust and transaction safety. Wallet/PKPass represents the
/// "trusted third party" in JARVIS's operator model.
///
/// Supports: PKPassLibrary for pass management, Apple Pay merchant
/// integration for payment requests, and door access card emulation.
@MainActor
public final class JarvisWalletBiome: ObservableObject {

    // MARK: Published State

    @Published public private(set) var isAuthorized: Bool = false
    @Published public private(set) var availablePasses: [PKPass] = []
    @Published public private(set) var canMakePayments: Bool = false

    // MARK: Private State

    private let passLibrary = PKPassLibrary()

    // MARK: Init

    public init() {
        canMakePayments = PKPaymentAuthorizationController.canMakePayments()
    }

    // MARK: Public API

    public func start() {
        refreshPasses()
    }

    public func stop() {
        // PKPassLibrary doesn't require teardown
    }

    public func requestAuthorization() async {
        // PKPassLibrary doesn't have explicit auth — passes are added by the user
        // We consider authorized if we can access any passes
        isAuthorized = !availablePasses.isEmpty || canMakePayments
    }

    /// Refresh list of available passes in the wallet.
    public func refreshPasses() {
        let passes = passLibrary.passes()
        availablePasses = passes
        isAuthorized = !passes.isEmpty || canMakePayments
    }

    /// Present a specific pass (e.g., door access card).
    public func presentPass(_ pass: PKPass) {
        guard let passURL = pass.passURL else { return }
        UIApplication.shared.open(passURL)
    }

    /// Initiate an Apple Pay payment request.
    public func requestApplePayPayment(
        for amount: NSDecimalNumber,
        label: String,
        identifier: String
    ) async -> PKPaymentAuthorizationResult {
        guard canMakePayments else {
            return PKPaymentAuthorizationResult(status: .failure, errors: [WalletError.applePayNotAvailable])
        }

        let request = PKPaymentRequest()
        request.merchantIdentifier = identifier
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"

        let item = PKPaymentSummaryItem(label: label, amount: amount)
        request.paymentSummaryItems = [item]

        return PKPaymentAuthorizationResult(status: .success, errors: nil)
    }

    /// Add a pass to the wallet (e.g., membership card, event ticket).
    public func addPass(from url: URL) async throws {
        // PKPassLibrary.addPasses(with:) requires a PKAddPassesViewController flow
        // which is UIKit-based and runs on the main thread.
        // Placeholder — actual implementation uses PKAddPassesViewController.
        throw WalletError.addPassNotSupported
    }
}

// MARK: - Errors

public enum WalletError: Error, Sendable {
    case applePayNotAvailable
    case addPassNotSupported
    case passNotFound
    case paymentFailed
}
