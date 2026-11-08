import Foundation
import ImageIO
import UIKit

/// Each copied link's site icon, shown beside it as ChatGPT shows a link's. It's fetched once per site from the site
/// itself, its `apple-touch-icon.png` or else its `favicon.ico`, so only the site's name leaves the device, never the
/// link; a site without either is asked again a week later. The icons sit in the App Group's caches, where the app and
/// the keyboard share them, drawn on white with rounded corners so a dark logo shows on a dark keyboard.
public final class LinkIcons {
    public static let shared = LinkIcons()

    private let folder = (AppGroup.library ?? .cachesDirectory).appending(path: "Caches/link-icons")
    private let memory = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    nonisolated private static let session = URLSession(configuration: .ephemeral)

    /// An icon already in memory, for a row drawn before `icon` answers.
    public func cached(_ site: String) -> UIImage? { memory.object(forKey: site as NSString) }

    public func icon(_ site: String) async -> UIImage? {
        if let image = cached(site) { return image }
        let task = loading[site] ?? Task { [folder] in await Self.load(site, folder: folder) }
        loading[site] = task
        let image = await task.value
        loading[site] = nil
        if let image { memory.setObject(image, forKey: site as NSString) }
        return image
    }

    nonisolated private static func load(_ site: String, folder: URL) async -> UIImage? {
        let file = folder.appending(path: "\(site).png"), none = folder.appending(path: "\(site).none")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: 3) { return image } // file: link icon cache
        let tried = (try? none.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let tried, tried.timeIntervalSinceNow > -7 * 24 * 3600 { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var answered = false
        for name in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(site)/\(name)"),
                  let (data, response) = try? await session.data(from: url),
                  let response = response as? HTTPURLResponse
            else { continue }
            answered = true
            guard response.statusCode == 200, let image = tile(data) else { continue }
            try? image.pngData()?.write(to: file, options: .atomic) // file: link icon cache
            try? FileManager.default.removeItem(at: none)
            return image
        }
        if answered { try? Data().write(to: none, options: .atomic) } // file: marker that a site has no icon, so it's asked weekly at most
        return nil
    }

    /// The icon on a white rounded square, 60 points a side, the largest anything shows it. A favicon holds several
    /// sizes, so the largest is drawn.
    nonisolated private static func tile(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let width = { (index: Int) in (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0 }
        guard let largest = (0..<CGImageSourceGetCount(source)).max(by: { width($0) < width($1) }),
              let icon = CGImageSourceCreateThumbnailAtIndex(source, largest, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 180] as CFDictionary),
              icon.width >= 16
        else { return nil }
        let side: CGFloat = 60
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let bounds = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(roundedRect: bounds, cornerRadius: side * 0.22).addClip()
            UIColor.white.setFill()
            context.fill(bounds)
            let inset = icon.width >= 120 ? 0 : side * 0.14
            UIImage(cgImage: icon).draw(in: bounds.insetBy(dx: inset, dy: inset))
        }
    }
}
