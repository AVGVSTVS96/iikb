import Foundation
import KeyboardCore
import KeyboardUI
import UIKit

/// How an app's field lays out its text on one of the Duo's screens, as measured there (`Resources/fields.json`, each
/// row's evidence in docs/trackpad.md), so the space bar trackpad moves up and down the lines it wraps where the field's
/// accessibility doesn't answer (`FieldLines`), as it never does on the device. An app or screen with no row moves by
/// sentence.
struct MeasuredField: Decodable {
    /// How wide the field wraps its text, in points.
    var width: CGFloat
    var font: String
    var size: CGFloat
    /// Whether the field's text follows the reader's text size, as the body style does.
    var dynamicType: Bool

    var layout: HostLayout { HostLayout(width: width, font: uiFont) }
    var lineHeight: CGFloat { uiFont.lineHeight }

    private var uiFont: UIFont {
        let font = UIFont(name: font, size: size) ?? .systemFont(ofSize: size)
        return dynamicType ? UIFontMetrics(forTextStyle: .body).scaledFont(for: font) : font
    }

    static func measured(in app: String?, on screen: Duo.Screen?) -> MeasuredField? {
        guard let app, let screen else { return nil }
        return rows[app]?["\(screen)"]
    }

    private static let rows: [String: [String: MeasuredField]] = {
        guard let url = Bundle.module.url(forResource: "fields", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return [:] }
        return (try? JSONDecoder().decode([String: [String: MeasuredField]].self, from: data)) ?? [:]
    }()
}
