import Foundation
import ImageIO
import UIKit

/// Each copied link's site icon, shown beside it as ChatGPT shows a link's. It's fetched once per site from the site
/// itself, its `apple-touch-icon.png`, else the largest icon its home page links, else its `favicon.ico`, so only the
/// site's name leaves the device, never the link; a site without any is asked again a week later. The icons sit in
/// the App Group's caches, where the app and the keyboard share them, on a white rounded tile with a hairline edge, so
/// a dark logo shows on a dark keyboard and the tile on a white one.
public final class LinkIcons {
    public static let shared = LinkIcons()

    private let folder = (AppGroup.library ?? .cachesDirectory).appending(path: "Caches/site-icons")
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
        let file = folder.appending(path: "\(site).png")
        let none = folder.appending(path: "\(site).none")
        // file: link icon cache
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: 3) { return image }
        let tried = (try? none.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let tried, tried.timeIntervalSinceNow > -7 * 24 * 3600 { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var answered = false
        func fetch(_ url: URL?) async -> UIImage? {
            guard let url, let (data, response) = try? await session.data(from: url),
                let response = response as? HTTPURLResponse
            else { return nil }
            answered = true
            return response.statusCode == 200 ? tile(data) : nil
        }
        var image = await fetch(URL(string: "https://\(site)/apple-touch-icon.png"))
        if image == nil, let page = URL(string: "https://\(site)/"), let (html, _) = try? await session.data(from: page)
        {
            answered = true
            for url in linkedIcons(String(decoding: html.prefix(500_000), as: UTF8.self), page: page).prefix(2)
            where image == nil {
                image = await fetch(url)
            }
        }
        if image == nil { image = await fetch(URL(string: "https://\(site)/favicon.ico")) }
        if let image {
            try? image.pngData()?.write(to: file, options: .atomic)  // file: link icon cache
            try? FileManager.default.removeItem(at: none)
            return image
        }
        // file: marker that a site has no icon, so it's asked weekly at most
        if answered { try? Data().write(to: none, options: .atomic) }
        return nil
    }

    /// The icons a home page's `<link rel="…icon…">` tags name, largest first, leaving out SVG, which ImageIO can't draw.
    nonisolated static func linkedIcons(_ html: String, page: URL) -> [URL] {
        html.matches(of: /<link\b[^>]*>/.ignoresCase()).compactMap { tag -> (size: Int, url: URL)? in
            let tag = tag.output
            let rel = tag.firstMatch(of: /rel\s*=\s*["']([^"']*)["']/.ignoresCase()).map { $0.1.lowercased() } ?? ""
            guard rel.contains("icon"), !rel.contains("mask"),
                let href = tag.firstMatch(of: /href\s*=\s*["']([^"']*)["']/.ignoresCase()).map({
                    String($0.1).replacingOccurrences(of: "&amp;", with: "&")
                }),
                !href.lowercased().hasSuffix(".svg"), let url = URL(string: href, relativeTo: page)?.absoluteURL
            else { return nil }
            let size =
                tag.firstMatch(of: /sizes\s*=\s*["'](\d+)/.ignoresCase()).flatMap { Int($0.1) }
                ?? (rel.contains("apple") ? 180 : 32)
            return (size, url)
        }
        .sorted { $0.size > $1.size }
        .map(\.url)
    }

    /// The icon on a white rounded square, 60 points a side, the largest anything shows it. A favicon holds several
    /// sizes, so the largest is drawn.
    nonisolated private static func tile(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let width = { (index: Int) in
            (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth]
                as? Int ?? 0
        }
        guard let largest = (0..<CGImageSourceGetCount(source)).max(by: { width($0) < width($1) }),
            let icon = CGImageSourceCreateThumbnailAtIndex(
                source, largest,
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 180]
                    as CFDictionary),
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
            let edge = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 1.25), cornerRadius: side * 0.22 - 1.25)
            edge.lineWidth = 2.5
            UIColor.black.withAlphaComponent(0.12).setStroke()
            edge.stroke()
        }
    }
}
