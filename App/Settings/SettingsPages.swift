import KeyboardStore
import KeyboardCore
import SwiftUI

/// What Sources and Extensions share: a service you run, with a name, an address and an optional token, added in
/// Settings or from its link.
protocol Service: Hashable, Identifiable {
    var name: String { get }
    var url: URL { get }
    var token: String? { get }
    init(name: String, url: URL, token: String?)
    static var noun: String { get }
    static var about: String { get }
    @MainActor static var saved: [Self] { get }
    @MainActor static func save(_ service: Self, replacing old: Self?)
    @MainActor static func delete(_ service: Self)
}

extension Source: Service, @retroactive Identifiable {
    public var id: String { name + url.absoluteString }
    static let noun = "Source"
    static let about = "A source is a service you run that iikb tells what you type. With Full Access on, each one gets the app’s bundle ID and the text of the field you’re typing in, never passwords or codes, and can answer with a hint above the keys. Tap a hint to hide it."
    static var saved: [Source] { SettingsModel.shared.sources }
    static func save(_ service: Source, replacing old: Source?) { SettingsModel.shared.save(service, replacing: old) }
    static func delete(_ service: Source) {
        if let index = saved.firstIndex(of: service) { SettingsModel.shared.delete([index]) }
    }
}

extension Extension: Service, @retroactive Identifiable {
    public var id: String { name + url.absoluteString }
    static let noun = "Extension"
    static let about = "An extension is a service you run whose chats open from the bar, to read them and write in them as you would in any field. With Full Access on, iikb asks it for its chats and sends it what you write there, nothing else you type."
    static var saved: [Extension] { SettingsModel.shared.extensions }
    static func save(_ service: Extension, replacing old: Extension?) { SettingsModel.shared.save(service, replacing: old) }
    static func delete(_ service: Extension) { SettingsModel.shared.delete(service) }
}

struct ServicesPage<Item: Service>: View {
    @State private var editing: Item?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !Item.saved.isEmpty {
                Box(header: "Your \(Item.noun)s") {
                    ForEach(Item.saved) { service in
                        Button { editing = service } label: {
                            HStack {
                                RowText(title: service.name, detail: service.url.host() ?? service.url.absoluteString)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.appSecondary)
                            }
                            .row()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Box(footer: Item.about) {
                ActionRow(title: "Add \(Item.noun)", symbol: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { ServiceForm<Item>(service: nil) }
        .sheet(item: $editing) { ServiceForm(service: $0) }
    }
}

/// A service's name, address and token, checked before it's saved.
private struct ServiceForm<Item: Service>: View {
    let service: Item?
    @State private var name: String
    @State private var address: String
    @State private var token: String
    @Environment(\.dismiss) private var dismiss

    init(service: Item?) {
        self.service = service
        _name = State(initialValue: service?.name ?? "")
        _address = State(initialValue: service?.url.absoluteString ?? "https://")
        _token = State(initialValue: service?.token ?? "")
    }

    private var url: URL? {
        URL(string: address.trimmingCharacters(in: .whitespaces)).flatMap { Source.allows($0) && $0.host() != nil ? $0 : nil }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? {
        if trimmedName.isEmpty { return nil }
        if Item.saved.contains(where: { $0.name == trimmedName && $0 != service }) { return "“\(trimmedName)” is already one of your \(Item.noun.lowercased())s." }
        if url == nil, address.count > "https://".count { return "The address needs to start with https://." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Column {
                Box(footer: problem ?? "iikb sends the token with each request, so the \(Item.noun.lowercased()) can tell it’s you.") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .row()
                    TextField("https://", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .row()
                    SecureField("Token (optional)", text: $token)
                        .textInputAutocapitalization(.never)
                        .row()
                }
                if let service {
                    Box {
                        ActionRow(title: "Delete \(Item.noun)", role: .destructive) {
                            Item.delete(service)
                            dismiss()
                        }
                    }
                }
            }
            .pushedPage(service == nil ? "Add \(Item.noun)" : "Edit \(Item.noun)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url else { return }
                        Item.save(Item(name: trimmedName, url: url, token: token.isEmpty ? nil : token), replacing: service)
                        dismiss()
                    }
                    .disabled(url == nil || trimmedName.isEmpty || problem != nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.appPage)
    }
}

/// The switches iOS keeps for iikb, each checked when iikb can tell.
struct SetupSteps: View {
    private let status = AppStatus.shared

    var body: some View {
        SetupStep(done: status.isAdded, title: "Add iikb", detail: status.isAdded ? "iikb is one of your keyboards." : "Turn on Keyboards › iikb.")
        SetupStep(done: status.fullAccess, title: "Allow Full Access", detail: "For voice typing, haptics, GIFs, the clipboard, sources and your taps.")
        SetupStep(done: status.pasteAllowed, title: "Paste from Other Apps", detail: "Set it to Allow, so the clipboard keeps what you copy.") { AppStatus.openPasteSetting() }
    }
}

private struct SetupStep: View {
    let done: Bool
    let title: String
    let detail: String
    var open: @MainActor () -> Void = AppStatus.openSettings

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.appSecondary)
                    .accessibilityHidden(true)
                RowText(title: title, detail: detail)
                Image(systemName: "arrow.up.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.appSecondary)
                    .accessibilityHidden(true)
            }
            .row()
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

struct SetupPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(footer: "iOS keeps these in Settings › Apps › iikb. iikb checks each one off once the keyboard has seen it on; if you turn one off later, iikb can’t tell.") {
                SetupSteps()
            }
            Box {
                ActionRow(title: "Open iikb in Settings", symbol: "arrow.up.forward") { AppStatus.openSettings() }
            }
        }
    }
}

struct PrivacyPage: View {
    @State private var confirmsReset = false
    @State private var confirmsDelete = false
    @State private var confirmsDeleteTyping = false
    @State private var confirmsClearClipboard = false
    @State private var backup: Backup.Outcome?
    @State private var clipboard = ClipboardStore()
    @State private var unpinned = 0
    private let transcripts = Transcripts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Box(header: "What Leaves This \(ThisDevice.name)") {
                Label(Backup.isBuiltIn ? "Learned words, app-specific language and emoji choices, typing counts, dictations and clipboard history stay here and on your backup server." : "Learned words, app-specific language and emoji choices, typing counts, dictations and clipboard history stay here.", systemImage: ThisDevice.symbol).labelStyle(.aligned).row()
                Label("iikb goes online to download its voice model, search GIFs, ask the App Store the names of apps you type in, and send the field’s text and app ID to sources you add.", systemImage: "network").labelStyle(.aligned).row()
            }
            if Backup.isBuiltIn {
                Box(header: "Backup", footer: "iikb sends what it keeps to your server each time it changes, and the server keeps every version, so a lost \(ThisDevice.name), a reinstall or a bug can’t take it.") {
                    switch backup {
                    case nil: RowText(title: "Checking your server…").row()
                    case .upToDate: RowText(title: "Up to date", detail: "Your dictations, Dictionary, clipboard and taps are there. The keyboard sends what it learns each time it closes.").row()
                    case .unreachable: RowText(title: "Can’t reach your server", detail: "iikb sends what changed the next time it can.").row()
                    }
                }
                .task { backup = await Backup.sendApp() }
            }
            Box(footer: "iikb forgets the words it learned across apps and within each app, and where your thumbs land on each key. Your Dictionary stays.") {
                ActionRow(title: "Reset Learned Words and Taps", role: .destructive) { confirmsReset = true }
            }
            Box(footer: "Deletes the counts Stats keeps of your typing on this \(ThisDevice.name): never what you typed, only how much, how fast and in which app.") {
                ActionRow(title: "Delete Typing Stats", role: .destructive) { confirmsDeleteTyping = true }
            }
            Box(footer: transcripts.all.isEmpty ? "You haven’t dictated anything yet." : "Deletes all \(transcripts.all.count.formatted()) transcripts and their sound from this \(ThisDevice.name).") {
                ActionRow(title: "Delete All Transcripts", role: .destructive) { confirmsDelete = true }
                    .disabled(transcripts.all.isEmpty)
            }
            Box(footer: unpinned == 0 ? "Your clipboard history has nothing to clear." : "Deletes \(unpinned == 1 ? "1 item" : "\(unpinned.formatted()) items") from your clipboard history. Pinned items stay.") {
                ActionRow(title: "Clear Clipboard History", role: .destructive) { confirmsClearClipboard = true }
                    .disabled(unpinned == 0)
            }
        }
        .onAppear {
            clipboard.onChange = { unpinned = clipboard.history.items.filter { !$0.pinned }.count }
            clipboard.reload()
        }
        .confirmationDialog("iikb will forget the words it learned and everything it learned about your taps.", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { MemoryStore.reset() }
        }
        .confirmationDialog("Delete your typing stats from this \(ThisDevice.name)?", isPresented: $confirmsDeleteTyping, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { TypingStats.delete() }
        }
        .confirmationDialog("Delete all \(transcripts.all.count) transcripts from this \(ThisDevice.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { transcripts.deleteAll() }
        }
        .confirmationDialog("Clear your clipboard history?", isPresented: $confirmsClearClipboard, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                clipboard.removeUnpinned()
            }
        }
    }
}

struct AboutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 16) {
                Mark(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iikb").font(.display(28)).tracking(-0.045 * 28)
                    Text(Self.version).foregroundStyle(Color.appSecondary)
                }
            }
            .padding(.horizontal, 4)
            Box(footer: "iikb types like Apple’s keyboard and learns where your thumbs land. It’s open source, under the MIT license.") {
                Link(destination: URL(string: "https://github.com/AVGVSTVS96/iikb")!) {
                    HStack {
                        Text("Source Code").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color.appSecondary)
                    }
                    .row()
                }
            }
            Box {
                Link(destination: URL(string: "https://github.com/AVGVSTVS96/iikb/blob/main/Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/SWIPE-LICENSE")!) {
                    HStack {
                        Text("Swipe typing powered by FUTO Swipe").foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).foregroundStyle(Color.appSecondary)
                    }
                    .row()
                }
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}

/// A label whose icon takes a fixed width, so the text of labels stacked in one card starts at the same place.
private struct AlignedLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.frame(width: 24)
            configuration.title
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension LabelStyle where Self == AlignedLabel {
    static var aligned: AlignedLabel { AlignedLabel() }
}
