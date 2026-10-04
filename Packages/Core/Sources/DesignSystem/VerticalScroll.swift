import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A scroll view that only moves up and down. A slightly wide child (a rounded width, a glow, a long word) makes a
/// plain `ScrollView` pan sideways on a light finger movement; here the horizontal axis is locked and pinned to 0.
public struct VerticalScrollView<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        ScrollView(.vertical) {
            content.background(VerticalOnlyAnchor())
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

#if canImport(UIKit)
/// Sits inside the scroll content, finds the `UIScrollView` around it and keeps it from moving sideways.
private struct VerticalOnlyAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView { AnchorView() }
    func updateUIView(_ uiView: AnchorView, context: Context) {}

    final class AnchorView: UIView {
        private var observation: NSKeyValueObservation?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, observation == nil, let scrollView = enclosingScrollView() else { return }
            scrollView.isDirectionalLockEnabled = true
            scrollView.alwaysBounceHorizontal = false
            scrollView.showsHorizontalScrollIndicator = false
            observation = scrollView.observe(\.contentOffset, options: [.new]) { scrollView, _ in
                // Pin the horizontal position. Only touch it when it moved, so the reset does not loop.
                if abs(scrollView.contentOffset.x + scrollView.adjustedContentInset.left) > 0.5 {
                    scrollView.contentOffset.x = -scrollView.adjustedContentInset.left
                }
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view: UIView? = superview
            while let current = view {
                if let scrollView = current as? UIScrollView { return scrollView }
                view = current.superview
            }
            return nil
        }
    }
}
#else
private struct VerticalOnlyAnchor: View {
    var body: some View { Color.clear }
}
#endif
