import SwiftUI

/// Takes exactly the size it is offered and pins its single child to the top edge.
///
/// A hosting view centres content that is taller than the view, which makes the
/// settings content jump while the window animates to a new height. This layout keeps
/// the content anchored at the top and lets it overflow the bottom edge instead. When no
/// size is proposed (intrinsic size queries) it reports the child's ideal size, so the
/// window can still be sized to fit.
struct TopAnchoredLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(
            width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal.width,
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? ideal.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(subview.sizeThatFits(.unspecified))
        )
    }
}
