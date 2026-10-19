import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var browserController: BrowserViewController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = .white
        let intro = IntroViewController()
        intro.onFinished = { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            let browser = BrowserViewController()
            self.browserController = browser
            UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {
                window.rootViewController = browser
            })
        }
        window.rootViewController = intro
        self.window = window
        window.makeKeyAndVisible()
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Requires the website / OAuth provider to use sntat:// as its callback.
        guard url.scheme?.lowercased() == "sntat" else { return false }
        browserController?.handleReturnURL(url)
        return true
    }

    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Universal Links only work if sntat.app serves a valid AASA file
        // and the app has properly signed Associated Domains entitlements.
        guard let url = userActivity.webpageURL,
              url.host?.lowercased() == "sntat.app" else { return false }
        browserController?.loadSntatURL(url)
        return true
    }
}
