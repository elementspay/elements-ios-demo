//
//  ElementsDemoViewController.swift
//  Elements-iOS-Demo
//
//  Created by Tengqi Zhan on 2021-05-08.
//

import Elements
import ElementsCard
import NetworkMonitor
import UIKit

final class ElementsDemoViewController: UIViewController {

	private let clientToken = "TODO: Your client token fetched from backend goes here..."
	private let stripeKey = "TODO: Optional if you want to provide your Stripe publishable key as a fall back method..."

	private var currentViewController: UIViewController?
	private var cardComponent: CardComponent?
	private var monitorCoordinator: NetworkMonitorCoordinator?

	private lazy var apiClient: ElementsAPIClient = {
		return ElementsAPIClient(
			config: .init(
				environment: .sandbox(clientToken: clientToken),
				stripePublishableKey: stripeKey
			)
		)
	}()

	override func viewDidLoad() {
		super.viewDidLoad()
		presentCardComponent()
	}

	override public func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		showNetworkMonitor()
	}

	private func presentCardComponent() {
		let brands: [SupportedCardData] = [
			"visa", "master", "discover"
		].map { SupportedCardData(brand: $0) }
		let config = CardComponent.Configuration(
			showsHolderNameField: true,
			showsStorePaymentMethodField: false,
			billingAddressMode: .none
		)
		cardComponent = CardComponent(
			paymentMethod: CardPaymentMethod(
				type: "scheme",
				name: "Elements Demo",
				fundingSource: nil,
				cardData: brands
			),
			configuration: config
		)
		cardComponent?.environment = .sandbox(clientToken: clientToken)
		cardComponent?.cardComponentDelegate = self
		cardComponent?.delegate = self

		guard let cardComponent = cardComponent else { return }
		let navVC = UINavigationController(rootViewController: cardComponent.viewController)
		cardComponent.viewController.navigationItem.setRightBarButton(UIBarButtonItem(image: UIImage(named: "network_monitor_image")?.withRenderingMode(.alwaysOriginal), style: .plain, target: self, action: #selector(rightNavBarButtonTapped)), animated: false)
		replaceScreen(viewController: navVC)
	}

	private func tokenizeCard(card: ElementsCardParams) {
		apiClient.tokenizeCard(data: card) { [weak self] result in
			guard let self = self else { return }
			self.cardComponent?.stopLoadingIfNeeded()
			switch result {
			case .success(let response):
				if let elementsToken = response.elementsToken {
					self.presentAlertView(title: "Tokenization success!", message: self.parseElementsTokenToDisplayString(token: elementsToken))
				}
				if let fallbackStripeToken = response.fallbackStripeToken {
					self.presentAlertView(title: "Stripe tokenization success!", message: "Stripe: \(fallbackStripeToken)")
				}
			case .failure(let error):
				if let apiError = error as? ElementsAPIError {
					self.presentAlertView(title: "Error", message: apiError.errorMessage)
				} else {
					self.presentAlertView(title: "Error", message: error.localizedDescription)
				}
			}
		}
	}
}

extension ElementsDemoViewController {

	private func presentAlertView(title: String, message: String, completion: (() -> Void)? = nil) {
		let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
		alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: { _ in
			completion?()
		}))
		present(alert, animated: true, completion: nil)
	}

	private func replaceScreen(viewController: UIViewController) {
		viewController.willMove(toParent: self)
		addChild(viewController)
		view.addSubview(viewController.view)
		viewController.view.frame = view.frame
		currentViewController?.willMove(toParent: nil)
		currentViewController?.view.removeFromSuperview()
		currentViewController?.removeFromParent()
		viewController.didMove(toParent: self)
		currentViewController = viewController
	}

	private func parseElementsTokenToDisplayString(token: ElementsToken) -> String {
		var result = "Elements Token Object\n"
		let pspTokens = token.pspTokens.reduce("", { $0 + "\($1.pspAccount.pspType.lowercased()): \($1.token)" })
		result += "Psp Tokens\n\(pspTokens)"
		result += "\nElements Card\n"
		var cardDisplay = "Card id: \(token.card?.id ?? "Unknown")\n"
		let brand = token.card?.brand ?? "Unknown brand"
		let last4 = token.card?.last4 ?? "Unknown last 4"
		cardDisplay += "Brand: \(brand)\nLast4: \(last4)"
		result += cardDisplay
		return result
	}
}

extension ElementsDemoViewController: CardComponentDelegate {
	func didChangeBIN(_ value: String, component: CardComponent) {
	}

	func didChangeCardBrand(_ value: [CardBrand]?, component: CardComponent) {
	}
}

extension ElementsDemoViewController: PaymentComponentDelegate {
	func didSubmit(_ data: PaymentComponentData, from component: PaymentComponent) {
		guard let cardDetails = data.paymentMethod as? CardDetails else {
			print("Error: Failed getting card details from payment method.")
			return
		}
		guard let card = cardDetails.card else {
			print("Error: Card number is missing.")
			return
		}
		tokenizeCard(card: card)
	}

	func didFail(with error: Error, from component: PaymentComponent) {
		print("Opps something went wrong \(error)")
	}
}

extension ElementsDemoViewController {

	private func showNetworkMonitor() {
		guard NetworkMonitor.shared.isEnabled() else { return }
		monitorCoordinator = NetworkMonitorCoordinator()
		monitorCoordinator?.delegate = self
		monitorCoordinator?.start()
		var topController: UIViewController? = UIApplication.shared.windows.filter { $0.isKeyWindow }.first?.rootViewController
		while topController?.presentedViewController != nil {
			topController = topController?.presentedViewController
		}
		topController?.present(monitorCoordinator!.toPresentable(), animated: true)
	}

	@objc
	private func rightNavBarButtonTapped() {
		showNetworkMonitor()
	}
}

extension ElementsDemoViewController: NetworkMonitorCoordinatorDelegate {
	func didDismiss(in coordinator: NetworkMonitorCoordinator) {
		monitorCoordinator = nil
	}
}