import SwiftUI

/// Root view hosted in the notch panel.
///
/// Animation recipe: both the pill and the expanded board stay mounted at
/// their FIXED layout sizes; only the container (and its clip shape)
/// springs between the two sizes, revealing the content — no re-layout
/// churn during the transition. The window itself is resized instantly by
/// `NotchPanelController`; hover detection lives there too (AppKit
/// tracking area — SwiftUI's onHover misfires in borderless panels).
struct NotchRootView: View {
    let state: AppState
    var onTogglePin: () -> Void

    var body: some View {
        let expanded = state.panelExpanded
        let compact = CGSize(width: state.compactSize.width, height: state.compactSize.height)
        let full = CGSize(width: NotchPanelController.expandedSize.width,
                          height: NotchPanelController.expandedSize.height)
        let target = expanded ? full : compact
        let radius: CGFloat = expanded ? Theme.cornerRadius : 12

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: radius)
                    .fill(Theme.background)

                ExpandedPanelView(state: state)
                    .frame(width: full.width, height: full.height, alignment: .top)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)

                CompactPillView(state: state)
                    .frame(width: compact.width, height: compact.height)
                    .opacity(expanded ? 0 : 1)
                    .allowsHitTesting(!expanded)
            }
            .frame(width: target.width, height: target.height, alignment: .top)
            .clipShape(NotchShape(bottomRadius: radius))
            .overlay(
                NotchShape(bottomRadius: radius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    .frame(width: target.width, height: target.height)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if !expanded { onTogglePin() }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: expanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
