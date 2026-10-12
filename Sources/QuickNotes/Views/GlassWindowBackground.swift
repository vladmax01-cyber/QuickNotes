import AppKit
import SwiftUI

struct GlassWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let transparency: Double
    let glassEnabled: Bool
    var material: NSVisualEffectView.Material = .underWindowBackground

    var body: some View {
        if !glassEnabled || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                StableWindowMaterial(material: material)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(adaptiveTintOpacity)
            }
        }
    }

    private var adaptiveTintOpacity: Double {
        let amount = sqrt(min(1, max(0, transparency)))
        let minimum = colorScheme == .dark ? 0.22 : 0.21
        let maximum = colorScheme == .dark ? 0.62 : 0.72
        return maximum - ((maximum - minimum) * amount)
    }
}

private struct StableWindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = material
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}
