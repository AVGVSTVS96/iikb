// Run on the Mac by scripts/duoshots: `swift duoshot-check.swift <shot.png>` exits 0 when the shot is iikb's Home with
// iikb's keyboard up: Home's title "iikb" in the screen's top quarter, and in its bottom half the keyboard's bottom row,
// where the space bar's corner reads "iikb" level with the 123 key. Otherwise it prints what the shot shows instead.
import AppKit
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("couldn't read \(url.path)")
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])
let lines = (request.results ?? []).compactMap { line in
    line.topCandidates(1).first.map { (text: $0.string.trimmingCharacters(in: .whitespaces), top: 1 - line.boundingBox.maxY) }
}
let title = lines.contains { $0.text == "iikb" && $0.top < 0.25 }
let space = lines.contains { label in
    label.text == "iikb" && label.top > 0.5
        && lines.contains { $0.text.hasSuffix("123") && abs($0.top - label.top) < 0.02 }
}
if title && space { exit(0) }
let top = lines.filter { $0.top < 0.25 }.prefix(3).map(\.text).joined(separator: " · ")
print(
    [
        title ? nil : "iikb's Home isn't in front (its top reads \"\(top)\")",
        space ? nil : "iikb's keyboard isn't up",
    ].compactMap { $0 }.joined(separator: ", and "))
exit(1)
