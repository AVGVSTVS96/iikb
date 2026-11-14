import Foundation

/// The install link a build from `scripts/phone` names in its Info.plist (`IIKBInstallLink`), where a newer build is
/// a tap away. TestFlight's and the simulator's builds leave it empty (`IIKB_INSTALL_LINK` in
/// project.yml), so they never offer one.
public enum InstallLink {
    /// The link's page, with Install on it.
    public static let page = (Bundle.main.object(forInfoDictionaryKey: "IIKBInstallLink") as? String).flatMap(
        URL.init(string:))

    /// The build on the link, read from its manifest, when it's newer than this one; nil when it isn't, or when the
    /// link can't be reached, as off the tailnet.
    public static func newer() async -> Int? {
        guard let page,
            let installed = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init)
        else { return nil }
        let request = URLRequest(
            url: page.appending(path: "manifest.plist"), cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
            let manifest = try? PropertyListDecoder().decode(Manifest.self, from: data),
            let offered = manifest.items.first?.metadata["bundle-version"].flatMap(Int.init), offered > installed
        else { return nil }
        return offered
    }

    private struct Manifest: Decodable {
        struct Item: Decodable { var metadata: [String: String] }
        var items: [Item]
    }
}
