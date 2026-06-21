import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Generates a QR code image for a string (e.g. a tunnel's public URL) using the
/// system `CIQRCodeGenerator` — no third-party dependency.
///
/// The image is rendered at *native module resolution* (one pixel per QR module).
/// Display it with `.resizable().interpolation(.none)` so SwiftUI scales it up
/// into crisp squares at any size without blurring or breaking scannability.
enum QRCode {
    /// Reused across calls so generating in a view body stays cheap.
    private static let context = CIContext(options: nil)

    static func image(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"   // ~15% error correction — good for URLs
        guard let output = filter.outputImage, !output.extent.isEmpty else { return nil }
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
