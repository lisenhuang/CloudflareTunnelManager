import SwiftUI

/// A small, tappable QR code for a tunnel's public URL. Clicking it opens a
/// popover with a large version plus the URL and a copy button — so someone can
/// scan it with a phone to open the tunnel.
///
/// The QR is computed synchronously in `body` (cheap, thanks to a cached
/// `CIContext`). It deliberately avoids `.task`/`.onAppear`, which don't reliably
/// fire when the hosting view starts out empty.
struct QRCodeView: View {
    let url: String
    var size: CGFloat = 92

    @State private var showLarge = false

    var body: some View {
        if let qr = QRCode.image(from: url) {
            Button { showLarge = true } label: {
                tile(qr, side: size)
            }
            .buttonStyle(.plain)
            .help("Scan to open \(url) — click to enlarge")
            .popover(isPresented: $showLarge, arrowEdge: .trailing) {
                VStack(spacing: 14) {
                    tile(qr, side: 280)
                    Text(url)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                }
                .padding(24)
            }
        }
    }

    /// A QR rendered on a white rounded tile (QR codes need a light quiet zone).
    private func tile(_ image: NSImage, side: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.none)
            .frame(width: side, height: side)
            .padding(side * 0.07)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.08))
            .overlay(RoundedRectangle(cornerRadius: side * 0.08).stroke(.black.opacity(0.08)))
    }
}
