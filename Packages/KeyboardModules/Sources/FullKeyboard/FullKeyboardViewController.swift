import KeyboardCore
import KeyboardEnglish
import KeyboardStore
import KeyboardUI
import OSLog
import UIKit

open class FullKeyboardViewController: UIInputViewController {
    open var hapticsEnabled: Bool { hasFullAccess && engine.settings.haptics != .off }

    private let keyboardView = KeyboardView()
    private var dictation = Dictation.Status()
    private var micIsOn = false
    /// How much the app has recorded of the dictation it's making, in seconds.
    private var recorded: Double = 0
    private var observers: [Int32] = []
    /// Who this keyboard is to the app, new each time it appears: dictations you stop here are typed here.
    private var keyboard = UInt64.random(in: 1 ... .max)
    /// What the app told you about a dictation, or why copy or paste couldn't, until you tap it or a key.
    private var notice: String?
    /// The menu is in the keys' place (docs/design.md, "The menu"), until something in it is used or the More button is
    /// tapped again.
    private var menuOpen = false
    /// A newer build is on the install link (`InstallLink`), as last read when the keyboard appeared.
    private var updateOffered = false
    private let suggestionBar = SuggestionBar()
    /// The record button in the bottom row, where Settings › Layout › Record Key puts it in the globe's place.
    private let keyMic = MicButton()
    /// Dictation in the keyboard itself while the app's microphone is off (`LocalDictation`): a tap on the mic
    /// hears and writes down what you say without the app ever coming to the front.
    private lazy var localDictation = LocalDictation(host: view)
    /// Whether the keys' layout has the Record Key. While the keys are out of sight (a chat with the keys down, the
    /// menu, a panel in their place) the mic is the bar's, so there's always the one mic to tap.
    private var keyed = false
    private let panelView = PanelView()
    private let menuView = MenuView()
    private let toolbarView = UIView()
    private var toolbar = KeyboardMetrics.phone(width: 390).toolbar
    private lazy var emojiPanel: EmojiPanel = {
        let panel = EmojiPanel()
        panel.onPick = { [unowned self] emoji, base in
            feedback(.input)
            handle(.emoji(emoji, base: base))
        }
        panel.history = { [unowned self] in engine.emojiHistory }
        panel.onKey = { [unowned self] in handle($0) }
        panel.onLetters = { [unowned self] in
            feedback(.other)
            handle(.panel(nil))
        }
        panel.onCategory = { [unowned self] in feedback(.other) }
        return panel
    }()
    private lazy var gifPanel: GifPanel? = Klipy.shared.map { klipy in
        let panel = GifPanel(klipy: klipy)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.app = { [unowned self] in hostApp }
        panel.onCopied = { [unowned self] in clipboard.skip(changeCount: $0) }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.changed = { [unowned self] in noticed(panel.notice) }
        panel.clearSearch = { [unowned self] in handle(.panel(.gif)) }
        return panel
    }
    private lazy var clipboardPanel: ClipboardPanel = {
        let panel = ClipboardPanel(store: clipboard)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPaste = { [unowned self] in paste($0) }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.changed = { [unowned self] in noticed(panel.notice) }
        panel.length = { [unowned self] in engine.settings.clipboardLength }
        return panel
    }()
    private lazy var transcriptsPanel: TranscriptsPanel = {
        let panel = TranscriptsPanel()
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPaste = { [unowned self] in paste($0) }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        return panel
    }()
    /// Your quicklinks, read with the settings.
    private var quicklinks: [Quicklink] = []
    private lazy var snippetsPanel: SnippetsPanel = {
        let panel = SnippetsPanel(.snippets)
        panel.items = { [unowned self] in engine.snippets.map { SnippetsPanel.Item($0) } }
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPick = { [unowned self] id in
            guard let snippet = engine.snippets.first(where: { $0.id == id }) else { return }
            insert(.snippet(snippet))
        }
        panel.onEdit = { [unowned self] in open(AppLink.snippets($0)) }
        panel.onCreate = { [unowned self] in
            guard hasFullAccess else { return .fullAccess }
            feedback(.other)
            handle(.createSnippet)
            return engine.fill == nil ? .empty : nil
        }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        return panel
    }()
    private lazy var quicklinksPanel: SnippetsPanel = {
        let panel = SnippetsPanel(.quicklinks)
        panel.items = { [unowned self] in quicklinks.map { SnippetsPanel.Item($0) } }
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onPick = { [unowned self] id in
            guard let link = quicklinks.first(where: { $0.id == id }) else { return }
            insert(.quicklink(link, opening: false))
        }
        panel.onOpen = { [unowned self] id in
            guard let link = quicklinks.first(where: { $0.id == id }) else { return }
            feedback(.other)
            handle(.quicklink(link, opening: true))
        }
        panel.onEdit = { [unowned self] in open(AppLink.quicklinks($0)) }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        return panel
    }()
    private lazy var formPanel: FormPanel = {
        let panel = FormPanel()
        panel.fill = { [unowned self] in engine.fill }
        panel.focuses = { [unowned self] in hasFullAccess }
        panel.onField = { [unowned self] in
            feedback(.other)
            handle(.field($0))
        }
        panel.onNext = { [unowned self] in
            feedback(.other)
            guard let fill = engine.fill else { return }
            handle(fill.isLast ? .submit : .field(fill.at + 1))
        }
        return panel
    }()
    private lazy var textStylesPanel = rewritePanel(.textStyles, placeholder: "Search styles")
    private lazy var changeCasePanel = rewritePanel(.changeCase, placeholder: "Search cases")
    /// The panels this keyboard has, in the tools' order. GIFs need a KLIPY key built in.
    private lazy var panels: [Panel: PanelContent] = [
        .emoji: emojiPanel, .gif: gifPanel, .clipboard: clipboardPanel, .transcripts: transcriptsPanel,
        .snippets: snippetsPanel, .quicklinks: quicklinksPanel, .form: formPanel,
        .textStyles: textStylesPanel, .changeCase: changeCasePanel,
    ].compactMapValues { $0 }
    private lazy var host = ProxyDocument { [unowned self] in textDocumentProxy }
    /// The chats panel's message line while it's open, which the keys type into in place of the app's field.
    private var line: LineDocument?
    private var document: any TextDocument { line ?? host }
    /// What you'd begun in each chat you switched away from, by chat id.
    private var drafts: [String: String] = [:]
    private let chats = Chats()
    private let seen = ChatSeen()
    private lazy var chatShelf: ChatShelf = {
        let shelf = ChatShelf(chats: chats)
        shelf.fullAccess = { [unowned self] in hasFullAccess }
        shelf.onTurnOn = { [unowned self] in open(AppLink.settings) }
        shelf.onPick = { [unowned self] chat in
            feedback(.other)
            openChat(at: chat.id)
        }
        return shelf
    }()
    /// A panel fills the keys' place until you tap its field, which brings the keys up with the panel above them
    /// (docs/design.md, "Panels"): the emoji keyboard's search, a menu panel's.
    private var keysUp = false
    /// Where the open panel sits, so moving it lays the view out again even when no height changes, as when a panel opens
    /// from the menu in the keys' place.
    private var placed: (chat: Bool, inPlace: Bool)?
    private var panelOpen: Bool { line != nil || engine.panel != nil }
    /// A chat grows the keyboard, to all of the screen but this much left for the app (docs/extensions.md),
    /// and a chat keeps that height while you read, dictate and type. On the Duo it clears the clock, battery and
    /// Wi-Fi iOS stacks at the screen's top right, which reach 167 down (measured on the phone, Nov 8).
    private var roomForApp: Double { Duo.isDuo(short: min(screenSize.width, screenSize.height)) ? 172 : 140 }
    /// What iOS keeps under the keyboard, below the bar and the keys. The keyboard can't see it: its window is exactly
    /// its own size, at its own origin, and no keyboard notification reaches it (probed on the iPhone 17 simulator,
    /// Nov 9). Measured on screen instead: 44 on the Duo, a strip over the home indicator (on the phone, Nov 8), and 91
    /// on the other Face ID iPhones, iOS's globe-and-dictation bar (iPhone 17).
    private var beneath: Double {
        guard device == .phone else { return 0 }
        if Duo.isDuo(short: min(screenSize.width, screenSize.height)) { return 44 }
        return needsInputModeSwitchKey ? 0 : 91
    }
    /// A form needs the keys to fill it in, so it always sits above them.
    private var panelInKeysPlace: Bool { panelOpen && !keysUp && engine.panel != .form }
    /// The emoji keyboard in the keys' place, its search field over it in the bar's.
    private var emojiKeyboard: Bool { panelInKeysPlace && line == nil && engine.panel == .emoji }
    /// The photos attached to the open chat's next message, and the grid they're picked in.
    private let photos = ChatPhotos()
    /// The photo grid is up in the keys' place, the chat over it as with the keys up.
    private var picking = false
    private lazy var chatPanel: ChatPanel = {
        let panel = ChatPanel(chats: chats)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.onSend = { [unowned self] in
            guard let line else { return }
            feedback(.separator)
            engine.finishWord(in: line)
            send(line.take())
        }
        panel.onFocus = { [unowned self] in raiseKeys() }
        panel.onAttach = { [unowned self] in pickPhotos() }
        panel.onRemove = { [unowned self] in photos.remove(at: $0) }
        panel.onPastePhotos = { [unowned self] in photos.paste($0) }
        panel.onPick = { [unowned self] in suggestionBar.onChat($0) }
        panel.onMore = { [unowned self] in suggestionBar.onMore() }
        panel.onOpen = { [unowned self] in open($0) }
        panel.onReplace = { [unowned self] range, text in
            guard let line else { return }
            line.select(range)
            line.insert(text)
            engine.documentChanged(line)
            render()
        }
        panel.onBrowse = { [unowned self] in
            (keysUp, picking) = (false, false)
            render()
        }
        panel.onSelect = { [unowned self] range in
            guard let line else { return }
            line.select(range)
            engine.documentChanged(line)
            render()
        }
        return panel
    }()
    /// The chat open in a field, its line and the drafts begun in other chats, so the next keyboard in that field opens
    /// it again as you left it: dictating into a chat can open iikb and come back. It's on disk, since iOS ends the
    /// keyboard's process while it's away, as it does at its memory limit (177 MB on the Duo, Nov 9).
    private struct KeptChat: Codable {
        var field: String
        var chat: String?
        var text: String
        var keysUp: Bool
        var drafts: [String: String]
        var photos: [UnsentPhoto]?
        var picking: Bool?
        /// The process ID of the app iikb was opened from to ask iOS for the photos, until they're allowed: back in it,
        /// the chat opens again even in a field iOS names anew, as Safari's and Contacts' are on coming back, and it
        /// waits through the fields of other apps, iikb's own included. The process, not the app's name: a keyboard iOS
        /// has just started holds its host's process ID from the start, but the name can come only later or, in iikb's
        /// own app, never. 0 where the keyboard can't tell (the App Store build), so the chat waits for its own field.
        var askedFrom: Int32?

        func opens(in field: String, of process: Int32) -> Bool {
            field == self.field || (process > 0 && process == askedFrom)
        }
    }
    private static let keptChat = StoredFile<KeptChat>(
        URL.applicationSupportDirectory.appending(path: "chat-kept.json"))
    private static let log = Logger(subsystem: "com.shahidy.iikb", category: "chats")
    private var engine = TypingEngine()
    /// The languages the corrector's words are, and the list each came from, which `useLanguages` keeps to those picked.
    private var typing: String?
    private var typingLog = TypingLog()
    private let memoryStore = MemoryStore()
    private lazy var toolbarHeightConstraint = toolbarView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keysMinimumConstraint = keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()
    private var clicks = KeyClicks()
    private let clipboard = ClipboardStore(backup: ClipboardStore.own)
    private let sources = Sources()
    private var hostApp: String?
    private let fieldLines = FieldLines()
    /// The field's measured layout, where there is one, for the trackpad's moves up and down.
    private var measuredField: MeasuredField?
    /// The open chat's `KeptChat.askedFrom`.
    private var askedFrom: Int32?
    /// The field the keyboard is typing in (`documentIdentifier`), so dictations end with the field they were typed in,
    /// and the next keyboard in the same field goes on following them.
    private var field: String?
    /// The rest of what drawing needs of the app's field, read with `field` only as UIKit calls in (appearing, text and
    /// selection changes). Drawing never reads `textDocumentProxy` itself: sources' and chats' answers draw when they
    /// come, often after the app went to the background and iOS tore the proxy down, and reading it then crashes
    /// (EXC_BAD_ACCESS in `_UITextDocumentInterface`, builds 966 to 1059, 10 and 11 November).
    private var hostField = HostField()
    private struct HostField {
        var isPrivate = false
        var appearance: UIKeyboardAppearance?
        var selected = ""
    }

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    /// iOS keeps each keyboard's input view after its controller goes (the `_UIInputViewContent` it hangs on the view
    /// points back at it), so everything in it comes out here. Left in, every keyboard shown kept its whole tree,
    /// 2.7 MB each in the iOS 27.1 simulator, in a process iOS ends at 177 MB on the Duo (Nov 9).
    isolated deinit {
        chats.stop()
        viewIfLoaded?.subviews.forEach { $0.removeFromSuperview() }
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(hostLeft), name: .NSExtensionHostDidEnterBackground, object: nil)
        center.addObserver(self, selector: #selector(hostCameBack), name: .NSExtensionHostDidBecomeActive, object: nil)
        [toolbarView, keyboardView, menuView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        toolbarView.addSubview(suggestionBar)
        view.addSubview(panelView)
        keysMinimumConstraint.priority = .required - 1
        toolbarHeightConstraint.priority = .required - 2
        keyboardHeightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarHeightConstraint,
            keyboardView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeightConstraint,
            keysMinimumConstraint,
            menuView.topAnchor.constraint(equalTo: keyboardView.topAnchor),
            menuView.leadingAnchor.constraint(equalTo: keyboardView.leadingAnchor),
            menuView.trailingAnchor.constraint(equalTo: keyboardView.trailingAnchor),
            menuView.bottomAnchor.constraint(equalTo: keyboardView.bottomAnchor),
        ])
        menuView.isHidden = true
        menuView.onOpen = { [unowned self] in
            menuOpen = false
            open($0)
        }
        menuView.onSettings = { [unowned self] in
            feedback(.other)
            menuOpen = false
            handle(.settings)
        }
        menuView.onTheme = { [unowned self] in pick(\.theme, $0) }
        menuView.onStop = { [unowned self] in pick(\.stopAnimation, $0) }
        menuView.onAppearance = { [unowned self] in
            feedback(.other)
            menuOpen = false
            open(AppLink.appearance)
        }
        suggestionBar.onMore = { [unowned self] in toggleMenu() }
        suggestionBar.onUpdate = { [unowned self] in
            feedback(.other)
            if let page = InstallLink.page { open(page) }
        }
        suggestionBar.onMic = { [unowned self] in
            feedback(.other)
            toggleVoice()
        }
        suggestionBar.onMicDown = { [unowned self] in armVoice() }
        suggestionBar.onMicCancel = { [unowned self] in localDictation.disarm() }
        suggestionBar.onTool = { [unowned self] in open($0, backToMenu: hasMore) }
        suggestionBar.onSplit = { [unowned self] in
            feedback(.other)
            handle(.split($0))
        }
        suggestionBar.onEdit = { [unowned self] in edit($0) }
        suggestionBar.onStyle = { [unowned self] in pickStyle($0.map { DictationStyle.allCases[$0] }) }
        suggestionBar.onChat = { [unowned self] index in
            guard chats.list.indices.contains(index) else { return }
            feedback(.other)
            switchChat(to: chats.list[index])
        }
        panelView.onClose = { [unowned self] in back() }
        panelView.onField = { [unowned self] in raiseKeys() }
        panelView.onClear = { [unowned self] in
            guard let line else { return handle(.panel(engine.panel)) }
            line.clear()
            engine.documentChanged(line)
            render()
        }
        suggestionBar.onNotice = { [unowned self] in
            if notice != nil { notice = nil } else { sources.dismissHint() }
            render()
        }
        sources.onHint = { [unowned self] in render() }
        chats.changed = { [weak self] in self?.render() }
        photos.changed = { [weak self] in
            guard let self else { return }
            keepChat()
            render()
        }
        suggestionBar.onCancel = { [unowned self] in
            feedback(.other)
            if localDictation.isRecording { localDictation.cancel() } else { Dictation.send(.cancel) }
        }
        engine.defersSuggestions = true
        keyboardView.onEvent = { [unowned self] in handle($0) }
        keyboardView.heldEmoji = { [unowned self] in
            EmojiSearch.english.held(
                engine.settings.emojiGrid, custom: engine.settings.customEmoji, history: engine.emojiHistory)
        }
        suggestionBar.onSelect = { [unowned self] in
            feedback(.input)
            engine.accept($0, in: document)
            render()
        }
        suggestionBar.onEmoji = { [unowned self] in
            feedback(.input)
            engine.accept(emoji: $0, in: document)
            render()
        }
        useLanguages()
        Task { [weak self] in
            let catalog = await Task.detached(priority: .userInitiated) {
                _ = EmojiSearch.english
                return EmojiCatalog.english
            }.value
            self?.engine.emojiCatalog = catalog
            self?.engine.suggestionsChanged()
            self?.render()
        }
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] grid in
            engine.use(grid)
            suggestionBar.keys = grid.barRow.map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
            keyed = grid.rows.joined().contains { $0.key.action == .dictate }
            placeMic()
        }
        keyMic.addAction(UIAction { [unowned self] _ in suggestionBar.onMic() }, for: .touchUpInside)
        keyMic.addAction(UIAction { [unowned self] _ in suggestionBar.onMicDown() }, for: .touchDown)
        keyMic.addAction(
            UIAction { [unowned self] _ in suggestionBar.onMicCancel() }, for: [.touchUpOutside, .touchCancel])
        keyboardView.micKey = keyMic
        localDictation.onLevel = { [weak self] level, recorded in
            guard let self else { return }
            self.recorded = recorded
            suggestionBar.hear(level, recorded: recorded)
            keyMic.hear(level)
        }
        localDictation.onWritten = { [weak self] text, plain, id in
            guard let self else { return }
            engine.handle(.dictated(text, plain: plain, id: hostField.isPrivate ? nil : id.uuidString), in: document)
            render()
        }
        localDictation.onStartFailure = { [weak self] in self?.openAppToDictate() }
        localDictation.onNotice = { [weak self] message in
            guard let self else { return }
            notice = message
            render()
        }
        localDictation.onChange = { [weak self] in self?.render() }
        keyboardView.advance = { [unowned self] step in HostText.width(of: engine.character(crossedBy: step)) }
        keyboardView.lineHeight = { [unowned self] in
            line == nil ? fieldLines.lineHeight ?? measuredField?.lineHeight : nil
        }
        keyboardView.onTrackpad = { [unowned self] held in
            trackpadHeld = held
            if !held { return renderSuggestions() }
            if line == nil {
                fieldLines.check(app: hostApp, process: KeyboardHost.process(of: self), before: engine.text.before)
            }
        }
        fieldLines.apply = { [unowned self] offset in
            if engine.handle(.cursor(offset: offset), in: document) { render() }
        }
        keyboardView.globeTarget = { [unowned self] control in
            control.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.render() }
        if hasFullAccess { sources.reload() }
        if hasFullAccess { chats.reload() }
        syncWithDocument()
    }

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        render()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let room = toolbarView.bounds.height
        let bar = line == nil ? 0 : toolbar.height
        suggestionBar.frame = CGRect(x: 0, y: max(room - toolbar.height, 0), width: width, height: toolbar.height)
        panelView.frame =
            emojiKeyboard
            ? view.bounds
            : panelInKeysPlace
                ? keyboardView.frame
                : line != nil
                    ? CGRect(x: 0, y: 0, width: width, height: max(room - toolbar.height, 0))
                    : CGRect(
                        x: 0, y: max(room - bar - toolbar.panelHeight, 0), width: width, height: toolbar.panelHeight)
        if picking {
            let keys = keyboardView.frame
            photos.shown?.frame = CGRect(
                x: keys.minX, y: keys.minY, width: keys.width, height: view.bounds.maxY - keys.minY)
        }
        TouchTrace.shared.layout(view)
        fitLines()
    }

    private func fitLines() {
        measuredField = MeasuredField.measured(
            in: hostApp, on: Duo.Screen(width: screenSize.width, height: screenSize.height))
        engine.lineLayout = measuredField?.layout
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appeared = true
        hostAway = false
        KeyboardHost.appeared()
        updateHost()
        keyboard = .random(in: 1 ... .max)
        memoryStore.refresh { [weak self] memory in
            self?.engine.corrector?.changeMemory { $0 = memory }
            self?.engine.suggestionsChanged()
            self?.render()
        }
        engine.emojiHistory = MemoryStore.loadEmoji()
        engine.emojiHistory.app = hostApp
        loadSettings()
        clicks.refresh()
        if hasFullAccess { clipboard.catchUp() }
        syncWithDocument()
        if observers.isEmpty {
            observers = [SettingsStore.observe { [weak self] in self?.settingsChanged() }]
            if hasFullAccess {
                observers += [
                    Dictation.observe(.appeared) { [weak self] keyboard in
                        guard let self, keyboard != self.keyboard else { return }
                        self.observers.forEach(Dictation.stopObserving)
                        self.observers = []
                    },
                    Dictation.observe(.changed) { [weak self] in self?.dictationChanged() },
                    Dictation.observe(.photos) { [weak self] in self?.photosAnswered() },
                    Dictation.observeLevel { [weak self] level, recorded in
                        self?.recorded = recorded
                        self?.suggestionBar.hear(level, recorded: recorded)
                        self?.keyMic.hear(level)
                    },
                ]
                Dictation.send(.appeared, from: keyboard)
                dictationChanged()
            }
        }
        if hasFullAccess { sources.reload() }
        if hasFullAccess { chats.reload() }
        if hasFullAccess { readInstallLink() }
        syncWithDocument()
    }

    private func readInstallLink() {
        guard InstallLink.page != nil else { return }
        Task { [weak self] in
            let offered = await InstallLink.newer() != nil
            guard let self, offered != updateOffered else { return }
            updateOffered = offered
            render()
        }
    }

    override open func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        localDictation.memoryWarning()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateHost()
        syncWithDocument()
        fieldLines.check(app: hostApp, process: KeyboardHost.process(of: self), before: engine.text.before)
        if hapticsEnabled { haptics.start() }
        if hasFullAccess, !Dictation.micIsOn { localDictation.prepare() }
        stopSystemGesturesDelayingTouches()
        TouchTrace.shared.watch(view.window)
        Task { [weak self] in
            guard let lexicon = await self?.requestSupplementaryLexicon() else { return }
            self?.engine.corrector?.learn(lexicon)
            self?.engine.suggestionsChanged()
            self?.render()
        }
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appeared = false
        keepChat()
        chats.keep()
        leaveChat()
        engine.endSession()
        keepDictations()
        localDictation.keyboardWillHide()
        Dictation.keep(engine.takeDraft(), in: field)
        field = nil
        closePanels(in: document)
        menuOpen = false
        menuView.isHidden = true
        keysUp = false
        haptics.stop()
        TouchTrace.shared.flush()
        saveMemory()
        saveTyping()
        MemoryStore.save(engine.emojiHistory)
        if hasFullAccess { MemoryStore.queue.async { Backup.sync(Backup.keyboard + Backup.group) } }
        observers.forEach(Dictation.stopObserving)
        observers = []
    }

    private func loadSettings() {
        engine.settings = SettingsStore.load(sharing: hasFullAccess)
        engine.region = .current
        engine.snippets = SnippetStore.snippets(sharing: hasFullAccess)
        quicklinks = SnippetStore.quicklinks(sharing: hasFullAccess)
        engine.emojiHistory.skinTone = engine.settings.skinTone
        haptics.strength = Float(engine.settings.haptics.strength)
        keyboardView.characterPreview = engine.settings.characterPreview
        suggestionBar.stopAnimation = engine.settings.stopAnimation
        keyMic.stopAnimation = engine.settings.stopAnimation
        useLanguages()
        engine.suggestionsChanged()
    }

    /// Corrects in the languages picked in the app, each with its downloaded words, leaving out one whose words aren't
    /// here (or can't be reached without Full Access) and typing English when none are, keeping what you've taught it.
    /// For now it types the first of them alone, and the next-word network is English's. Slide to Type reads any
    /// language's words on its keys, with English's decoder only while English is typed alone (`Swipe.decodes`).
    private func useLanguages() {
        let here = engine.settings.languages.compactMap { language in
            LanguageFiles.lexicon(language.id).map { (language, $0) }
        }
        let typed = here.isEmpty ? [(Language.english, Lexicon.english)] : here
        let list = typed.map { "\($0.0.id) \(LanguageFiles.installed($0.0.id) ?? "")" }.joined(separator: ",")
        guard list != typing else { return }
        typing = list
        let english = typed[0].0 == .english
        let corrector = Corrector(source: typed[0].1, network: english ? .current : nil)
        if let old = engine.corrector {
            corrector.changeMemory { $0 = old.memory }
            corrector.replacements = old.replacements
            corrector.names = old.names
            corrector.app = old.app
            corrector.grid = old.grid
        }
        engine.corrector = corrector
        engine.swipeModel = typed.count == 1 && english ? .english : Swipe.english.withoutDecoder
    }

    /// A look picked in the menu, kept where the app reads it too, so its Appearance page shows it at once. A new theme
    /// fades in over the old.
    private func pick<Value: RawRepresentable<String>>(_ path: WritableKeyPath<KeyboardSettings, Value>, _ value: Value)
    {
        feedback(.other)
        SettingsStore.set(value, for: path, sharing: hasFullAccess)
        loadSettings()
        guard path == \.theme else { return render() }
        UIView.transition(with: view, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.render()
        }
    }

    /// A writing style picked in the bar for the app the keyboard is in, so its next dictation there is written so, or
    /// nil to have it follow the default again. Only with Full Access, since the app writes the dictation and reads the
    /// pick from the shared settings, and only where the app is known, so a pick is never the default's by mistake.
    private func pickStyle(_ style: DictationStyle?) {
        guard let hostApp else { return }
        feedback(.other)
        SettingsStore.set(style, in: hostApp, sharing: hasFullAccess)
        loadSettings()
        renderSuggestions()
    }

    /// The app kept new settings while the keyboard is up, as beside it on the open iPhone Duo.
    private func settingsChanged() {
        loadSettings()
        snippetsPanel.reset()
        quicklinksPanel.reset()
        if hasFullAccess { chats.reload() }
        if hapticsEnabled { haptics.start() }
        render()
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        hostAway = false
        updateHost()
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        hostAway = false
        updateHost()
        syncWithDocument()
    }

    private func updateHost() {
        let app = KeyboardHost.app(of: self)
        guard app != hostApp else { return }
        engine.changeApp(app)
        hostApp = app
        fitLines()
        engine.emojiHistory.app = app
        engine.suggestionsChanged()
    }

    private func syncWithDocument() {
        let proxy = textDocumentProxy
        hostField = HostField(
            isPrivate: proxy.isPrivate, appearance: proxy.keyboardAppearance, selected: proxy.selectedText ?? "")
        if line != nil {
            // WHY: iOS takes the field from a keyboard it's about to end (the iPad, back in an app), which isn't a move.
            guard let now = textDocumentProxy.field, now != field else { return render() }
            return closeChat()
        }
        engine.update(InputTraits(textDocumentProxy))
        if textDocumentProxy.field != field {
            field = textDocumentProxy.field
            engine.leaveField()
            localDictation.appeared(in: field)
            if let kept = Dictation.takeDraft() {
                if let field, kept.field == field {
                    engine.resume(kept.draft)
                } else {
                    Dictation.leave(kept.draft.outcomes(sent: false))
                }
            }
            keepDictations()
            if let field, let kept = Self.keptChat.read().value {
                let process = KeyboardHost.process(of: self)
                let opens = kept.opens(in: field, of: process)
                let waits = !opens && kept.askedFrom != nil
                if !waits { Self.keptChat.remove() }
                Self.log.notice(
                    "kept chat \(opens ? "opens" : waits ? "waits" : "goes", privacy: .public) in process \(process) of \(self.hostApp ?? "an unnamed app", privacy: .public), asked from \(kept.askedFrom.map { "\($0)" } ?? "none", privacy: .public)"
                )
                if hasFullAccess, opens {
                    // Kept until the photos are allowed, since the keyboard can come back to the app before iikb has
                    // even opened, as on the iPad, and the return after iOS answers still has to find the chat.
                    askedFrom = Dictation.photosAllowed ? nil : kept.askedFrom
                    drafts = kept.drafts
                    photos.restore(kept.photos ?? [])
                    openChat(kept.text, at: kept.chat, keysUp: kept.keysUp)
                    if kept.picking == true { showPhotos() }
                    return
                }
            }
        }
        let known = engine.text.before.count
        let report = engine.documentChanged(document)
        if report == .changed { tellSources(.app) }
        if report == .changed, engine.text.isEmpty {
            saveMemory()
            saveTyping()
            keepDictations()
        }
        TouchTrace.shared.record(report, host: textDocumentProxy.documentContextBeforeInput?.count ?? 0, known: known)
        render()
    }

    /// When the keyboard goes away and when a message is sent, so what was learned outlives the keyboard being ended.
    private func saveMemory() {
        if let memory = engine.corrector?.memory { memoryStore.save(memory, sharing: hasFullAccess) }
    }

    private func keepDictations() {
        Dictation.leave(engine.takeDictations())
    }

    private func saveTyping() {
        noteTyping()
        TypingStats.save(typingLog.take(), sharing: hasFullAccess)
    }

    /// Notes what typing did, in the hour and app it happened in: the engine's tally changes only as you type.
    private func noteTyping() {
        let now = Date.now
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        typingLog.note(
            engine.tally, at: ProcessInfo.processInfo.systemUptime, day: day, hour: parts.hour ?? 0, app: hostApp ?? "")
    }

    /// The screen the keys are laid out for, by the room iOS gives the keyboard, never the device alone: the iPad's
    /// screen, or, in the iPad's floating keyboard (a window about 320 wide), an iPhone that wide held upright, which is
    /// what Apple's floating keyboard is.
    private var screenSize: CGSize {
        let screen = view.window?.windowScene?.screen.bounds.size ?? view.bounds.size
        guard isFloating else { return screen }
        return CGSize(width: view.bounds.width, height: max(screen.width, screen.height))
    }

    private var isFloating: Bool {
        traitCollection.userInterfaceIdiom == .pad && view.bounds.width > 0 && view.bounds.width < 500
    }

    private var device: DeviceClass {
        DeviceClass(
            isPad: traitCollection.userInterfaceIdiom == .pad && !isFloating,
            shortSide: min(screenSize.width, screenSize.height))
    }

    /// The iPhone Duo draws no globe under a third-party keyboard, yet its iOS 27.1 simulator says none is needed, so
    /// on its screens (the only iPhones over 440pt on the short side) iikb always offers the next keyboard.
    private var showsGlobe: Bool {
        needsInputModeSwitchKey || (device == .phone && Duo.isDuo(short: min(screenSize.width, screenSize.height)))
    }

    private var mic: MicButton.Phase {
        if localDictation.isRecording { return localDictation.hears ? .listening : .starting }
        if dictation.listening { return .listening }
        if !localDictation.writing.isEmpty || !dictation.writing.isEmpty { return .writing }
        return micIsOn ? .on : .off
    }

    /// What a source sees: the field's text as the keyboard knows it, with Full Access, outside password and code fields.
    private func tellSources(_ author: FieldUpdate.Author) {
        guard hasFullAccess, line == nil, !hostField.isPrivate, let field else { return }
        sources.observe(
            FieldUpdate(
                field: field, before: engine.text.before, after: engine.text.after ?? "", by: author,
                traits: engine.traits,
                at: Date().timeIntervalSince1970, app: hostApp
            ))
    }

    private var hint: String? {
        guard hasFullAccess, let field else { return nil }
        return sources.hint(for: field, app: hostApp)
    }

    private func render() {
        guard isShown else { return }
        tellSources(.keyboard)
        noteTyping()
        let device = device
        let screen = Size(width: screenSize.width, height: screenSize.height)
        let keys = KeyboardGeometry(
            engine.layout(on: device, screen: screen, showsGlobe: showsGlobe), screen: screen,
            window: view.bounds.width, style: .current)
        let (context, layout, height) = (keys.context, keys.layout, keys.height)
        var metrics = keys.metrics
        let emoji = line == nil && engine.panel == .emoji
        let wanted =
            emoji
            ? metrics.toolbar.emoji : metrics.toolbar.showing(engine.panel, compact: engine.settings.compactPanels)
        let inPlace = panelInKeysPlace
        let overKeys = PanelView.height(over: MessageField.withPhotos, toolbar: wanted)
        let tall = max(height + wanted.height + overKeys, Double(screenSize.height) - roomForApp - beneath)
        let ask =
            line != nil
            ? (keysUp ? tall - height : wanted.height)
            : inPlace ? (emoji ? wanted.emojiStrip : wanted.height) : panelOpen ? wanted.panelHeight : wanted.height
        let keysHeight = line != nil && !keysUp ? tall - ask : height
        let room = view.bounds.height
        metrics.toolbar = wanted
        if ask == toolbarHeightConstraint.constant, keysHeight == keyboardHeightConstraint.constant, room > 0 {
            if engine.panel != nil, !inPlace { metrics.toolbar = wanted.fitting(room - height) }
            if keysHeight == height {
                metrics = metrics.filling(room - ask, rows: layout.rows.count, shortRows: layout.shortRows)
            }
        }
        if toolbarHeightConstraint.constant != ask { toolbarHeightConstraint.constant = ask }
        keyboardView.slidesToType = engine.settings.slideToType && engine.panel == nil && engine.swipeModel != nil
        keyboardView.menu = (context.menuKeys(in: layout), context.menu, context.menuPick)
        keyboardView.update(
            layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device),
            theme: theme)
        renderToolbar(metrics, context: context)
        renderMenu(context, metrics: metrics)
        renderSuggestions()

        if keyboardHeightConstraint.constant != keysHeight {
            keyboardHeightConstraint.constant = keysHeight
            keysMinimumConstraint.constant = height
        }
    }

    /// The bar, or the open panel in its place, across the keys block.
    private func renderToolbar(_ metrics: KeyboardMetrics, context: LayoutContext) {
        let width = view.bounds.width
        let block = (
            minX: CGFloat(metrics.margin.leading + metrics.sideInset),
            maxX: width - CGFloat(metrics.margin.trailing + metrics.sideInset)
        )
        if metrics.toolbar != toolbar {
            toolbar = metrics.toolbar
            view.setNeedsLayout()
        }
        // 375 is the narrowest iPhone; only the iPad's floating keyboard is narrower.
        let narrow = width < 375
        let tools = narrow ? [] : barTools(context)
        let panel = line != nil ? chatPanel : engine.panel.flatMap { panels[$0] }
        let inPlace = panelInKeysPlace
        panelView.focuses = hasFullAccess
        panelView.open(panel)
        panelView.isHidden = panel == nil
        panelView.inKeysPlace = inPlace
        panelView.fieldFirst = picking && !photos.attached.isEmpty
        if placed.map({ $0 != (line != nil, inPlace) }) ?? true {
            placed = (line != nil, inPlace)
            view.setNeedsLayout()
        }
        let emoji = line == nil && engine.panel == .emoji
        panelView.fieldOnTop = emoji
        emojiPanel.browsing = inPlace
        panelView.showsBack = line == nil
        panelView.bottomInset = line == nil ? PanelView.inset : CGFloat(metrics.bottomInset)
        suggestionBar.isHidden = engine.panel != nil && (!inPlace || emoji)
        panelView.block = block
        suggestionBar.toolbar = toolbar
        suggestionBar.maximumSlotWidth = metrics.toolbar.slot
        suggestionBar.update(tools: tools, open: engine.panel, theme: theme)
        suggestionBar.update(split: context.allowsSplit ? context.isSplit : nil)
        let fresh = line != nil ? seen.update(chats) : []
        chatPanel.fresh = fresh
        chatPanel.tabsRow = (suggestionBar.chatRow.minX - block.minX, suggestionBar.chatRow.maxX - block.minX)
        chatPanel.moreFrame = suggestionBar.chatMore.offsetBy(dx: -block.minX, dy: 0)
        suggestionBar.update(
            chats: line != nil && !keysUp ? chats.list.map(\.name) : nil,
            open: chats.list.firstIndex { $0 == chats.open }, fresh: fresh, theme: theme)
        hasMore = context.showsMoreButton
        let leading = hasMore || line != nil
        suggestionBar.update(more: (line == nil || !keysUp) && leading, on: menuShown || inPlace)
        suggestionBar.update(offered: updateOffered && !narrow)
        suggestionBar.update(edits: menuShown && panel == nil ? edits : nil, theme: theme)
        placeMic()
        suggestionBar.update(
            mic: mic, recorded: recorded,
            saved: dictation.writing + localDictation.writing, waitingFor: dictation.waiting ?? localDictation.waiting,
            notice: notice ?? hint, theme: theme)
        keyMic.show(mic, theme: theme)
        var shown = metrics
        if inPlace {
            shown.toolbar.results = PanelView.results(
                inKeysPlace: keyboardView.bounds.height, field: metrics.toolbar.field)
        }
        if let line {
            chatPanel.photos = photos.attached.map(\.url)
            chatPanel.show(line, typing: keysUp, picking: picking)
            panelView.show(query: line.text, caret: line.caret, theme: theme, metrics: shown)
        } else if panel != nil {
            panelView.show(query: engine.query, theme: theme, metrics: shown)
        }
    }

    /// The one mic: the Record Key while it's on screen, the bar's otherwise, and none without the dictation button,
    /// where a dictation started in the app still shows in the bar.
    private func placeMic() {
        let keysShown = !panelInKeysPlace && !menuShown
        suggestionBar.micInBar = engine.settings.dictationButton && !(keyed && keysShown)
        keyMic.isHidden = !keyed
    }

    /// The bar's tools: on iPad the emoji's, where the emoji key is on, then your actions where the bar shows them
    /// (`KeyboardSettings.showsActions`), outside a chat, whose tabs take that room.
    private func barTools(_ context: LayoutContext) -> [Panel] {
        let emoji: [Panel] = engine.settings.emojiKey && context.device != .phone ? [.emoji] : []
        let actions =
            engine.settings.showsActions && line == nil ? engine.settings.actions.filter { !emoji.contains($0) } : []
        return (emoji + actions).filter { panels[$0] != nil }
    }

    /// Whether the open panel's Back returns to the menu: not for one opened from a key, nor from the bar without a
    /// More button, whose menu would then have no way out.
    private var backToMenu = true
    /// The bar has its More button.
    private var hasMore = true

    /// The menu is in the keys' place: opened with More, while no panel is.
    private var menuShown: Bool { menuOpen && !panelOpen }

    /// The menu in the keys' place while it's open: the clipboard's, Transcripts' and the GIFs' shelves, then what the
    /// More button offers.
    private func renderMenu(_ context: LayoutContext, metrics: KeyboardMetrics) {
        let open = menuShown
        keyboardView.isHidden = open || panelInKeysPlace || picking
        photos.shown?.isHidden = !picking
        if open != !menuView.isHidden {
            menuView.isHidden = !open
            if open {
                let chats: [(Panel, PanelResults)] = hasChats ? [(.chats, chatShelf)] : []
                let kept: [Panel] = [.snippets] + (quicklinks.isEmpty ? [] : [.quicklinks])
                menuView.open(
                    ([Panel.clipboard, .transcripts, .gif] + kept).compactMap { panel in
                        panels[panel].map { (panel, $0) }
                    } + chats + [(.textStyles, textStylesPanel), (.changeCase, changeCasePanel)])
            }
        }
        guard open else { return }
        let width = view.bounds.width
        let block = (
            minX: CGFloat(metrics.margin.leading + metrics.sideInset),
            maxX: width - CGFloat(metrics.margin.trailing + metrics.sideInset)
        )
        menuView.show(settings: context.menu.isEmpty, theme: theme, metrics: metrics, block: block)
        let dark = hostField.appearance == .dark || traitCollection.userInterfaceStyle == .dark
        menuView.show(look: engine.settings, dark: dark, theme: theme)
    }

    /// Chats' shelf, with Full Access and an extension added, where the keyboard is an iPhone's width or more.
    private var hasChats: Bool {
        hasFullAccess && !chats.services.isEmpty && view.bounds.width >= 375
    }

    /// More opens the menu, and closes it, a chat, or a panel out in the keys' place, giving the keys back.
    private func toggleMenu() {
        feedback(.other)
        notice = nil
        if panelInKeysPlace || line != nil {
            menuOpen = false
            return closePanel()
        }
        menuOpen.toggle()
        if menuOpen, hasFullAccess { clipboard.catchUp() }
        if menuOpen, hasChats { chats.start(opening: false) }
        if !menuOpen, line == nil { chats.stop() }
        render()
    }

    /// Back steps out one level: the keys down, then the panel to the menu it was opened from. The emoji keyboard has
    /// none, as Apple's has none: its emoji key and return lower the keys, and ABC closes it.
    private func back() {
        if engine.panel == .form { return handle(.panel(nil)) }
        if keysUp { return lowerKeys() }
        let fromMenu = line != nil || backToMenu
        closePanel()
        if fromMenu {
            menuOpen = true
            if hasChats { chats.start(opening: false) }
            render()
        }
    }

    private func closePanel() {
        keysUp = false
        if line != nil { closeChat() } else { handle(.panel(nil)) }
    }

    /// The keys go back down, giving their place to the panel: the emoji keyboard's pages show again, its search emptied.
    private func lowerKeys() {
        (keysUp, picking) = (false, false)
        if engine.panel == .emoji, line == nil { return handle(.panel(.emoji)) }
        render()
    }

    /// A tap on the field of a panel in the keys' place: the keys come up to type into it.
    private func raiseKeys() {
        guard !keysUp || picking else { return }
        feedback(.other)
        (keysUp, picking) = (true, false)
        render()
    }

    /// iOS answered iikb's ask for access to the photos: the grid shows what it now may.
    private func photosAnswered() {
        if picking { photos.shown?.show(theme: theme) }
    }

    /// Opens iikb to ask iOS for access to the photos, which the keyboard shares, and back to the app you're in, where
    /// the chat opens again as you left it; only from an app iikb can bring you back to.
    private func allowPhotos() {
        updateHost()
        guard KeyboardHost.returns(to: hostApp, apps: engine.corrector?.memory.apps.map { Array($0.keys) } ?? []) else {
            notice = "Opening iikb would close this. Turn on photos from Chats in another app."
            return render()
        }
        askedFrom = KeyboardHost.process(of: self)
        keepChat()
        open(AppLink.Photos(back: hostApp).url)
    }

    /// The paperclip: your photos come up in the keys' place, or go back down to the chat.
    private func pickPhotos() {
        feedback(.other)
        if picking {
            (keysUp, picking) = (false, false)
            return render()
        }
        showPhotos()
    }

    /// Your photos in the keys' place, read again so a photo just taken, or access just given, shows.
    private func showPhotos() {
        if photos.shown == nil {
            let grid = photos.grid
            grid.onAllow = { [unowned self] in allowPhotos() }
            view.addSubview(grid)
        }
        photos.grid.show(theme: theme)
        (keysUp, picking) = (true, true)
        keepChat()
        render()
        view.setNeedsLayout()
    }

    /// Something picked in a panel or the menu's shelves is typed, and the menu gives the keys back.
    private func paste(_ text: String) {
        feedback(.input)
        menuOpen = false
        handle(.paste(text))
    }

    /// A panel's notice, like a GIF's "Copied": in its search row while the panel is open, in the bar once the menu,
    /// which has no search row, gives the keys back.
    private func noticed(_ panelNotice: String?) {
        if menuShown, let panelNotice {
            menuOpen = false
            notice = panelNotice
        }
        render()
    }

    private func open(_ panel: Panel, backToMenu: Bool = true) {
        feedback(.other)
        show(panel, backToMenu: backToMenu)
    }

    /// Text Styles or Change Case: a pick rewrites the text they act on, and the menu gives the keys back.
    private func rewritePanel(_ panel: Panel, placeholder: String) -> RewritePanel {
        let content = RewritePanel(panel, placeholder: placeholder)
        content.target = { [unowned self] in engine.rewriting }
        content.preview = { [unowned self] in engine.preview($0) }
        content.onPick = { [unowned self] in
            feedback(.input)
            menuOpen = false
            handle(.rewrite($0))
        }
        return content
    }

    /// Opens a panel without a tap of its own to feel, for a key that already played one as it went down. Its Back
    /// returns to the menu, or with `backToMenu` off, as from a key, to the letters.
    private func show(_ panel: Panel, backToMenu: Bool) {
        keysUp = false
        self.backToMenu = backToMenu
        if panel == .chats { return openChat() }
        handle(.panel(panel))
    }

    /// What the menu's edits can do now. Without Full Access a keyboard can't reach the clipboard, so every edit is offered and
    /// a tap says why it can't.
    private var edits: SuggestionBar.Edits {
        guard hasFullAccess else { return .init(cut: true, copy: true, paste: true) }
        let selected = !(hostField.selected.isEmpty && engine.text.selected.isEmpty)
        return .init(cut: selected, copy: selected, paste: UIPasteboard.general.hasStrings)
    }

    private var selection: String {
        let selected = textDocumentProxy.selectedText ?? ""
        return selected.isEmpty ? engine.text.selected : selected
    }

    /// One of the menu's edits, after which it gives the keys back. What you copy or cut joins the clipboard's history.
    private func edit(_ edit: SuggestionBar.Edit) {
        menuOpen = false
        feedback(.other)
        guard hasFullAccess else {
            notice = "Copy and paste need Allow Full Access in Settings › Apps › iikb › Keyboards"
            return render()
        }
        if edit == .paste {
            guard let text = UIPasteboard.general.string else {
                notice = "To paste, set Settings › Apps › iikb › Paste from Other Apps to Allow"
                return render()
            }
            return handle(.paste(text))
        }
        let text = selection
        if !text.isEmpty {
            UIPasteboard.general.string = text
            clipboard.catchUp()
            if edit == .cut { engine.perform(.delete, in: document) }
        }
        render()
    }

    private var theme: KeyboardTheme {
        KeyboardTheme.current(
            for: traitCollection, appearance: hostField.appearance, settings: engine.settings)
    }

    private var ranking = false
    /// From viewWillAppear to viewWillDisappear, and not while the host app is in the background, so a ranking job or
    /// answer that finishes then draws nothing. It saves work, not crashes: those notifications don't always come
    /// (`hostField`).
    private var isShown: Bool { appeared && !hostAway }
    private var appeared = false
    private var hostAway = false

    @objc private func hostLeft() {
        hostAway = true
        localDictation.keyboardWillHide()
    }

    @objc private func hostCameBack() {
        hostAway = false
        guard appeared else { return }
        localDictation.appeared(in: field)
        if hasFullAccess, !Dictation.micIsOn { localDictation.prepare() }
    }

    /// While the space bar trackpad is held the bar keeps what it showed, as Apple's does, and ranks once it's let go.
    private var trackpadHeld = false

    private func renderSuggestions() {
        guard isShown, !trackpadHeld else { return }
        let style = engine.settings.dictationStyle(in: hostApp)
        let own = hostApp.map { engine.settings.appDictationStyles[$0] != nil } ?? false
        suggestionBar.update(
            styles: hasFullAccess && hostApp != nil ? DictationStyle.allCases.map(\.title) : nil,
            picked: DictationStyle.allCases.firstIndex(of: style) ?? 0,
            reset: own ? "Use Default (\(engine.settings.dictationStyle.title))" : nil, theme: theme)
        guard engine.suggestionsAreStale else {
            return suggestionBar.update(
                engine.suggestions, emoji: engine.emojiSuggestions, enabled: engine.showsSuggestions, theme: theme)
        }
        guard !ranking, let job = engine.suggestionJob() else { return }
        ranking = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var job = job
            job.run()
            await self?.finish(job)
        }
    }

    private func finish(_ job: SuggestionJob) {
        ranking = false
        engine.finish(job)
        renderSuggestions()
    }

    private func handle(_ event: KeyboardEvent) {
        switch event {
        case .down(let key, _):
            feedback(Self.haptic(for: key))
            if key.action == .delete { startDeleteRepeat() }
            if notice != nil {
                notice = nil
                render()
            }
        case .up(let key) where key.action == .delete:
            deleteRepeat = nil
        case .deleteSlide:
            guard engine.handle(event, in: document) else { return }
            deleteRepeat = nil
            feedback(.deletionRepeat)
            return render()
        case .trigger(let key) where key.action == .dismiss:
            return dismissKeyboard()
        case .trigger(let key) where key.action == .nextKeyboard:
            return advanceToNextInputMode()
        case .trigger(let key) where key.action == .dictate:
            return toggleVoice()
        case .trigger(let key)
        where key.action == .return && keysUp && line == nil && engine.panel != nil && engine.panel != .form:
            return lowerKeys()
        case .trigger(let key) where key.action == .emoji && line == nil:
            if keysUp, engine.panel == .emoji { return lowerKeys() }
            keysUp = false
        case .type:
            TouchTrace.shared.mark("typed")
        case .oneHanded(let hand), .pick(let hand):
            SettingsStore.set(hand, sharing: hasFullAccess)
        case .split(let split):
            SettingsStore.set(split, for: \.split, sharing: hasFullAccess)
        case .settings:
            open(AppLink.keyboard)
        case .panel:
            menuOpen = false
        case .nextKeyboard:
            advanceToNextInputMode()
        case .cursorLines(let count) where line == nil && fieldLines.lineHeight != nil:
            return fieldLines.move(count, process: KeyboardHost.process(of: self), before: engine.text.before)
        default:
            break
        }
        if engine.handle(event, in: document) {
            if line != nil, engine.fill != nil { engine.handle(.panel(nil), in: document) }
            render()
        }
        switch engine.takeFinished() {
        case .keep(let snippet):
            SnippetStore.keep(snippet)
            settingsChanged()
        case .open(let link):
            if let url = URL(string: link) { open(url) }
        case nil:
            break
        }
    }

    /// A snippet or quicklink picked in its panel or shelf is typed, once any arguments are filled in, and the menu
    /// gives the keys back.
    private func insert(_ event: KeyboardEvent) {
        feedback(.input)
        menuOpen = false
        handle(event)
    }

    /// Closes a form, then the panel it came from.
    private func closePanels(in document: some TextDocument) {
        if engine.fill != nil { engine.handle(.panel(nil), in: document) }
        engine.handle(.panel(nil), in: document)
    }

    /// The chats panel opens with its line in place of the app's field, which the keys type into as into a message box,
    /// return starting a new line and the box's ↑ sending.
    private func openChat(_ text: String = "", at chat: String? = nil, keysUp: Bool = false) {
        guard line == nil else { return }
        menuOpen = false
        self.keysUp = keysUp
        closePanels(in: host)
        engine.leaveField()
        let line = LineDocument(text)
        self.line = line
        engine.update(InputTraits())
        engine.documentChanged(line)
        chats.reload()
        chats.start(at: chat)
        keepChat()
        render()
    }

    /// Notes the open chat where the next keyboard finds it, as it opens, as it switches and as the keyboard goes away,
    /// so even a keyboard iOS ends while it's up comes back to it.
    private func keepChat() {
        guard let line, let field else { return }
        Self.keptChat.save(
            KeptChat(
                field: field, chat: chats.open?.id, text: line.text, keysUp: keysUp && !picking, drafts: drafts,
                photos: photos.attached, picking: picking, askedFrom: askedFrom))
    }

    /// Another chat from its pill, the line you'd begun kept with the chat you left and the one you'd begun in this chat
    /// put back.
    private func switchChat(to chat: Chats.Chat) {
        guard let line, chat != chats.open else { return }
        if let open = chats.open { drafts[open.id] = line.text.isEmpty ? nil : line.text }
        line.clear()
        line.insert(drafts.removeValue(forKey: chat.id) ?? "")
        chats.pick(chat)
        engine.documentChanged(line)
        keepChat()
        render()
    }

    /// Back to the app's field, as the keyboard found it.
    private func closeChat() {
        guard line != nil else { return }
        photos.clear()
        leaveChat()
        // After the photos, since clearing them keeps the chat again (`photos.changed`).
        Self.keptChat.remove()
        syncWithDocument()
    }

    private func leaveChat() {
        guard line != nil else { return }
        photos.dropGrid()
        picking = false
        chats.stop()
        engine.leaveField()
        line = nil
        keysUp = false
        askedFrom = nil
    }

    /// What the box's ↑ took from the line goes to the open chat with the photos attached, which keeps them until its
    /// extension has them, and the chat comes back down to read. With no chat open to keep it, the text comes back to
    /// the line.
    private func send(_ text: String) {
        engine.documentChanged(document)
        render()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !photos.attached.isEmpty else { return }
        if chats.send(text, photos: photos.attached) {
            if !photos.attached.isEmpty { (keysUp, picking) = (false, false) }
            return photos.clear()
        }
        guard let line, !text.isEmpty else { return }
        line.insert(text)
        engine.documentChanged(line)
        render()
    }

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one, even while the last is
    /// still being written: in place while the app keeps the microphone on, and in the keyboard itself while it's
    /// off (`LocalDictation`), in the Writing Style picked for this app. Only a tap the keyboard can't hear or write
    /// (the app not yet given the microphone or Parakeet, a capture that won't start) opens the app. A chat keeps its
    /// keys as they were, up or down, while what you say lands in its box.
    private func toggleVoice() {
        guard hasFullAccess else {
            notice = "Voice needs Allow Full Access in Settings › Apps › iikb › Keyboards"
            return render()
        }
        updateHost()
        menuOpen = false
        Dictation.host = hostApp
        if localDictation.isRecording { return localDictation.stop() }
        if dictation.listening { return Dictation.send(.finish, from: keyboard) }
        notice = nil
        micIsOn = Dictation.micIsOn
        if micIsOn {
            localDictation.disarm()
            return Dictation.send(.start)
        }
        localDictation.start(for: hostApp, style: engine.settings.dictation(in: hostApp))
        render()
    }

    /// A finger came down on the mic: the keyboard starts hearing for a dictation it would make itself, so the first
    /// word isn't lost while the touch becomes a tap.
    private func armVoice() {
        guard hasFullAccess, !localDictation.isRecording, !dictation.listening, !Dictation.micIsOn else { return }
        updateHost()
        localDictation.arm(for: hostApp, style: engine.settings.dictation(in: hostApp))
    }

    /// Opens the app to dictate, for a tap the keyboard couldn't hear or write itself: only from a host it can bring
    /// you back to, never from one that leaving would close; from one it can't, it says the mic must be turned on in
    /// iikb first.
    private func openAppToDictate() {
        guard KeyboardHost.returns(to: hostApp, apps: engine.corrector?.memory.apps.map { Array($0.keys) } ?? []) else {
            notice = "Turn on the mic in iikb first"
            return render()
        }
        render()
        open(Dictation.Request(host: hostApp).url)
    }

    /// Opens a link from the keyboard. Apps can't be opened from a keyboard through public API, so this goes through
    /// the responder chain to the host's UIApplication, as voice keyboards do.
    private func open(_ url: URL) {
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication { return application.open(url) }
            responder = next.next
        }
    }

    /// The app listened, or left notes: types what you said in this keyboard, once each, and says so when what you
    /// said in a keyboard that has since closed isn't typed here. A status without the app's microphone lock was left by
    /// an app that ended mid-dictation, so the mic starts a new one.
    private func dictationChanged() {
        var status = Dictation.status
        micIsOn = Dictation.micIsOn
        if !micIsOn { (status.listening, status.writing, status.waiting) = (false, [], nil) }
        dictation = status
        recorded = Dictation.level.recorded
        let notes = Dictation.notes
        for (file, note) in notes where Dictation.take(file) {
            switch note {
            case .heard(let text, let plain, let keyboard, let id) where keyboard == nil || keyboard == self.keyboard:
                engine.handle(
                    .dictated(text, plain: plain, id: hostField.isPrivate ? nil : id?.uuidString), in: document)
            case .heard:
                notice = "Saved to Transcripts"
            case .notice(let notice):
                self.notice = notice
            }
        }
        render()
    }

    private func startDeleteRepeat() {
        deleteRepeat = DeleteRepeat { [unowned self] words in
            if words { engine.deleteWord(in: document) } else { engine.perform(.delete, in: document) }
            feedback(words ? .deletionRapid : .deletionRepeat)
            render()
        }
    }

    private func stopSystemGesturesDelayingTouches() {
        view.window?.gestureRecognizers?.forEach {
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
    }

    private func feedback(_ haptic: KeyHaptics.Kind) {
        if engine.settings.sound { clicks.play(haptic) }
        if hapticsEnabled { haptics.play(haptic) }
    }

    private static func haptic(for key: Key) -> KeyHaptics.Kind {
        switch key.action {
        case .character: .input
        case .space, .tab: .separator
        case .delete: .deletion
        default: .other
        }
    }
}
