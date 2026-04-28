import CarPlay
import UIKit
import SwiftUI
import WebKit
import AVFoundation

/// GrizzOS CarPlay Integration
/// "Mark LXVIII" Ambient Vehicle Interface
/// 100% Generative UI with Functional YouTube/Video Support
public class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    public var interfaceController: CPInterfaceController?
    private var mapTemplate: CPMapTemplate?
    private var carWindow: UIWindow?
    private var webView: WKWebView?

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                         didConnect interfaceController: CPInterfaceController,
                                         to window: CPWindow) {

        self.interfaceController = interfaceController
        self.carWindow = window

        // Configure audio session for multi-route playback
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowBluetooth, .allowAirPlay])
        try? session.setActive(true)

        print("[GrizzOS] CarPlay Dashboard Connected.")

        setupNavigationTemplate()
        setupVideoLayer(on: window)
        setupGenerativeUIListener()
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                         didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        self.carWindow = nil
    }

    private func setupNavigationTemplate() {
        let mapTemplate = CPMapTemplate()
        self.mapTemplate = mapTemplate
        self.interfaceController?.setRootTemplate(mapTemplate, animated: true, completion: nil)
    }

    private func setupGenerativeUIListener() {
        NotificationCenter.default.addObserver(forName: Notification.Name("com.grizzos.generateCarPlayUI"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let mapTemplate = self.mapTemplate else { return }
            if let buttonsData = notification.userInfo?["buttons"] as? [[String: String]] {
                var generatedButtons: [CPMapButton] = []
                for btnData in buttonsData {
                    guard let iconName = btnData["icon"], let actionId = btnData["actionId"] else { continue }
                    let newButton = CPMapButton { _ in
                        NotificationCenter.default.post(name: Notification.Name("com.grizzos.actionExecuted"), object: nil, userInfo: ["actionId": actionId])
                    }
                    if let image = UIImage(systemName: iconName) { newButton.image = image }
                    generatedButtons.append(newButton)
                }
                mapTemplate.mapButtons = generatedButtons
            }
        }
    }

    private func setupVideoLayer(on window: CPWindow) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: window.bounds, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = self

        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.addSubview(webView)
        webView.frame = vc.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        self.webView = webView
        window.rootViewController = vc
        window.isHidden = false

        NotificationCenter.default.addObserver(forName: Notification.Name("com.grizzos.playVideoFeed"), object: nil, queue: .main) { [weak self] notification in
            if let urlString = notification.userInfo?["url"] as? String {
                self?.loadVideo(urlString: urlString)
            }
        }
    }

    private func loadVideo(urlString: String) {
        guard let webView = self.webView else { return }
        if urlString.contains("youtube.com") || urlString.contains("youtu.be") {
            let videoId = extractYoutubeId(from: urlString)
            let embedUrl = "https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&controls=0&modestbranding=1"
            if let url = URL(string: embedUrl) {
                webView.load(URLRequest(url: url))
            }
        } else if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    private func extractYoutubeId(from url: String) -> String {
        let pattern = "((?<=(v|V)/)|(?<=be/)|(?<=(\\?|\\&)v=)|(?<=embed/))([\\w-]++)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.count)) {
            return (url as NSString).substring(with: match.range)
        }
        return url
    }
}

extension CarPlaySceneDelegate: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementsByTagName('video')[0].play();", completionHandler: nil)
    }
}
