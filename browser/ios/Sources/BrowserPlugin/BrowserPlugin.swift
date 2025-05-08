import Foundation
import Capacitor

@objc(CAPBrowserPlugin)
public class CAPBrowserPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CAPBrowserPlugin"
    public let jsName = "Browser"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "open", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "close", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = Browser()

    @objc func open(_ call: CAPPluginCall) {
        print("🔍 [BrowserPlugin] Opening browser")
        // validate the URL
        guard let urlString = call.getString("url"), let url = URL(string: urlString) else {
            print("❌ [BrowserPlugin] Invalid URL: \(call.getString("url") ?? "nil")")
            call.reject("Must provide a valid URL to open")
            return
        }
        print("🔍 [BrowserPlugin] URL: \(url.absoluteString)")
        // extract the optional parameters
        var color: UIColor?
        if let toolbarColor = call.getString("toolbarColor") {
            color = UIColor.capacitor.color(fromHex: toolbarColor)
        }
        let style = self.presentationStyle(for: call.getString("presentationStyle"))

        // Check for ASWebAuthenticationSession flag
        let useWebAuthSession = call.getBool("useASWebAuthenticationSession") ?? false
        print("🔍 [BrowserPlugin] Using ASWebAuthenticationSession: \(useWebAuthSession)")
        if useWebAuthSession {
            let callbackUrlScheme = call.getString("callbackUrlScheme")
            let prefersEphemeral = call.getBool("prefersEphemeralWebBrowserSession") ?? false
            print("🔍 [BrowserPlugin] Callback URL Scheme: \(callbackUrlScheme ?? "nil")")
            print("🔍 [BrowserPlugin] Prefers Ephemeral: \(prefersEphemeral)")
            implementation.browserEventDidOccur = { [weak self] (event) in
                print("🔍 [BrowserPlugin] Browser event: \(event)")
                if event == .finished {
                    // Try to get the callback URL
                    if let callbackURL = self?.implementation.getLastCallbackURL() {
                        self?.notifyListeners("browserCallbackReceived", data: ["url": callbackURL])
                    }
                    call.resolve()
                    self?.notifyListeners("browserFinished", data: nil)
                } else {
                    self?.notifyListeners(event.listenerEvent, data: nil)
                }
            }
            implementation.prepareWebAuthSession(for: url, callbackURLScheme: callbackUrlScheme, prefersEphemeral: prefersEphemeral) { started in
                if !started {
                    print("❌ [BrowserPlugin] Failed to start ASWebAuthenticationSession")
                    call.reject("Unable to start ASWebAuthenticationSession")
                } else {
                    print("✅ [BrowserPlugin] Successfully started ASWebAuthenticationSession")
                }
            }
            return
        }
        // prepare for display
        guard implementation.prepare(for: url, withTint: color, modalPresentation: style), let viewController = implementation.viewController else {
            print("❌ [BrowserPlugin] Unable to display URL")
            call.reject("Unable to display URL")
            return
        }
        implementation.browserEventDidOccur = { [weak self] (event) in
            print("🔍 [BrowserPlugin] Browser event: \(event)")
            if event == .finished {
                self?.bridge?.dismissVC(animated: true, completion: {
                    self?.notifyListeners(event.listenerEvent, data: nil)
                })
            } else {
                self?.notifyListeners(event.listenerEvent, data: nil)
            }
        }
        // display
        DispatchQueue.main.async { [weak self] in
            if style == .popover {
                if let width = call.getInt("width"), let height = call.getInt("height") {
                    self?.setCenteredPopover(viewController, size: CGSize.init(width: width, height: height))
                } else {
                    self?.setCenteredPopover(viewController)
                }
            }
            self?.bridge?.presentVC(viewController, animated: true, completion: {
                print("✅ [BrowserPlugin] Presented SFSafariViewController")
                call.resolve()
            })
        }
    }

    @objc func close(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            if self?.implementation.viewController != nil {
                self?.bridge?.dismissVC(animated: true) {
                    call.resolve()
                    self?.implementation.cleanup()
                }
            } else {
                call.reject("No active window to close!")
            }
        }
    }

    private func presentationStyle(for style: String?) -> UIModalPresentationStyle {
        if let style = style, style == "popover" {
            return .popover
        }
        return .fullScreen
    }
}

private extension BrowserEvent {
    var listenerEvent: String {
        switch self {
        case .loaded:
            return "browserPageLoaded"
        case .finished:
            return "browserFinished"
        }
    }
}
