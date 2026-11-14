import AVFoundation
import AVKit
import UIKit

/// iikb's picture in picture, a small tab you tuck off the screen's edge. While it's up iOS counts iikb as on screen,
/// so the keyboard's mic starts the microphone in place from any app, share sheets included, and the microphone is on
/// only while you talk. Typeless ships this (typeless.com/help/release-notes/ios/picture-in-picture); one developer's
/// iOS 27 logs show how (github.com/getdictus/dictus-ios/issues/430). Apple documents no recording started this way,
/// so a start iOS refuses takes the tab down (`Listener.start`) and the next dictation opens the app.
final class MicTab: NSObject {
    static let shared = MicTab()

    private(set) var isUp = false
    /// Asked to come up, and iOS hasn't said yet whether it did.
    private(set) var isOpening = false
    /// Comes up by itself as iikb leaves the screen.
    var armed = false {
        didSet { controller?.canStartPictureInPictureAutomaticallyFromInline = armed }
    }
    var onChange: () -> Void = {}

    private let source = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 12))
    private let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?

    /// iOS starts picture in picture only from a layer in a window, so the tab's sits behind the app's screens.
    func place(in window: UIWindow) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        window.insertSubview(source, at: 0)
        guard controller == nil else { return }
        layer.frame = source.bounds
        layer.videoGravity = .resizeAspect
        source.layer.addSublayer(layer)
        source.isUserInteractionEnabled = false
        source.accessibilityElementsHidden = true
        show(Self.frame())
        let controller = AVPictureInPictureController(
            contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = armed
        self.controller = controller
    }

    /// Only from a tap: iOS starts picture in picture from nothing else.
    @discardableResult func open() -> Bool {
        guard let controller, controller.isPictureInPicturePossible else { return false }
        controller.startPictureInPicture()
        isOpening = true
        onChange()
        return true
    }

    func close() {
        controller?.stopPictureInPicture()
    }

    private func show(_ frame: CMSampleBuffer?) {
        guard let frame else { return }
        layer.sampleBufferRenderer.flush()
        layer.sampleBufferRenderer.enqueue(frame)
    }

    private func changed(up: Bool) {
        guard up != isUp || isOpening else { return }
        HostApp.log.notice("the mic tab is \(up ? "up" : "down", privacy: .public)")
        (isUp, isOpening) = (up, false)
        onChange()
    }

    /// The tab: iikb's mic on black, wide and short so little of it shows.
    private static func frame() -> CMSampleBuffer? {
        let size = CGSize(width: 240, height: 80)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let glyph = UIImage(
                systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let name = NSAttributedString(
                string: "iikb",
                attributes: [.font: UIFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: UIColor.white])
            let glyphSize = glyph?.size ?? .zero
            let width = glyphSize.width + 10 + name.size().width
            var x = (size.width - width) / 2
            glyph?.draw(at: CGPoint(x: x, y: (size.height - glyphSize.height) / 2))
            x += glyphSize.width + 10
            name.draw(at: CGPoint(x: x, y: (size.height - name.size().height) / 2))
        }
        guard let image = image.cgImage else { return nil }
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
        guard let pixels else { return nil }
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixels), width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &description)
        guard let description else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: description,
            sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

extension MicTab: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        Task { @MainActor in
            MicTab.shared.show(MicTab.frame())
            MicTab.shared.changed(up: true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        Task { @MainActor in MicTab.shared.changed(up: false) }
    }

    nonisolated func pictureInPictureController(
        _: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error
    ) {
        HostApp.log.error("the mic tab couldn't come up: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in MicTab.shared.changed(up: false) }
    }
}

/// A still that's always playing, live, with nothing to skip to.
extension MicTab: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_: AVPictureInPictureController, setPlaying _: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_: AVPictureInPictureController) -> Bool { false }

    nonisolated func pictureInPictureController(
        _: AVPictureInPictureController, didTransitionToRenderSize _: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _: AVPictureInPictureController, skipByInterval _: CMTime, completion: @escaping @Sendable () -> Void
    ) {
        completion()
    }
}
