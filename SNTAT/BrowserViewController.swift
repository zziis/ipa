import UIKit
import WebKit

/// iOS counterpart of the Android WebActivity. Uses persistent WKWebView storage.
/// Web accounts are never copied from Android; users sign in once on each device.
final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let siteURL = URL(string: "https://sntat.app/")!
    private let mainHost = "sntat.app"
    private var webView: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let offlinePanel = UIView()
    private let backButton = UIButton(type: .system)
    private var progressObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var downloads: [ObjectIdentifier: URL] = [:]

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        configureBrowser()
        configureControls()
        webView.load(URLRequest(url: siteURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    private func configureBrowser() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Cookies + localStorage survive normal app restarts.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.backgroundColor = .white
        web.isOpaque = false
        web.scrollView.backgroundColor = .white
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        webView = web
        progressObservation = web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            DispatchQueue.main.async {
                self?.progress.progress = Float(web.estimatedProgress)
                self?.progress.isHidden = web.estimatedProgress >= 1
            }
        }
        backObservation = web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] web, _ in
            DispatchQueue.main.async { self?.backButton.isHidden = !web.canGoBack }
        }
    }

    private func configureControls() {
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = UIColor(red: 0.00, green: 0.69, blue: 0.72, alpha: 1)
        progress.trackTintColor = .clear
        progress.isHidden = true
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2)
        ])

        // Minimal floating back affordance when the website has navigation history.
        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.tintColor = .white
        backButton.backgroundColor = UIColor(red: 0.00, green: 0.64, blue: 0.69, alpha: 0.87)
        backButton.layer.cornerRadius = 22
        backButton.accessibilityLabel = "رجوع"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.isHidden = true
        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        offlinePanel.translatesAutoresizingMaskIntoConstraints = false
        offlinePanel.backgroundColor = .white
        offlinePanel.isHidden = true
        view.addSubview(offlinePanel)
        NSLayoutConstraint.activate([
            offlinePanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            offlinePanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            offlinePanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            offlinePanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let message = UILabel()
        message.text = "تعذّر الاتصال بالمنصة. تحقق من الإنترنت وحاول مجددًا."
        message.textAlignment = .center
        message.numberOfLines = 0
        message.textColor = .darkGray
        message.font = .systemFont(ofSize: 17)
        let retry = UIButton(type: .system)
        retry.setTitle("إعادة المحاولة", for: .normal)
        retry.backgroundColor = UIColor(red: 0.0, green: 0.68, blue: 0.71, alpha: 1)
        retry.setTitleColor(.white, for: .normal)
        retry.titleLabel?.font = .boldSystemFont(ofSize: 16)
        retry.layer.cornerRadius = 22
        retry.heightAnchor.constraint(equalToConstant: 44).isActive = true
        retry.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, retry])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        offlinePanel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: offlinePanel.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: offlinePanel.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: offlinePanel.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: offlinePanel.trailingAnchor, constant: -36),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        ])
    }

    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func retryLoading() {
        offlinePanel.isHidden = true
        if webView.url == nil { webView.load(URLRequest(url: siteURL)) }
        else { webView.reload() }
    }

    func loadSntatURL(_ url: URL) {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == mainHost else { return }
        webView?.load(URLRequest(url: url))
    }

    func handleReturnURL(_ url: URL) {
        guard url.scheme?.lowercased() == "sntat" else { return }
        // sntat://auth/callback?code=... is mapped to https://sntat.app/auth/callback?code=...
        // Actual OAuth providers MUST be configured to permit this callback.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let hostPart = url.host.map { "/" + $0 } ?? ""
        let rawPath = (hostPart + url.path).isEmpty ? "/" : (hostPart + url.path)
        guard !rawPath.contains("..") else { return }
        var target = URLComponents()
        target.scheme = "https"
        target.host = mainHost
        target.path = rawPath
        target.percentEncodedQuery = components?.percentEncodedQuery
        target.fragment = components?.fragment
        if let builtURL = target.url { webView?.load(URLRequest(url: builtURL)) }
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if ["tel", "mailto", "sms", "whatsapp", "tg", "fb", "fb-messenger"].contains(scheme) { return true }
        guard scheme == "https" || scheme == "http" else { return false }
        let host = url.host?.lowercased() ?? ""
        if scheme == "http" { return true }
        let hosts = ["wa.me", "api.whatsapp.com", "web.whatsapp.com", "whatsapp.com",
                     "t.me", "telegram.me", "telegram.org", "fb.me", "fb.com",
                     "facebook.com", "m.facebook.com", "mbasic.facebook.com", "messenger.com"]
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if shouldOpenExternally(url) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        guard ["https", "about", "blob", "data", "file"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            return
        }
        // Pages opening target=_blank remain inside the existing WKWebView.
        if navigationAction.targetFrame == nil && url.scheme == "https" {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        offlinePanel.isHidden = true
        progress.isHidden = false
        progress.progress = 0.05
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        offlinePanel.isHidden = true
        progress.isHidden = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { offlinePanel.isHidden = false }
        progress.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { offlinePanel.isHidden = false }
        progress.isHidden = true
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if shouldOpenExternally(url) { UIApplication.shared.open(url) }
            else if url.scheme == "https" { webView.load(URLRequest(url: url)) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let host = origin.host.lowercased()
        // Only let pages on the trusted first-party site request camera/microphone.
        decisionHandler(origin.protocol == "https" && (host == mainHost || host.hasSuffix("." + mainHost)) ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "سنتات", message: String(message.prefix(500)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "حسنًا", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "سنتات", message: String(message.prefix(500)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "سنتات", message: String(prompt.prefix(500)), preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true {
            decisionHandler(.download)
        } else if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) { download.delegate = self }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let candidate = (suggestedFilename as NSString).lastPathComponent
        let name = candidate.isEmpty ? "download" : candidate
        let destination = documents.appendingPathComponent(UUID().uuidString + "-" + name)
        downloads[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let fileURL = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let share = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        if view.window != nil { present(share, animated: true) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }
}
