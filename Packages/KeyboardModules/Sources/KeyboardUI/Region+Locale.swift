import Foundation
import KeyboardCore

extension Region {
    /// The region and currency iOS is set to.
    public static var current: Region {
        Region(code: Locale.current.region?.identifier, currency: Locale.current.currency?.identifier)
    }
}
