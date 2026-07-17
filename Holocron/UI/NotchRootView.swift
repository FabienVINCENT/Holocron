import SwiftUI

/// Root view hosted in the notch panel. The panel window is resized by
/// `NotchPanelController`; this view just fills it and renders either the
/// compact pill or the expanded board.
struct NotchRootView: View {
    let state: AppState
    var onHoverChange: (Bool) -> Void
    var onTogglePin: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: state.panelExpanded ? Theme.cornerRadius : 12)
                .fill(Theme.background)
                .overlay(
                    NotchShape(bottomRadius: state.panelExpanded ? Theme.cornerRadius : 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

            if state.panelExpanded {
                ExpandedPanelView(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                CompactPillView(state: state)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.panelExpanded)
        .onHover(perform: onHoverChange)
        .onTapGesture {
            if !state.panelExpanded { onTogglePin() }
        }
        .preferredColorScheme(.dark)
    }
}

/// The notch-extension silhouette: square top (hugs the screen edge, blends
/// with the hardware notch), rounded bottom corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
