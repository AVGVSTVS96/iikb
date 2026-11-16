import KeyboardCore
import SwiftUI
import UIKit

/// What a piece of a snippet's text or a quicklink's link is, as `Template` reads it.
enum TemplatePiece: Equatable {
    case text, cursor
    case argument(String)
}

extension Template {
    /// `source` cut into its text and its placeholders, each with its range: a `{` up to the next `}` is a placeholder
    /// when `Template` reads it as one, and a `{` that isn't stays text, as `Template` keeps it.
    static func pieces(of source: String) -> [(range: Range<String.Index>, piece: TemplatePiece)] {
        var pieces: [(range: Range<String.Index>, piece: TemplatePiece)] = []
        var start = source.startIndex
        var search = start
        while let open = source[search...].firstIndex(of: "{"), let close = source[open...].firstIndex(of: "}") {
            let range = open..<source.index(after: close)
            let alone = Template(String(source[range]))
            let piece: TemplatePiece? =
                if let argument = alone.arguments.first {
                    .argument(argument.name)
                } else if alone.filled().cursor != nil {
                    .cursor
                } else {
                    nil
                }
            guard let piece else {
                search = source.index(after: open)
                continue
            }
            if start < open { pieces.append((start..<open, .text)) }
            pieces.append((range, piece))
            start = range.upperBound
            search = start
        }
        if start < source.endIndex { pieces.append((start..<source.endIndex, .text)) }
        return pieces
    }

    /// `{argument name="City" default="Paris"}`, leaving out what's empty and the quotes and braces that would end it.
    static func argument(name: String, defaultValue: String) -> String {
        let clean = { (value: String) in
            value.filter { !"{}\"“”„'‘’".contains($0) }.trimmingCharacters(in: .whitespaces)
        }
        let name = clean(name)
        let defaultValue = clean(defaultValue)
        return "{argument" + (name.isEmpty ? "" : " name=\"\(name)\"")
            + (defaultValue.isEmpty ? "" : " default=\"\(defaultValue)\"") + "}"
    }

    /// The text as a list shows it: each argument its name and the cursor an I-beam, in blue.
    static func line(_ source: String) -> Text {
        pieces(of: source).reduce(Text(verbatim: "")) { line, piece in
            switch piece.piece {
            case .text: Text("\(line)\(Text(verbatim: String(source[piece.range])))")
            case .cursor: Text("\(line)\(Text(Image(systemName: "character.cursor.ibeam")).foregroundStyle(.blue))")
            case .argument(let name): Text("\(line)\(Text(verbatim: name).foregroundStyle(.blue))")
            }
        }
    }
}

/// Puts a placeholder in a `TemplateField` at its caret, from a button outside it.
@MainActor final class TemplateInput {
    fileprivate weak var view: UITextView?
    /// Whether you've put the caret anywhere yet: until you do, a placeholder goes at the end.
    fileprivate var placed = false

    func insert(_ placeholder: String) {
        guard let view else { return }
        if !placed { view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0) }
        guard let range = view.selectedTextRange else { return }
        view.replace(range, withText: placeholder)
        view.delegate?.textViewDidChange?(view)
        placed = true
        view.becomeFirstResponder()
    }
}

/// A snippet's text or a quicklink's link as you write it, its placeholders in blue as `Template` reads them. A link is
/// one paragraph, typed with the URL keys, that wraps rather than scrolls.
struct TemplateField: UIViewRepresentable {
    @Binding var text: String
    let prompt: String
    var link = false
    let input: TemplateInput

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, link: link) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if link {
            view.keyboardType = .URL
            view.autocapitalizationType = .none
            view.autocorrectionType = .no
            view.smartQuotesType = .no
            view.smartDashesType = .no
            view.returnKeyType = .done
        }
        view.delegate = context.coordinator
        view.text = text
        view.accessibilityLabel = prompt
        context.coordinator.paint(view)
        input.view = view
        context.coordinator.input = input
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.text != text else { return }
        view.text = text
        context.coordinator.paint(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let lines: CGFloat = link ? 1 : 4
        let least = ((view.font ?? Coordinator.font).lineHeight * lines).rounded(.up)
        let fits = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(fits.rounded(.up), least))
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        static var font: UIFont { .preferredFont(forTextStyle: .body) }
        private let text: Binding<String>
        private let link: Bool
        weak var input: TemplateInput?

        init(text: Binding<String>, link: Bool) {
            self.text = text
            self.link = link
        }

        func textViewDidChange(_ view: UITextView) {
            if text.wrappedValue != view.text { text.wrappedValue = view.text }
            paint(view)
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            if view.isFirstResponder { input?.placed = true }
        }

        /// A link stays one paragraph: return puts the keys away, and a pasted link loses its line breaks.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard link, replacementText.contains(where: \.isNewline) else { return true }
            if replacementText == "\n" {
                view.resignFirstResponder()
            } else if let start = view.position(from: view.beginningOfDocument, offset: range.location),
                let end = view.position(from: start, offset: range.length),
                let replaced = view.textRange(from: start, to: end)
            {
                view.replace(replaced, withText: replacementText.filter { !$0.isNewline })
                textViewDidChange(view)
            }
            return false
        }

        /// Colors the placeholders, leaving the text and the caret as they are; never while a word is being composed.
        func paint(_ view: UITextView) {
            guard view.markedTextRange == nil else { return }
            let plain: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: UIColor.label]
            let source = view.text ?? ""
            let storage = view.textStorage
            storage.beginEditing()
            storage.setAttributes(plain, range: NSRange(location: 0, length: storage.length))
            for piece in Template.pieces(of: source) where piece.piece != .text {
                storage.addAttribute(
                    .foregroundColor, value: UIColor.systemBlue, range: NSRange(piece.range, in: source))
            }
            storage.endEditing()
            view.typingAttributes = plain
        }
    }
}

/// The row under a `TemplateField` that puts placeholders in: Cursor, for a snippet, where the caret ends, and Argument,
/// a value asked for each time, named and with a default.
struct PlaceholderButtons: View {
    let input: TemplateInput
    let source: String
    var cursor = true
    @State private var asking = false
    @State private var name = ""
    @State private var defaultValue = ""

    var body: some View {
        HStack(spacing: 22) {
            if cursor {
                Button("Cursor", systemImage: "character.cursor.ibeam") { input.insert("{cursor}") }
                    .disabled(Template(source).filled().cursor != nil)
            }
            Button("Argument", systemImage: "curlybraces") {
                name = ""
                defaultValue = ""
                asking = true
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.borderless)
        .tint(.blue)
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
        .alert("Add Argument", isPresented: $asking) {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
            TextField("Default (optional)", text: $defaultValue)
            Button("Cancel", role: .cancel) {}
            Button("Add") { input.insert(Template.argument(name: name, defaultValue: defaultValue)) }
        }
    }
}
