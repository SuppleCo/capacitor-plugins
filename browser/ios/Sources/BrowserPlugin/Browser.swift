import Foundation
import SafariServices
import AuthenticationServices

@objc public enum BrowserEvent: Int {
    case loaded
    case finished
}

@objc public class Browser: NSObject, SFSafariViewControllerDelegate, UIPopoverPresentationControllerDelegate, ASWebAuthenticationPresentationContextProviding {
    private var safariViewController: SFSafariViewController?
    private var webAuthSession: ASWebAuthenticationSession?
    private var lastCallbackURL: URL?
    public typealias BrowserEventCallback = (BrowserEvent) -> Void

    @objc public var browserEventDidOccur: BrowserEventCallback?
    @objc var viewController: UIViewController? {
        return safariViewController
    }

    @objc public func prepare(for url: URL, withTint tint: UIColor? = nil, modalPresentation style: UIModalPresentationStyle = .fullScreen) -> Bool {
        if safariViewController == nil, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            let safariVC = SFSafariViewController(url: url)
            safariVC.delegate = self
            if let color = tint {
                safariVC.preferredBarTintColor = color
            }
            safariVC.modalPresentationStyle = style
            if style == .popover {
                DispatchQueue.main.async {
                    safariVC.popoverPresentationController?.delegate = self
                }
            }
            safariViewController = safariVC
            return true
        }
        return false
    }

    @objc public func cleanup() {
        safariViewController = nil
        webAuthSession = nil
    }

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        browserEventDidOccur?(.finished)
        safariViewController = nil
    }

    public func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        browserEventDidOccur?(.loaded)
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        browserEventDidOccur?(.finished)
        safariViewController = nil
    }

    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        browserEventDidOccur?(.finished)
        safariViewController = nil
    }

    // MARK: - ASWebAuthenticationSession
    @objc public func prepareWebAuthSession(for url: URL, callbackURLScheme: String?, prefersEphemeral: Bool = false, completion: @escaping (Bool) -> Void) {
        print("🔍 [Browser] Preparing ASWebAuthenticationSession")
        print("🔍 [Browser] URL: \(url.absoluteString)")
        print("🔍 [Browser] Callback URL Scheme: \(callbackURLScheme ?? "nil")")
        print("🔍 [Browser] Prefers Ephemeral: \(prefersEphemeral)")
        // Validate URL
        guard url.scheme?.lowercased() == "https" else {
            print("❌ [Browser] Error: URL must be HTTPS")
            completion(false)
            return
        }
        // Validate callback scheme
        guard let callbackScheme = callbackURLScheme, !callbackScheme.isEmpty else {
            print("❌ [Browser] Error: Callback URL scheme is required")
            completion(false)
            return
        }
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            if let error = error {
                print("❌ [Browser] ASWebAuthenticationSession error: \(error.localizedDescription)")
            }
            if let callbackURL = callbackURL {
                print("✅ [Browser] Received callback URL: \(callbackURL.absoluteString)")
                self?.lastCallbackURL = callbackURL
                self?.browserEventDidOccur?(.finished)
            } else {
                print("⚠️ [Browser] No callback URL received")
                self?.browserEventDidOccur?(.finished)
            }
            self?.webAuthSession = nil
        }
        if #available(iOS 13.0, *) {
            session.prefersEphemeralWebBrowserSession = prefersEphemeral
            print("🔍 [Browser] Set ephemeral session: \(prefersEphemeral)")
        }
        session.presentationContextProvider = self
        self.webAuthSession = session
        let started = session.start()
        print("🔍 [Browser] Session start result: \(started)")
        completion(started)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Use the key window, which is what SFSafariViewController would use
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        // Fallback: return a new window if none found
        return ASPresentationAnchor()
    }

    @objc public func getLastCallbackURL() -> String? {
        return lastCallbackURL?.absoluteString
    }
}
