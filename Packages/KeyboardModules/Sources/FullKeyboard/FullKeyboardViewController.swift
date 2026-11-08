import KeyboardCore
import KeyboardEnglish
import KeyboardStore
import KeyboardUI
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
    private let suggestionBar = SuggestionBar()
    /// The record button in the bottom row, where Settings › Layout › Record Key puts it in the globe's place.
    private let keyMic = MicButton()
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
    /// The panels this keyboard has, in the tools' order. GIFs need a KLIPY key built in.
    private lazy var panels: [Panel: PanelContent] = [
        .emoji: emojiPanel, .gif: gifPanel, .clipboard: clipboardPanel, .transcripts: transcriptsPanel,
    ].compactMapValues { $0 }
    private lazy var host = ProxyDocument { [unowned self] in textDocumentProxy }
    /// The chats panel's message line while it's open, which the keys type into in place of the app's field.
    private var line: LineDocument?
    private var document: any TextDocument { line ?? host }
    /// What you'd begun in each chat you switched away from, by chat id.
    private var drafts: [String: String] = [:]
    private let chats = Chats()
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
    /// A panel opened from the menu fills the keys' place until you tap its field, which brings the keys up with the
    /// panel above them (docs/design.md, "Panels"). The emoji panel opens from its key, so always with the keys.
    private var keysUp = false
    /// Where the open panel sits, so moving it lays the view out again even when no height changes, as when a chat opens
    /// from the menu at the menu's height.
    private var placed: (chat: Bool, inPlace: Bool)?
    private var panelOpen: Bool { line != nil || engine.panel != nil }
    /// The menu and a chat grow the keyboard, to all of the screen but this much left for the app (docs/extensions.md),
    /// and a chat keeps that height while you read, dictate and type.
    private static let roomForApp = 140.0
    private var panelInKeysPlace: Bool { panelOpen && !keysUp && engine.panel != .emoji }
    private lazy var chatPanel: ChatPanel = {
        let panel = ChatPanel(chats: chats)
        panel.fullAccess = { [unowned self] in hasFullAccess }
        panel.onTurnOn = { [unowned self] in open(AppLink.settings) }
        panel.onSend = { [unowned self] in
            feedback(.separator)
            handle(.trigger(Key(.return)))
        }
        panel.onFocus = { [unowned self] in raiseKeys() }
        panel.onEdit = { [unowned self] in edit($0) }
        panel.onBrowse = { [unowned self] in
            keysUp = false
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
    /// The chat open in a field as the keyboard went away, and its line, so the next keyboard in that field opens it
    /// again: dictating into a chat can open iikb and come back.
    private static var keptChat: (field: String, chat: String?, text: String, keysUp: Bool)?
    private var engine = TypingEngine()
    private var typingLog = TypingLog()
    private let memoryStore = MemoryStore()
    private lazy var toolbarHeightConstraint = toolbarView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keyboardHeightConstraint = keyboardView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var keysMinimumConstraint = keyboardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
    private var deleteRepeat: DeleteRepeat?
    private let haptics = KeyHaptics()
    private let clipboard = ClipboardStore(backup: ClipboardStore.own)
    private let sources = Sources()
    private var hostApp: String?
    /// The field the keyboard is typing in (`documentIdentifier`), so dictations end with the field they were typed in,
    /// and the next keyboard in the same field goes on following them.
    private var field: String?

    override open func loadView() {
        inputView = KeyboardInputView(frame: .zero, inputViewStyle: .default)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
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
        suggestionBar.onMore = { [unowned self] in toggleMenu() }
        suggestionBar.onMic = { [unowned self] in toggleVoice() }
        suggestionBar.onTool = { [unowned self] in tool($0) }
        suggestionBar.onEdit = { [unowned self] in edit($0) }
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
        chats.changed = { [unowned self] in render() }
        suggestionBar.onCancel = { [unowned self] in
            feedback(.other)
            Dictation.send(.cancel)
        }
        engine.defersSuggestions = true
        keyboardView.onEvent = { [unowned self] in handle($0) }
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
        engine.corrector = Corrector(source: Lexicon.english, network: .current)
        engine.swipeModel = .english
        Task { [weak self] in
            let catalog = await Task.detached(priority: .userInitiated) { EmojiCatalog.english }.value
            self?.engine.emojiCatalog = catalog
            self?.engine.suggestionsChanged()
            self?.render()
        }
        keyboardView.resolve = { [unowned self] grid, point in engine.key(atX: point.x, y: point.y, in: grid) }
        keyboardView.onGrid = { [unowned self] grid in
            engine.use(grid)
            suggestionBar.keys = (grid.rows.first ?? []).map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
            let keyed = grid.rows.joined().contains { $0.key.action == .dictate }
            suggestionBar.micInBar = !keyed
            keyMic.isHidden = !keyed
        }
        keyMic.addAction(UIAction { [unowned self] _ in suggestionBar.onMic() }, for: .touchUpInside)
        keyboardView.micKey = keyMic
        keyboardView.advance = { [unowned self] step in HostText.width(of: engine.character(crossedBy: step)) }
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
            panelInKeysPlace
            ? keyboardView.frame
            : line != nil
                ? CGRect(x: 0, y: 0, width: width, height: max(room - toolbar.height, 0))
                : CGRect(x: 0, y: max(room - bar - toolbar.panelHeight, 0), width: width, height: toolbar.panelHeight)
        TouchTrace.shared.layout(view)
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isShown = true
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
        if hasFullAccess { clipboard.catchUp() }
        if hasFullAccess, let kept = Self.keptChat {
            Self.keptChat = nil
            syncWithDocument()
            if kept.field == field { openChat(kept.text, at: kept.chat, keysUp: kept.keysUp) }
        }
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
                    Dictation.observeLevel { [weak self] level, recorded in
                        self?.recorded = recorded
                        self?.suggestionBar.hear(level, recorded: recorded)
                    },
                ]
                Dictation.send(.appeared, from: keyboard)
                dictationChanged()
            }
        }
        if hasFullAccess { sources.reload() }
        if hasFullAccess { chats.reload() }
        syncWithDocument()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateHost()
        syncWithDocument()
        if hapticsEnabled { haptics.start() }
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
        isShown = false
        if let line, let field { Self.keptChat = (field, chats.open?.id, line.text, keysUp) }
        leaveChat()
        engine.endSession()
        keepDictations()
        Dictation.keep(engine.takeDraft(), in: field)
        field = nil
        engine.handle(.panel(nil), in: document)
        menuOpen = false
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
        engine.emojiHistory.skinTone = engine.settings.skinTone
        haptics.strength = Float(engine.settings.haptics.strength)
        keyboardView.characterPreview = engine.settings.characterPreview
        suggestionBar.stopAnimation = engine.settings.stopAnimation
        engine.suggestionsChanged()
    }

    /// The app kept new settings while the keyboard is up, as beside it on the open iPhone Duo.
    private func settingsChanged() {
        loadSettings()
        if hasFullAccess { chats.reload() }
        if hapticsEnabled { haptics.start() }
        render()
    }

    override open func selectionDidChange(_ textInput: UITextInput?) {
        updateHost()
        syncWithDocument()
    }

    override open func textDidChange(_ textInput: UITextInput?) {
        updateHost()
        syncWithDocument()
    }

    private func updateHost() {
        let app = KeyboardHost.app(of: self)
        guard app != hostApp else { return }
        engine.changeApp(app)
        hostApp = app
        engine.emojiHistory.app = app
        engine.suggestionsChanged()
    }

    private func syncWithDocument() {
        if line != nil {
            guard textDocumentProxy.field != field else { return render() }
            return closeChat()
        }
        engine.update(InputTraits(textDocumentProxy))
        if textDocumentProxy.field != field {
            field = textDocumentProxy.field
            engine.leaveField()
            if let kept = Dictation.takeDraft() {
                if let field, kept.field == field {
                    engine.resume(kept.draft)
                } else {
                    Dictation.leave(kept.draft.outcomes(sent: false))
                }
            }
            keepDictations()
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
        if dictation.listening { return .listening }
        if !dictation.writing.isEmpty { return .writing }
        return micIsOn ? .on : .off
    }

    /// What a source sees: the field's text as the keyboard knows it, with Full Access, outside password and code fields.
    private func tellSources(_ author: FieldUpdate.Author) {
        guard hasFullAccess, line == nil, !textDocumentProxy.isPrivate, let field = textDocumentProxy.field else {
            return
        }
        sources.observe(
            FieldUpdate(
                field: field, before: engine.text.before, after: engine.text.after ?? "", by: author,
                traits: engine.traits,
                at: Date().timeIntervalSince1970, app: hostApp
            ))
    }

    private var hint: String? {
        guard hasFullAccess, let field = textDocumentProxy.field else { return nil }
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
        let wanted = metrics.toolbar.showing(engine.panel, compact: engine.settings.compactPanels)
        let inPlace = panelInKeysPlace
        let tall = max(height + wanted.height, Double(screenSize.height) - Self.roomForApp)
        let ask =
            line != nil
            ? (keysUp ? tall - height : wanted.height) : inPlace || !panelOpen ? wanted.height : wanted.panelHeight
        let keysHeight = (line != nil && !keysUp) || (menuOpen && !panelOpen) ? tall - ask : height
        let room = view.bounds.height
        metrics.toolbar = wanted
        if ask == toolbarHeightConstraint.constant, keysHeight == keyboardHeightConstraint.constant, room > 0 {
            if engine.panel != nil, !inPlace { metrics.toolbar = wanted.fitting(room - height) }
            if keysHeight == height {
                metrics = metrics.filling(room - ask, rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
            }
        }
        if toolbarHeightConstraint.constant != ask { toolbarHeightConstraint.constant = ask }
        keyboardView.slidesToType = engine.settings.slideToType && engine.panel == nil
        keyboardView.menu = (context.menuKeys(in: layout), context.menu, context.menuPick)
        keyboardView.update(
            layout: layout, signature: context.signature, metrics: metrics, faces: engine.faces(on: device),
            theme: theme)
        renderToolbar(metrics, device: device)
        renderMenu(context, metrics: metrics)
        renderSuggestions()

        if keyboardHeightConstraint.constant != keysHeight {
            keyboardHeightConstraint.constant = keysHeight
            keysMinimumConstraint.constant = height
        }
    }

    /// The bar, or the open panel in its place, across the keys block.
    private func renderToolbar(_ metrics: KeyboardMetrics, device: DeviceClass) {
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
        let tools: [Panel] = engine.settings.emojiKey && device != .phone && !narrow ? [.emoji] : []
        let panel = line != nil ? chatPanel : engine.panel.flatMap { panels[$0] }
        let inPlace = panelInKeysPlace
        panelView.open(panel)
        panelView.isHidden = panel == nil
        panelView.inKeysPlace = inPlace
        if placed.map({ $0 != (line != nil, inPlace) }) ?? true {
            placed = (line != nil, inPlace)
            view.setNeedsLayout()
        }
        panelView.showsBack = line == nil
        panelView.backgroundColor = line == nil ? nil : theme.card.ui
        panelView.bottomInset = line == nil ? PanelView.inset : CGFloat(metrics.bottomInset)
        suggestionBar.isHidden = engine.panel != nil && !inPlace
        panelView.block = block
        suggestionBar.toolbar = toolbar
        suggestionBar.maximumSlotWidth = metrics.toolbar.slot
        suggestionBar.update(tools: tools, theme: theme)
        suggestionBar.update(
            chats: line != nil && !keysUp ? chats.list.map(\.name) : nil,
            open: chats.list.firstIndex { $0 == chats.open }, theme: theme)
        suggestionBar.update(more: true, on: menuOpen || inPlace)
        suggestionBar.update(edits: menuOpen && panel == nil ? edits : nil, theme: theme)
        suggestionBar.update(
            mic: mic, recorded: recorded, saved: dictation.writing, waitingFor: dictation.waiting,
            notice: notice ?? hint, theme: theme)
        keyMic.show(mic, theme: theme)
        var shown = metrics
        if inPlace {
            shown.toolbar.results = PanelView.results(
                inKeysPlace: keyboardView.bounds.height, field: metrics.toolbar.field)
        }
        if let line {
            chatPanel.show(line, typing: keysUp)
            panelView.show(query: line.text, caret: line.caret, theme: theme, metrics: shown)
        } else if panel != nil {
            panelView.show(query: engine.query, theme: theme, metrics: shown)
        }
    }

    /// The menu in the keys' place while it's open: the clipboard's, Transcripts' and the GIFs' shelves, then what the
    /// More button offers where Settings › Layout › Keyboard Menu puts layouts there.
    private func renderMenu(_ context: LayoutContext, metrics: KeyboardMetrics) {
        let open = menuOpen && !panelOpen
        keyboardView.isHidden = open || panelInKeysPlace
        if open != !menuView.isHidden {
            menuView.isHidden = !open
            if open {
                let chats: [(Panel, PanelResults)] = hasChats ? [(.chats, chatShelf)] : []
                menuView.open(
                    [Panel.clipboard, .transcripts, .gif].compactMap { panel in panels[panel].map { (panel, $0) } }
                        + chats)
            }
        }
        guard open else { return }
        let width = view.bounds.width
        let block = (
            minX: CGFloat(metrics.margin.leading + metrics.sideInset),
            maxX: width - CGFloat(metrics.margin.trailing + metrics.sideInset)
        )
        menuView.show(settings: context.menu.isEmpty, theme: theme, metrics: metrics, block: block)
    }

    /// Chats' shelf, with Full Access and an extension added, where the keyboard is an iPhone's width or more.
    private var hasChats: Bool {
        hasFullAccess && !chats.services.isEmpty && view.bounds.width >= 375
    }

    /// More opens the menu, and closes it or a panel out in the keys' place, giving the keys back.
    private func toggleMenu() {
        feedback(.other)
        notice = nil
        if panelInKeysPlace {
            menuOpen = false
            return closePanel()
        }
        menuOpen.toggle()
        if menuOpen, hasFullAccess { clipboard.catchUp() }
        if menuOpen, hasChats { chats.start(opening: false) }
        if !menuOpen, line == nil { chats.stop() }
        render()
    }

    /// Back steps out one level: the keys down, then the panel to the menu it was opened from. The emoji panel, opened
    /// from its key, closes.
    private func back() {
        if keysUp, engine.panel != .emoji {
            keysUp = false
            return render()
        }
        let fromMenu = engine.panel != .emoji
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

    /// A tap on the field of a panel in the keys' place: the keys come up to type into it.
    private func raiseKeys() {
        guard !keysUp else { return }
        feedback(.other)
        keysUp = true
        render()
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
        if menuOpen, let panelNotice {
            menuOpen = false
            notice = panelNotice
        }
        render()
    }

    private func open(_ panel: Panel) {
        feedback(.other)
        keysUp = false
        if panel == .chats { return openChat() }
        handle(.panel(panel))
    }

    private func tool(_ panel: Panel) {
        open(panel)
    }

    /// What the menu's edits can do now. Without Full Access a keyboard can't reach the clipboard, so every edit is offered and
    /// a tap says why it can't.
    private var edits: SuggestionBar.Edits {
        guard hasFullAccess else { return .init(cut: true, copy: true, paste: true) }
        let selected = !selection.isEmpty
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
            for: traitCollection, appearance: textDocumentProxy.keyboardAppearance, settings: engine.settings)
    }

    private var ranking = false
    /// From viewWillAppear to viewWillDisappear. Once the keyboard goes away the text document proxy is torn down while
    /// this controller lives on, and reading it then crashes, so a ranking job or load that finishes later draws nothing.
    private var isShown = false

    private func renderSuggestions() {
        guard isShown else { return }
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
        case .trigger(let key) where key.action == .dismiss:
            return dismissKeyboard()
        case .trigger(let key) where key.action == .nextKeyboard:
            return advanceToNextInputMode()
        case .trigger(let key) where key.action == .dictate:
            return toggleVoice()
        case .trigger(let key)
        where key.action == .return && keysUp && line == nil && engine.panel != nil && engine.panel != .emoji:
            keysUp = false
            return render()
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
        default:
            break
        }
        if engine.handle(event, in: document) { render() }
        if let text = line?.takeReturned() { send(text) }
    }

    /// The chats panel opens with its line in place of the app's field, which the keys type into as into a field whose
    /// return key sends.
    private func openChat(_ text: String = "", at chat: String? = nil, keysUp: Bool = false) {
        guard line == nil else { return }
        menuOpen = false
        self.keysUp = keysUp
        engine.handle(.panel(nil), in: host)
        engine.leaveField()
        let line = LineDocument(text)
        self.line = line
        engine.update(InputTraits(returnKind: .send, returnRequiresText: true))
        engine.documentChanged(line)
        chats.reload()
        chats.start(at: chat)
        render()
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
        render()
    }

    /// Back to the app's field, as the keyboard found it.
    private func closeChat() {
        guard line != nil else { return }
        leaveChat()
        syncWithDocument()
    }

    private func leaveChat() {
        guard line != nil else { return }
        chats.stop()
        engine.leaveField()
        line = nil
        keysUp = false
    }

    /// What return took from the line goes to the open chat; if it can't, it comes back to the line, unless you've
    /// begun another.
    private func send(_ text: String) {
        engine.documentChanged(document)
        render()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { [weak self] in
            guard let self, !(await chats.send(text)), let line, line.text.isEmpty else { return }
            line.insert(text)
            engine.documentChanged(line)
            render()
        }
    }

    /// Stops a dictation in progress, so what was heard is typed. Otherwise starts one, even while the last is still
    /// being written: in place while the app keeps the microphone on, or by opening the app, since a keyboard can't use
    /// the microphone and iOS starts a recording only in an app in front.
    private func toggleVoice() {
        guard hasFullAccess else {
            notice = "Voice needs Allow Full Access in Settings › Apps › iikb › Keyboards"
            return render()
        }
        updateHost()
        menuOpen = false
        Dictation.host = hostApp
        if dictation.listening { return Dictation.send(.finish, from: keyboard) }
        notice = nil
        micIsOn = Dictation.micIsOn
        if micIsOn { return Dictation.send(.start) }
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
        for (file, note) in Dictation.notes where Dictation.take(file) {
            switch note {
            case .heard(let text, let plain, let keyboard, let id) where keyboard == nil || keyboard == self.keyboard:
                engine.handle(
                    .dictated(text, plain: plain, id: textDocumentProxy.isPrivate ? nil : id?.uuidString), in: document)
            case .heard:
                notice = "Not typed here: it’s in iikb › Transcripts"
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
        if engine.settings.sound { UIDevice.current.playInputClick() }
        if hapticsEnabled { haptics.play(haptic) }
    }

    private static func haptic(for key: Key) -> KeyHaptics.Kind {
        switch key.action {
        case .character: .input
        case .space, .return, .tab: .separator
        case .delete: .deletion
        default: .other
        }
    }
}
