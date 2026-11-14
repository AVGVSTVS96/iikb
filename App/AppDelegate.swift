import KeyboardStore
import Photos
import SwiftUI
import UIKit
import VoiceCapture
import VoiceModels

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        guard !VoiceProbe.asked, !RankingProbe.asked, !JudgeProbe.asked else { return true }
        let photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        Dictation.photosAllowed = photos == .authorized || photos == .limited
        if VoiceModel.hasNeuralEngine { VoiceModel.shared.prepare() }
        LanguageDownloads.shared.reload()
        Task {
            await Transcripts.shared.recover()
            Backup.syncApp()
            await Transcripts.shared.rewriteApple()
        }
        return true
    }
}

/// A probe's launch (`VoiceProbe`, `RankingProbe`, `JudgeProbe`) is the iikb the keyboard dictates into while it runs.
enum Probe {
    /// Quits once the probe is done, unless you've turned the microphone on in it since: then iikb stays, as it would
    /// have, so the microphone stays on.
    @MainActor static func end() {
        guard !Listener.shared.isMicOn else { return }
        exit(0)  // exit: a probe's launch is done
    }
}

/// Which tab shows, and which settings page, so a tile, a link or the keyboard's menu can open one.
@Observable final class Router {
    static let shared = Router()

    enum Destination: String { case home, transcripts, clipboard, stats, settings }

    /// The settings page open on its own, or, wide, the one beside the list.
    var settingsPath: [SettingsPage.Page] = []
    /// Stats' pill.
    var stats = LaunchOptions.statsSection ?? .overview
    /// The computer Stats shows (docs/computers.md), or nil for the iPhone.
    var statsComputer = LaunchOptions.statsComputer
    @ObservationIgnored weak var tabs: UITabBarController?

    func show(_ destination: Destination, settings page: SettingsPage.Page? = nil) {
        if destination == .settings { settingsPath = page.map { [$0] } ?? [] }
        tabs?.selectedTab = tabs?.tab(forIdentifier: destination.rawValue)
    }

    func show(_ section: StatsPage.Section) {
        stats = section
        show(.stats)
    }
}

/// The five tabs, with the dictation going on in their accessory (`DictationBar`) for as long as `Listener` has one to
/// show. In a window narrower than `Arrangement.wide`, as a 13-inch iPad's Split View half, iPadOS's tab bar across the
/// top has no room for all five and scrolls them, so there the window takes the bar an iPhone has, as its pages already
/// take one column.
private final class Tabs: UITabBarController {
    private let dictation = DictationBar()
    private lazy var accessory = UITabAccessory(contentView: dictation)

    override func viewDidLoad() {
        super.viewDidLoad()
        Listener.shared.onLevel = { [dictation] in dictation.hear($0, recorded: $1) }
    }

    override func updateProperties() {
        super.updateProperties()
        let shown = LaunchOptions.dictation ?? Listener.shared.shown
        if let shown { dictation.show(shown) }
        guard (shown != nil) != (bottomAccessory != nil) else { return }
        setBottomAccessory(shown == nil ? nil : accessory, animated: viewIfLoaded?.window != nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if LaunchOptions.dictation == .listening { LaunchOptions.speak(into: dictation) }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let narrow = traitCollection.userInterfaceIdiom == .pad && view.bounds.width < Arrangement.wide
        guard narrow != traitOverrides.contains(UITraitHorizontalSizeClass.self) else { return }
        if narrow {
            traitOverrides.horizontalSizeClass = .compact
        } else {
            traitOverrides.remove(UITraitHorizontalSizeClass.self)
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        LaunchOptions.resetSettingsIfAsked()
        LaunchOptions.applySettings()
        LaunchOptions.applyLook()
        AppStyle.applyTitles()
        VoiceProbe.runIfAsked(then: Probe.end)
        RankingProbe.runIfAsked()
        JudgeProbe.runIfAsked()
        let tabs = Tabs(tabs: [
            UITab(title: "iikb", image: UIImage(systemName: "house"), identifier: Router.Destination.home.rawValue) {
                _ in HomeViewController()
            },
            UITab(
                title: "Transcripts", image: UIImage(systemName: "waveform"),
                identifier: Router.Destination.transcripts.rawValue
            ) { _ in
                Self.hosting(TranscriptsPage())
            },
            UITab(
                title: "Clipboard", image: UIImage(systemName: "list.clipboard"),
                identifier: Router.Destination.clipboard.rawValue
            ) { _ in
                Self.hosting(ClipboardPage())
            },
            UITab(
                title: "Stats", image: UIImage(systemName: "chart.bar.xaxis"),
                identifier: Router.Destination.stats.rawValue
            ) { _ in
                Self.hosting(StatsPage())
            },
            UITab(
                title: "Settings", image: UIImage(systemName: "gearshape"),
                identifier: Router.Destination.settings.rawValue
            ) { _ in
                Self.hosting(SettingsPage())
            },
        ])
        Router.shared.tabs = tabs
        LaunchOptions.route()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        if !Listener.shared.isMicOn { Microphone.rest() }
        MicTab.shared.place(in: window)
        open(options.urlContexts)
    }

    private static func hosting(_ view: some View) -> UIViewController {
        let controller = UIHostingController(rootView: view.readsWindow())
        controller.view.backgroundColor = AppStyle.page
        return controller
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UpdateToast.show(in: window)
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        if let source = contexts.lazy.compactMap({ Source(link: $0.url) }).first { return offer(source) }
        if let added = contexts.lazy.compactMap({ Extension(link: $0.url) }).first { return offer(added) }
        if let computer = contexts.lazy.compactMap({ Computer(link: $0.url) }).first {
            Computers.shared.add(computer)
            Router.shared.statsComputer = computer.name
            return Router.shared.show(.stats)
        }
        if contexts.contains(where: { $0.url == AppLink.settings }) { return AppStatus.openPasteSetting() }
        if contexts.contains(where: { $0.url == AppLink.keyboard }) { return Router.shared.show(.settings) }
        if contexts.contains(where: { $0.url == AppLink.appearance }) {
            return Router.shared.show(.settings, settings: .appearance)
        }
        if contexts.contains(where: { $0.url == AppLink.mic }) {
            Router.shared.show(.home)
            Task { try? await Listener.shared.turnMicOn() }
            return
        }
        if let photos = contexts.lazy.compactMap({ AppLink.Photos($0.url) }).first {
            Task { await allowPhotos(back: photos.back) }
            return
        }
        guard let request = contexts.lazy.compactMap({ Dictation.Request($0.url) }).first else { return }
        let fromSelf = request.host == Bundle.main.bundleIdentifier
        Task { await listen(thenOpen: fromSelf ? nil : request.host) }
    }

    /// Starts listening while iikb is in front, the only place iOS lets a recording begin, then reopens the app you were
    /// typing in. Dictating in iikb's own field it stays put: iOS quits an app that opens itself, and the quit throws
    /// away a Parakeet still getting ready.
    private func listen(thenOpen host: String?) async {
        let asked = Date.now
        await Listener.shared.start()
        guard Listener.shared.isListening else {
            return HostApp.log.notice(
                "not listening after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s")
        }
        let opened = if let host { await HostApp.open(host) } else { false }
        HostApp.log.notice(
            "back to \(host ?? "none", privacy: .public) \(opened ? "opened" : "failed", privacy: .public) after \(Date.now.timeIntervalSince(asked), format: .fixed(precision: 2))s"
        )
    }

    /// Asks iOS for access to the photos, which only an app in front can, for Chats on the keyboard to show them, then
    /// reopens the app you were typing in. The keyboard goes down while iOS asks, since its question squeezed above the
    /// keys hides its buttons, and comes back after only when you stay here: raised on the way out, it would take the
    /// chat the keyboard kept for the app you go back to.
    private func allowPhotos(back host: String?) async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .denied else {
            // iOS asks only once: after Don't Allow, only Settings turns photos on.
            _ = await UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            return
        }
        let typing = UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.firstResponder
        typing?.resignFirstResponder()
        let answer = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        Dictation.photosAllowed = answer == .authorized || answer == .limited
        Dictation.send(.photos)
        if let host, host != Bundle.main.bundleIdentifier, await HostApp.open(host) { return }
        typing?.becomeFirstResponder()
    }

    /// An extension's link asks before its chats open from the bar.
    private func offer(_ added: Extension) {
        let alert = UIAlertController(
            title: "Add “\(added.name)”?",
            message:
                "With Allow Full Access on, its chats open from the keyboard’s bar, and what you write in them goes to \(added.url.host() ?? "it").",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let add = UIAlertAction(title: "Add", style: .default) { _ in
            ExtensionStore.add(added)
            SettingsModel.shared.reload()
        }
        alert.addAction(add)
        alert.preferredAction = add
        present(alert)
    }

    /// A source's link asks before iikb starts telling it what you type.
    private func offer(_ source: Source) {
        let alert = UIAlertController(
            title: "Add “\(source.name)”?",
            message:
                "With Allow Full Access on, iikb will send \(source.url.host() ?? "it") the text of the field you’re typing in, except passwords and codes, and show the hints it answers with above the keys.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Add", style: .default) { _ in
                SourceStore.add(source)
                SettingsModel.shared.reload()
            })
        present(alert)
    }

    private func present(_ alert: UIAlertController) {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(alert, animated: true)
    }
}

extension UIView {
    /// The view being typed in, this one or one inside it.
    fileprivate var firstResponder: UIView? {
        isFirstResponder ? self : subviews.lazy.compactMap(\.firstResponder).first
    }
}
