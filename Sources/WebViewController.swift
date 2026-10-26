// WebViewController.swift – HARIVAS iOS
// Full WKWebView host for all 5 portals

import UIKit
import WebKit
import SafariServices
import UserNotifications
import LocalAuthentication
import CoreLocation

final class WebViewController: UIViewController {

    // MARK: - Configuration

    private var siteURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SITE_URL") as? String ?? "https://gkgos.in"
    }

    private var portalPath: String {
        Bundle.main.object(forInfoDictionaryKey: "PORTAL_PATH") as? String ?? "/"
    }

    private var portalURL: URL {
        URL(string: siteURL + portalPath)!
    }

    private var hostName: String {
        URL(string: siteURL)?.host ?? "gkgos.in"
    }

    /// Portals that require biometric auth before loading
    private let sensitivePortals = ["/harivas-rider/", "/harivas-staff/", "/harivas-admin/", "/harivas-vendor/"]

    // MARK: - Properties

    private var webView: WKWebView!
    private var refreshControl: UIRefreshControl!
    private var offlineView: UIView!
    private var offlineLabel: UILabel!
    private var retryButton: UIButton!
    private var imagePickerCompletion: ((URL?) -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupOfflineView()
        requestPushPermission()

        if sensitivePortals.contains(portalPath) {
            performBiometricAuth { [weak self] success in
                if success {
                    self?.loadPortal()
                } else {
                    // Biometric failed – app stays on blank screen, user can retry
                    self?.showBiometricFailedAlert()
                }
            }
        } else {
            loadPortal()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
        offlineView.frame = view.bounds
    }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // User content controller for JS→native bridge
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "hvNativeHandler")

        // Inject HvNative bridge after every page load
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let bridgeScript = """
        window.HvNative = {
            isIOSApp: true,
            getAppVersion: function() { return '\(appVersion)'; },
            startLocationTracking: function(orderId) {
                window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'startLocation', orderId: orderId });
            },
            stopLocationTracking: function() {
                window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'stopLocation' });
            },
            requestNotificationPermission: function() {
                window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'requestNotification' });
            }
        };
        """
        let script = WKUserScript(source: bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(script)
        config.userContentController = userContentController

        // Custom user agent
        let defaultUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        config.applicationNameForUserAgent = "HarivasIOS/1.0"

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.customUserAgent = "\(defaultUA) HarivasIOS/1.0"

        // Sync HTTPCookies to WKWebView
        syncCookiesToWebView()

        view.addSubview(webView)

        // Pull-to-refresh
        refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        webView.scrollView.addSubview(refreshControl)

        // Swipe-back gesture
        let swipeBack = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeBack))
        swipeBack.direction = .right
        swipeBack.delegate = self
        webView.addGestureRecognizer(swipeBack)

        // Observe scroll to manage pull-to-refresh availability
        webView.scrollView.delegate = self
    }

    private func setupOfflineView() {
        offlineView = UIView(frame: view.bounds)
        offlineView.backgroundColor = .systemBackground
        offlineView.isHidden = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "wifi.slash"))
        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80)
        ])

        offlineLabel = UILabel()
        offlineLabel.text = "No Internet Connection"
        offlineLabel.font = .preferredFont(forTextStyle: .headline)
        offlineLabel.textColor = .secondaryLabel
        offlineLabel.textAlignment = .center

        let subLabel = UILabel()
        subLabel.text = "Please check your connection and try again."
        subLabel.font = .preferredFont(forTextStyle: .subheadline)
        subLabel.textColor = .tertiaryLabel
        subLabel.textAlignment = .center
        subLabel.numberOfLines = 0

        retryButton = UIButton(type: .system)
        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.addTarget(self, action: #selector(retryConnection), for: .touchUpInside)

        var config = UIButton.Configuration.filled()
        config.title = "Retry"
        config.cornerStyle = .capsule
        retryButton.configuration = config

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(offlineLabel)
        stack.addArrangedSubview(subLabel)
        stack.addArrangedSubview(retryButton)

        offlineView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: offlineView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: offlineView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: offlineView.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: offlineView.trailingAnchor, constant: -40)
        ])

        view.addSubview(offlineView)
    }

    // MARK: - Loading

    private func loadPortal() {
        var request = URLRequest(url: portalURL)
        request.cachePolicy = .returnCacheDataElseLoad
        webView.load(request)
    }

    // MARK: - Push Permissions

    private func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    // MARK: - Biometric Auth

    private func performBiometricAuth(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometric/passcode available; let through
            completion(true)
            return
        }

        let reason = "Authenticate to access your HARIVAS portal"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private func showBiometricFailedAlert() {
        let alert = UIAlertController(
            title: "Authentication Required",
            message: "You must authenticate to access this portal.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
            self?.performBiometricAuth { success in
                if success { self?.loadPortal() }
                else { self?.showBiometricFailedAlert() }
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Cookie Sync

    private func syncCookiesToWebView() {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in cookies {
            store.setCookie(cookie)
        }
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        webView.reload()
    }

    @objc private func retryConnection() {
        offlineView.isHidden = true
        loadPortal()
    }

    @objc private func handleSwipeBack(_ gesture: UISwipeGestureRecognizer) {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    // MARK: - Helpers

    private func showOfflineView() {
        DispatchQueue.main.async { [weak self] in
            self?.offlineView.isHidden = false
            self?.refreshControl.endRefreshing()
        }
    }

    private func isExternalURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host != hostName
    }
}

// MARK: - UIScrollViewDelegate

extension WebViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only allow pull-to-refresh when at top of page
        refreshControl.isEnabled = scrollView.contentOffset.y <= 0
    }
}

// MARK: - UIGestureRecognizerDelegate

extension WebViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}

// MARK: - WKNavigationDelegate

extension WebViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        // Intercept special schemes
        let interceptSchemes = ["tel", "mailto", "maps", "upi", "razorpay", "phonepe", "telprompt"]
        if interceptSchemes.contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        // External https links → SFSafariViewController
        if (scheme == "https" || scheme == "http") && isExternalURL(url) {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = view.tintColor
            present(safari, animated: true)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        offlineView.isHidden = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()

        // Re-inject bridge after each page load (belt-and-suspenders)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let evalScript = """
        if (typeof window.HvNative === 'undefined') {
            window.HvNative = {
                isIOSApp: true,
                getAppVersion: function() { return '\(appVersion)'; },
                startLocationTracking: function(orderId) {
                    window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'startLocation', orderId: orderId });
                },
                stopLocationTracking: function() {
                    window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'stopLocation' });
                },
                requestNotificationPermission: function() {
                    window.webkit.messageHandlers.hvNativeHandler.postMessage({ action: 'requestNotification' });
                }
            };
        }
        """
        webView.evaluateJavaScript(evalScript, completionHandler: nil)

        // Persist cookies back to HTTPCookieStorage
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        refreshControl.endRefreshing()
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            showOfflineView()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            showOfflineView()
        }
    }
}

// MARK: - WKUIDelegate

extension WebViewController: WKUIDelegate {

    // Geolocation auto-granted (iOS already asks user via CLLocationManager)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    // File upload via camera / photo library
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let alert = UIAlertController(title: "Choose Photo", message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
                self?.presentImagePicker(sourceType: .camera) { url in
                    completionHandler(url.map { [$0] })
                }
            })
        }

        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentImagePicker(sourceType: .photoLibrary) { url in
                completionHandler(url.map { [$0] })
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(nil)
        })

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }

        present(alert, animated: true)
    }

    private func presentImagePicker(
        sourceType: UIImagePickerController.SourceType,
        completion: @escaping (URL?) -> Void
    ) {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = self
        imagePickerCompletion = completion
        present(picker, animated: true)
    }

    // WKUIDelegate alert shims so JS alert/confirm/prompt work
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { tf in tf.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}

// MARK: - WKScriptMessageHandler (JS→Native Bridge)

extension WebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "hvNativeHandler",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "startLocation":
            let orderId = body["orderId"] as? String ?? ""
            LocationManager.shared.startTracking(orderId: orderId)
        case "stopLocation":
            LocationManager.shared.stopTracking()
        case "requestNotification":
            requestPushPermission()
        default:
            break
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension WebViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)

        if let url = info[.imageURL] as? URL {
            imagePickerCompletion?(url)
        } else if let image = info[.originalImage] as? UIImage {
            // Save to temp file and return URL
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(UUID().uuidString).jpg")
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: tempURL)
                imagePickerCompletion?(tempURL)
            } else {
                imagePickerCompletion?(nil)
            }
        } else {
            imagePickerCompletion?(nil)
        }
        imagePickerCompletion = nil
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        imagePickerCompletion?(nil)
        imagePickerCompletion = nil
    }
}
