import Foundation
import UIKit
import Vision

/// Reads the total and the shop name from a receipt photo, on device.
enum ReceiptReader {

    nonisolated struct Result: Equatable {
        var amount: Decimal?
        var merchant: String?
    }

    private nonisolated struct Line {
        let text: String
        let box: CGRect
    }

    static let totalWords: [String] = [
        "total", "amount due", "to pay", "grand total", "sum", "сума", "всього", "разом", "до сплати", "до оплати", "сплачено",
        "итого", "к оплате", "сумма", "suma", "razem", "do zapłaty", "gesamt", "summe", "totale", "importe", "montant"
    ]

    static func read(_ image: UIImage) async -> Result {
        guard let cgImage = image.cgImage else { return Result() }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines: [Line] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let found = observations.compactMap { observation -> Line? in
                        guard let text = observation.topCandidates(1).first?.string else { return nil }
                        return Line(text: text, box: observation.boundingBox)
                    }
                    continuation.resume(returning: found)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
        return interpret(lines)
    }

    private static func interpret(_ lines: [Line]) -> Result {
        guard !lines.isEmpty else { return Result() }
        // Vision boxes have their origin at the bottom-left: higher y = nearer the top.
        let ordered = lines.sorted { $0.box.midY > $1.box.midY }

        var amount: Decimal?
        for line in ordered.reversed() where totalWords.contains(where: { line.text.lowercased().contains($0) }) {
            if let value = amounts(in: line.text).max() {
                amount = value
                break
            }
            // The figure often sits in a separate box on the same row.
            let sameRow = lines.filter { abs($0.box.midY - line.box.midY) < max(line.box.height, 0.015) && $0.box.minX > line.box.minX }
            if let value = sameRow.flatMap({ amounts(in: $0.text) }).max() {
                amount = value
                break
            }
        }
        if amount == nil {
            amount = lines.flatMap { amounts(in: $0.text) }.filter { $0 < 1_000_000 }.max()
        }

        let merchant = ordered.prefix(4).map(\.text).first { text in
            let letters = text.filter { $0.isLetter }.count
            return letters >= 3 && !totalWords.contains(where: { text.lowercased().contains($0) })
        }
        return Result(amount: amount, merchant: merchant?.trimmingCharacters(in: .whitespaces))
    }

    static func amounts(in text: String) -> [Decimal] {
        let pattern = "\\d{1,3}(?:[ \\u00A0.,]\\d{3})*[.,]\\d{2}(?!\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return AmountReader.number(String(text[swiftRange]))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Downscales photos before they are stored (keeps iCloud records small).
enum PhotoShrinker {
    static func jpeg(from data: Data, maxSide: CGFloat = 1400, quality: CGFloat = 0.62) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image, maxSide: maxSide, quality: quality)
    }

    static func jpeg(from image: UIImage, maxSide: CGFloat = 1400, quality: CGFloat = 0.62) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
