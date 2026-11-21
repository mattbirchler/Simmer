import SwiftUI

/// A picture of a simulator's screen, set inside a dark bezel shaped like
/// the device it belongs to.
struct DeviceFrame: View {
    let screen: NSImage
    let kind: Simulator.Kind
    /// The space the framed device has to fit in.
    var box = CGSize(width: 56, height: 84)

    var body: some View {
        let bezel: CGFloat = kind == .tv ? 1.5 : 2.5
        let pixels = screen.size
        let scale = min((box.width - bezel * 2) / max(pixels.width, 1),
                        (box.height - bezel * 2) / max(pixels.height, 1))
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        let short = min(size.width, size.height)
        let radius = short * cornerFraction(for: pixels)
        let glass = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let body = RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)

        Image(nsImage: screen)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(glass)
            .overlay(alignment: .top) {
                if hasIsland(pixels) {
                    // Screenshots leave the Dynamic Island out, so draw it.
                    Capsule()
                        .fill(.black)
                        .frame(width: size.width * 0.32, height: size.width * 0.094)
                        .padding(.top, size.width * 0.03)
                }
            }
            .padding(bezel)
            .background(body.fill(Color(white: 0.08)))
            // A hairline so the bezel doesn't melt into a dark menu.
            .overlay(body.strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
    }

    /// Phones with a Home button are closer to 16:9 and have no island.
    private func isTallPhone(_ pixels: CGSize) -> Bool {
        kind == .phone && max(pixels.width, pixels.height) / max(min(pixels.width, pixels.height), 1) > 2
    }

    /// Only when upright: a sideways screenshot would put it on the wrong edge.
    private func hasIsland(_ pixels: CGSize) -> Bool {
        isTallPhone(pixels) && pixels.height > pixels.width
    }

    /// The screen's corner radius as a share of its shorter side.
    private func cornerFraction(for pixels: CGSize) -> CGFloat {
        switch kind {
        case .phone: isTallPhone(pixels) ? 0.17 : 0.03
        case .tablet: 0.055
        case .watch: 0.22
        case .tv: 0.02
        case .vision: 0.1
        case .other: 0.05
        }
    }
}
