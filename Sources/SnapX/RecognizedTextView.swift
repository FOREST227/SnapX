import AppKit
import SwiftUI

struct RecognizedTextView: View {
    let text: String
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsWindowDragArea()
                .frame(height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("识别结果")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("已自动复制到剪贴板")
                            .panelDescription(size: 12)
                    }
                    Spacer(minLength: 0)
                    Button(action: onCopy) {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(PanelNeutralButtonStyle())
                    .help("复制全部识别文字")
                }

                RecognizedTextScrollView(text: text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppPanelStyle.controlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppPanelStyle.controlBorder.opacity(0.5), lineWidth: 0.5)
                        .allowsHitTesting(false))
            }
            .padding(.horizontal, AppPanelStyle.padding)
            .padding(.top, 8)
            .padding(.bottom, AppPanelStyle.padding)
        }
        .frame(minWidth: 360, minHeight: 280)
        .background(AppPanelStyle.background)
        .tint(AppPanelStyle.accent)
    }
}

private struct RecognizedTextScrollView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PanelOverlayScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        PanelScrollAppearance.configure(scroll)

        let textView = NSTextView(frame: .zero)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = CGSize(width: 14, height: 14)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        textView.defaultParagraphStyle = paragraph
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.setAccessibilityLabel("识别出的文字")
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        PanelScrollAppearance.configure(scroll)
        // Preserve the user's selection and scroll position during theme updates.
        if let textView = scroll.documentView as? NSTextView, textView.string != text {
            textView.string = text
        }
    }
}
