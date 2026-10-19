import UIKit
import AVFoundation

final class IntroViewController: UIViewController {
    var onFinished: (() -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var finishObserver: NSObjectProtocol?
    private var fallback: DispatchWorkItem?
    private var finished = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        playIntro()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.safeAreaLayoutGuide.layoutFrame
    }

    private func playIntro() {
        let fallbackLogo = UIImageView(image: UIImage(named: "SplashLogo"))
        fallbackLogo.contentMode = .scaleAspectFit
        fallbackLogo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fallbackLogo)
        NSLayoutConstraint.activate([
            fallbackLogo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fallbackLogo.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            fallbackLogo.widthAnchor.constraint(equalToConstant: 220),
            fallbackLogo.heightAnchor.constraint(equalToConstant: 220)
        ])
        guard let url = Bundle.main.url(forResource: "intro_video", withExtension: "mp4") else {
            finish()
            return
        }
        // Play the original bundled video with its original AAC sound.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect  // Do not crop the original S logo.
        layer.backgroundColor = UIColor.white.cgColor
        view.layer.addSublayer(layer)
        layer.frame = view.safeAreaLayoutGuide.layoutFrame
        self.player = player
        self.playerLayer = layer

        finishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in self?.finish() }

        let fallback = DispatchWorkItem { [weak self] in self?.finish() }
        self.fallback = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: fallback)
        player.play()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        fallback?.cancel()
        if let observer = finishObserver { NotificationCenter.default.removeObserver(observer) }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerLayer?.removeFromSuperlayer()
        player = nil
        onFinished?()
    }

    deinit {
        fallback?.cancel()
        if let observer = finishObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
