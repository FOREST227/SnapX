import AppKit
import SwiftUI

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct HighlighterNibIcon: View {
    var body: some View {
        ZStack {
            // Short collar above a broad, chisel-cut felt tip.
            Path { path in
                path.move(to: CGPoint(x: 5, y: 2))
                path.addLine(to: CGPoint(x: 13, y: 2))
                path.addLine(to: CGPoint(x: 13, y: 7))
                path.addLine(to: CGPoint(x: 5, y: 7))
                path.closeSubpath()
            }
            .stroke(.foreground, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            Path { path in
                path.move(to: CGPoint(x: 5.5, y: 8.5))
                path.addLine(to: CGPoint(x: 12.5, y: 8.5))
                path.addLine(to: CGPoint(x: 12.5, y: 12))
                path.addLine(to: CGPoint(x: 5.5, y: 16))
                path.closeSubpath()
            }
            .fill(.foreground)
        }
        .frame(width: 18, height: 18)
        .rotationEffect(.degrees(40))
        // Center the visible nib after rotation, rather than its empty canvas.
        .offset(x: -0.5, y: 1.5)
        .accessibilityHidden(true)
    }
}

private struct MosaicToolIcon: View {
    private let shades: [Double] = [1, 0.42, 0.72, 0.58, 0.9, 0.34, 0.4, 0.76, 1]

    var body: some View {
        VStack(spacing: 1.4) {
            ForEach(0..<3) { row in
                HStack(spacing: 1.4) {
                    ForEach(0..<3) { column in
                        RoundedRectangle(cornerRadius: 0.8)
                            .fill(.foreground)
                            .opacity(shades[row * 3 + column])
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }
}

private struct ToolOptionsAnchorKey: PreferenceKey {
    static var defaultValue: [ScreenshotEditorTool: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ScreenshotEditorTool: Anchor<CGRect>],
                       nextValue: () -> [ScreenshotEditorTool: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ToolbarBubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct ScreenshotEditorRootView: View {
    private static let selectionFrameColor = Color(red: 0.2, green: 0.86, blue: 0.56)

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: ScreenshotEditorViewModel
    let layout: ScreenshotEditorLayout
    let onClose: () -> Void
    let onDone: () -> Void
    let onPin: () -> Void
    let onSave: () -> Void
    let onExtractText: () -> Void

    @State private var draftRectangle: CGRect?
    @State private var draftHighlight: HighlightAnnotation?
    @State private var draftArrow: DraftArrow?
    @State private var draftArrowPoints: [CGPoint] = []
    @State private var draftLine: DraftLine?
    @State private var draftPenPoints: [CGPoint] = []
    @State private var draftMosaicPoints: [CGPoint] = []
    @State private var draftTextOrigin: CGPoint?
    @State private var draftText = ""
    // Native NSTextView focus is managed by InlineTextEditor, not SwiftUI .focused.
    @State private var isTextFieldFocused = false
    @State private var showToolShortcuts: Bool = false

    @State private var currentImageRect: CGRect
    @State private var cropAdjustRect: CGRect?
    @State private var isCropDragging = false
    @State private var cropDragEdge: CropEdge?
    @State private var cropDragStart: CGPoint?
    @State private var cropOriginalRect: CGRect?
    @State private var draggingTextIndex: Int?
    @State private var selectedTextIndex: Int?
    @State private var editingTextIndex: Int?
    @State private var movedText: TextAnnotation?
    @State private var textEditorHeight: CGFloat = 40

    init(
        viewModel: ScreenshotEditorViewModel,
        layout: ScreenshotEditorLayout,
        onClose: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onPin: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onExtractText: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.layout = layout
        self.onClose = onClose
        self.onDone = onDone
        self.onPin = onPin
        self.onSave = onSave
        self.onExtractText = onExtractText
        _currentImageRect = State(initialValue: layout.imageRect)
    }

    private let rectangleLineWidth: CGFloat = 4
    private let arrowLineWidth: CGFloat = 4
    private let lineLineWidth: CGFloat = 4
    private let penLineWidth: CGFloat = 4
    private let cropHandleSize: CGFloat = 8
    private let cropHandleHitTolerance: CGFloat = 10

    private var currentDisplayScale: CGFloat {
        max(currentImageRect.width / max(viewModel.image.size.width, 1), 0.01)
    }

    private var displayImageRect: CGRect {
        isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenshotEditorBackdropView(
                screenSize: layout.screenSize,
                imageRect: displayImageRect
            )

            imageStage
                .frame(width: currentImageRect.width, height: currentImageRect.height)
                .offset(x: currentImageRect.minX, y: currentImageRect.minY)
                .opacity(isCropDragging ? 0.3 : 1)

            if isCropDragging, let adjustRect = cropAdjustRect, let fullImg = viewModel.cropInfo?.fullScreenImage {
                Image(nsImage: fullImg)
                    .resizable()
                    .frame(width: layout.screenSize.width, height: layout.screenSize.height)
                    .mask(
                        Rectangle()
                            .frame(width: adjustRect.width, height: adjustRect.height)
                            .offset(x: adjustRect.midX - layout.screenSize.width / 2,
                                    y: adjustRect.midY - layout.screenSize.height / 2)
                    )

                SelectionFrameChromeView(
                    size: adjustRect.size,
                    borderColor: Self.selectionFrameColor
                )
                .offset(x: adjustRect.minX, y: adjustRect.minY)
            }

            if viewModel.canAdjustCrop {
                cropHandleOverlay
            }

            toolbar
                .fixedSize()
                .frame(width: layout.toolbarRect.width, height: layout.toolbarRect.height)
                .offset(x: layout.toolbarRect.minX, y: toolbarTop)

            if let toastMessage = viewModel.toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.75)),
                        removal: .move(edge: .top).combined(with: .opacity).animation(.smooth(duration: 0.2))
                    ))
            }

            if showToolShortcuts {
                ToolShortcutsOverlay()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.75)),
                        removal: .scale(scale: 0.95).combined(with: .opacity).animation(.smooth(duration: 0.2))
                    ))
            }
        }
        .frame(width: layout.screenSize.width, height: layout.screenSize.height)
        .background(Color.clear)
        .overlayPreferenceValue(ToolOptionsAnchorKey.self) { anchors in
            GeometryReader { geometry in
                if let anchor = anchors[viewModel.activeTool] {
                    let buttonRect = geometry[anchor]
                    let left = min(max(buttonRect.minX, 12), max(12, geometry.size.width - 220 - 12))
                    toolOptionsBubble(arrowOffset: min(max(buttonRect.midX - left - 6, 8), 200))
                        .position(x: left + 110, y: buttonRect.maxY + 8 + toolOptionsHeight / 2)
                }
            }
        }
        .onChange(of: viewModel.activeTool) { _ in
            draftHighlight = nil
            draftArrow = nil
            draftArrowPoints = []
            commitTextDraftIfNeeded()
        }
        .onChange(of: viewModel.textDraftDiscardRequest) { shouldDiscard in
            if shouldDiscard {
                discardDraftText()
                viewModel.textDraftDiscardRequest = false
            }
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.25).delay(0.05)) {
                showToolShortcuts = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.smooth(duration: 0.25)) {
                    showToolShortcuts = false
                }
            }
        }
    }

    // MARK: - Image Stage

    private var imageStage: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: viewModel.image)
                .resizable()
                .frame(width: currentImageRect.width, height: currentImageRect.height)

            if let pixelatedPreviewImage = viewModel.pixelatedPreviewImage,
               hasVisibleMosaicContent {
                Image(nsImage: pixelatedPreviewImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: currentImageRect.width, height: currentImageRect.height)
                    .mask(
                        MosaicMaskView(
                            annotations: viewModel.annotations,
                            draftPoints: draftMosaicPoints,
                            draftBrushSize: CGFloat(viewModel.mosaicBrushSize),
                            imageSize: viewModel.image.size,
                            displaySize: currentImageRect.size
                        )
                    )
            }

            ZStack(alignment: .topLeading) {
                ForEach(viewModel.annotations.compactMap { annotation -> HighlightAnnotation? in
                    if case let .highlight(stroke) = annotation { return stroke }
                    return nil
                }) { stroke in
                    HighlighterStrokeView(stroke: stroke, scale: currentDisplayScale)
                }
                if let draftHighlight {
                    HighlighterStrokeView(stroke: draftHighlight, scale: currentDisplayScale)
                }
            }
            .frame(width: currentImageRect.width, height: currentImageRect.height)
            .clipped()
            .allowsHitTesting(false)

            annotationOverlay.clipped()

            if viewModel.activeTool == .text {
                EditorTextInteraction(
                    onTap: { point, doubleClick in handleTextTap(at: point, doubleClick: doubleClick) },
                    onDrag: { start, current in updateTextDrag(from: start, to: current) },
                    onDragEnd: { finishTextDrag() }
                )
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { tap in
                        handleTextTap(at: tap.location, doubleClick: true)
                    })
            }

            if let index = selectedTextIndex, editingTextIndex == nil,
               case let .text(text) = viewModel.annotations[safe: index] {
                let rect = textBounds(movedText ?? text)
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: rect.width * currentDisplayScale, height: rect.height * currentDisplayScale)
                    .position(x: rect.midX * currentDisplayScale, y: rect.midY * currentDisplayScale)
                    .allowsHitTesting(false)
            }

            if let draftTextOrigin {
                draftTextEditor(at: draftTextOrigin)
            }
        }
        .overlay {
            if let scan = viewModel.ocrScan {
                OCRScanOverlay(scan: scan)
            }
        }
        .overlay((isCropDragging ? nil : selectionChrome)?.allowsHitTesting(false))
    }

    private var selectionChrome: some View {
        SelectionFrameChromeView(
            size: currentImageRect.size,
            borderColor: Self.selectionFrameColor
        )
    }

    // MARK: - Annotation Overlay

    private var annotationOverlay: some View {
        Canvas { context, _ in
            drawAnnotations(in: &context, annotations: viewModel.annotations.enumerated().compactMap { index, annotation in
                if index == editingTextIndex { return nil }
                if index == draggingTextIndex, let movedText { return .text(movedText) }
                return annotation
            })

            if let draftRectangle {
                let path = Path(roundedRect: draftRectangle, cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(lineWidth: displayStrokeWidth(for: rectangleLineWidth))
                )
            }

            if let draftArrow {
                let path = arrowPath(
                    start: draftArrow.start,
                    end: draftArrow.end,
                    control: draftArrow.controlPoint,
                    lineWidth: arrowLineWidth
                )
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: arrowLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if let draftLine {
                var path = Path()
                path.move(to: draftLine.start)
                path.addLine(to: draftLine.end)
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: lineLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if !draftPenPoints.isEmpty {
                var path = Path()
                if let first = draftPenPoints.first {
                    path.move(to: first)
                    for point in draftPenPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(viewModel.selectedColor.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: penLineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: currentImageRect.width, height: currentImageRect.height)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ScreenshotEditorTool.allCases) { tool in
                    toolbarButton(
                        icon: tool.symbolName,
                        title: tool.title,
                        isSelected: viewModel.activeTool == tool,
                        usesMosaicIcon: tool == .mosaic,
                        usesHighlighterIcon: tool == .highlight
                    ) {
                        switchTool(to: tool)
                    }
                    .anchorPreference(key: ToolOptionsAnchorKey.self, value: .bounds) {
                        tool == .highlight || tool == .mosaic || tool == .text ? [tool: $0] : [:]
                    }
                }
            }

            if viewModel.activeTool.supportsColorSelection {
                toolbarDivider

                HStack(spacing: 10) {
                    ForEach(ScreenshotAnnotationColor.allCases) { color in
                        Button {
                            viewModel.selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .stroke(viewModel.selectedColor == color ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }


            toolbarDivider

            toolbarButton(icon: "arrow.uturn.backward", title: "撤销", isSelected: false, isDisabled: !viewModel.canUndo) {
                triggerEditingAction {
                    viewModel.undoLastAnnotation()
                }
            }

            if viewModel.isExtractingText {
                ProgressView().controlSize(.small).frame(width: 30, height: 30)
                    .accessibilityLabel("正在提取文字")
                    .help("正在提取文字…")
            } else {
                toolbarButton(icon: "text.viewfinder", title: "提取文字", isSelected: false) {
                    triggerEditingAction(action: onExtractText)
                }
            }

            toolbarButton(icon: "square.and.arrow.down", title: "保存", isSelected: false) {
                triggerEditingAction(action: onSave)
            }

            toolbarButton(icon: "pin", title: "钉住", isSelected: false) {
                triggerEditingAction(action: onPin)
            }

            toolbarDivider

            toolbarButton(icon: "xmark", title: "关闭", isSelected: false, destructive: true) {
                discardDraftText()
                onClose()
            }

            toolbarButton(icon: "checkmark", title: "完成", isSelected: false, accent: true) {
                triggerEditingAction(action: onDone)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .light ? AppPanelStyle.controlFill.opacity(0.94) : .clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .light ? Color.black.opacity(0.1) : Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .light ? 0.14 : 0.22), radius: 16, y: 10)
    }

    private var highlightTransparencyPercent: Int {
        Int(((1 - viewModel.highlightOpacity) * 100).rounded())
    }

    private var toolOptionsHeight: CGFloat { viewModel.activeTool == .highlight ? 160 : 96 }

    private var toolbarTop: CGFloat {
        guard viewModel.activeTool == .highlight || viewModel.activeTool == .mosaic || viewModel.activeTool == .text else { return layout.toolbarRect.minY }
        // Keep the property bubble below its tool even when the toolbar is near the screen edge.
        let availableTop = layout.screenSize.height - layout.toolbarRect.height - 8 - toolOptionsHeight - 12
        return min(layout.toolbarRect.minY, max(12, availableTop))
    }

    private func toolOptionsBubble(arrowOffset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolbarBubblePointer()
                .fill(.regularMaterial)
                .frame(width: 12, height: 6)
                .padding(.leading, arrowOffset)
            VStack(spacing: 8) {
                if viewModel.activeTool == .text {
                    textOptions
                } else {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.activeTool == .highlight ? "circle.lefthalf.filled" : "circle.dashed")
                    Text(viewModel.activeTool == .highlight ? "透明度" : "笔刷大小")
                    Spacer()
                    Text(viewModel.activeTool == .highlight ? "\(highlightTransparencyPercent)%" : "\(Int(viewModel.mosaicBrushSize))")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                if viewModel.activeTool == .highlight {
                    Slider(value: Binding(
                        get: { 1 - viewModel.highlightOpacity },
                        set: { viewModel.highlightOpacity = 1 - ($0 * 100).rounded() / 100 }
                    ), in: 0...1)
                    .accessibilityLabel("高亮透明度")
                    .accessibilityValue("\(highlightTransparencyPercent)%")
                    .help("调整之后绘制的高亮透明度")
                } else {
                    Slider(value: Binding(
                        get: { viewModel.mosaicBrushSize },
                        set: { viewModel.mosaicBrushSize = $0.rounded() }
                    ), in: 8...100)
                    .accessibilityLabel("马赛克笔刷大小")
                    .accessibilityValue("\(Int(viewModel.mosaicBrushSize))")
                    .help("调整之后绘制的马赛克笔刷直径")
                }
                HStack {
                    Text(viewModel.activeTool == .highlight ? "0% 不透明" : "8 · 细")
                    Spacer()
                    Text(viewModel.activeTool == .highlight ? "100% 全透明" : "100 · 粗")
                }
                .font(.system(size: 11))
                .foregroundStyle(AppPanelStyle.secondaryText)
                if viewModel.activeTool == .highlight {
                    HStack(spacing: 6) {
                        Image(systemName: "paintbrush.pointed")
                        Text("笔刷大小")
                        Spacer()
                        Text("\(Int(viewModel.highlightBrushSize))pt").monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                    Slider(value: $viewModel.highlightBrushSize, in: 8...64, step: 1)
                        .accessibilityLabel("荧光笔笔刷大小")
                        .accessibilityValue("\(Int(viewModel.highlightBrushSize))点")
                    HStack { Text("8pt · 细"); Spacer(); Text("64pt · 粗") }
                        .font(.system(size: 11))
                        .foregroundStyle(AppPanelStyle.secondaryText)
                }
                }
            }
            .padding(12)
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5))
        }
        .frame(width: 220, height: toolOptionsHeight, alignment: .topLeading)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
            .frame(width: 1, height: 24)
    }

    private func toolbarButton(
        icon: String,
        title: String,
        isSelected: Bool,
        isDisabled: Bool = false,
        accent: Bool = false,
        destructive: Bool = false,
        usesMosaicIcon: Bool = false,
        usesHighlighterIcon: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if usesHighlighterIcon {
                    HighlighterNibIcon()
                } else if usesMosaicIcon {
                    MosaicToolIcon()
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
                .frame(width: 18, height: 18, alignment: .center)
                .foregroundStyle(buttonForeground(isSelected: isSelected, accent: accent || destructive, isDisabled: isDisabled))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(destructive && !isDisabled ? ScreenshotAnnotationColor.red.swiftUIColor : buttonBackground(isSelected: isSelected, accent: accent, isDisabled: isDisabled))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
    }

    private func textFormatToggle(icon: String, title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func buttonForeground(isSelected: Bool, accent: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return colorScheme == .dark ? Color.white.opacity(0.32) : Color.primary.opacity(0.28)
        }

        if accent || isSelected {
            return .white
        }

        return Color(nsColor: .labelColor).opacity(0.92)
    }

    private func buttonBackground(isSelected: Bool, accent: Bool, isDisabled: Bool) -> Color {
        if isDisabled {
            return colorScheme == .dark ? Color.white.opacity(0.04) : AppPanelStyle.lightToolbarButtonFill.opacity(0.45)
        }

        if accent {
            return Color.accentColor
        }

        if isSelected {
            return Color.accentColor.opacity(0.82)
        }

        return colorScheme == .dark ? Color.white.opacity(0.1) : AppPanelStyle.lightToolbarButtonFill
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard draftTextOrigin == nil else { return }

                let start = clampedDisplayPoint(for: value.startLocation)
                let current = clampedDisplayPoint(for: value.location)

                switch viewModel.activeTool {
                case .rectangle:
                    draftRectangle = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    ).integral

                case .highlight:
                    if draftHighlight == nil {
                        draftHighlight = viewModel.makeHighlight(points: [displayPointToImagePoint(start)])
                    }
                    let point = displayPointToImagePoint(current)
                    if let last = draftHighlight?.points.last,
                       hypot(last.x - point.x, last.y - point.y) >= 1 {
                        draftHighlight?.points.append(point)
                    }

                case .arrow:
                    if draftArrowPoints.isEmpty { draftArrowPoints = [start] }
                    if let last = draftArrowPoints.last, hypot(last.x - current.x, last.y - current.y) >= 2 {
                        draftArrowPoints.append(current)
                    }
                    if draftArrowPoints.count > 256 {
                        draftArrowPoints = draftArrowPoints.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
                    }
                    let samples = draftArrowPoints.last == current ? draftArrowPoints : draftArrowPoints + [current]
                    draftArrow = DraftArrow(start: start, end: current,
                        controlPoint: CurvedArrowGeometry.controlPoint(for: samples).map { clampedDisplayPoint(for: $0) })

                case .line:
                    draftLine = DraftLine(start: start, end: current)

                case .pen:
                    if draftPenPoints.isEmpty {
                        draftPenPoints = [start]
                    }
                    if let last = draftPenPoints.last,
                       hypot(last.x - current.x, last.y - current.y) >= 2 {
                        draftPenPoints.append(current)
                    }

                case .mosaic:
                    if draftMosaicPoints.isEmpty {
                        draftMosaicPoints = [start]
                    }
                    if let last = draftMosaicPoints.last,
                       hypot(last.x - current.x, last.y - current.y) >= 2 {
                        draftMosaicPoints.append(current)
                    }

                case .text:
                    updateTextDrag(from: start, to: current)
                }
            }
            .onEnded { value in
                if let index = draggingTextIndex {
                    if let movedText { viewModel.annotations[index] = .text(movedText) }
                    movedText = nil
                    draggingTextIndex = nil
                    return
                }

                let start = clampedDisplayPoint(for: value.startLocation)
                let end = clampedDisplayPoint(for: value.location)

                switch viewModel.activeTool {
                case .rectangle:
                    defer { draftRectangle = nil }
                    guard let draftRectangle, draftRectangle.width >= 8, draftRectangle.height >= 8 else { return }
                    viewModel.addAnnotation(
                        .rectangle(
                            RectangleAnnotation(
                                rect: displayRectToImageRect(draftRectangle),
                                color: viewModel.selectedColor,
                                lineWidth: rectangleLineWidth,
                                lineStyle: .solid
                            )
                        )
                    )

                case .highlight:
                    defer { draftHighlight = nil }
                    var stroke = draftHighlight ?? viewModel.makeHighlight(points: [displayPointToImagePoint(start)])
                    let point = displayPointToImagePoint(end)
                    if stroke.points.last != point { stroke.points.append(point) }
                    viewModel.addHighlight(stroke)

                case .arrow:
                    defer { draftArrow = nil; draftArrowPoints = [] }
                    guard hypot(end.x - start.x, end.y - start.y) >= 10 else { return }
                    let samples = draftArrowPoints.isEmpty ? [start, end] : (draftArrowPoints.last == end ? draftArrowPoints : draftArrowPoints + [end])
                    let control = CurvedArrowGeometry.controlPoint(for: samples)
                        .map { clampedDisplayPoint(for: $0) }
                    viewModel.addAnnotation(.arrow(ArrowAnnotation(
                        start: displayPointToImagePoint(start), end: displayPointToImagePoint(end),
                        color: viewModel.selectedColor, lineWidth: arrowLineWidth,
                        controlPoint: control.map(displayPointToImagePoint))))

                case .line:
                    defer { draftLine = nil }
                    guard hypot(end.x - start.x, end.y - start.y) >= 10 else { return }
                    viewModel.addAnnotation(
                        .line(
                            LineAnnotation(
                                start: displayPointToImagePoint(start),
                                end: displayPointToImagePoint(end),
                                color: viewModel.selectedColor,
                                lineWidth: lineLineWidth
                            )
                        )
                    )

                case .pen:
                    defer { draftPenPoints = [] }
                    guard draftPenPoints.count >= 2 else { return }
                    viewModel.addAnnotation(
                        .pen(
                            PenAnnotation(
                                points: draftPenPoints.map(displayPointToImagePoint),
                                color: viewModel.selectedColor,
                                lineWidth: penLineWidth
                            )
                        )
                    )

                case .mosaic:
                    defer { draftMosaicPoints = [] }
                    let points = draftMosaicPoints.isEmpty ? [start] : draftMosaicPoints
                    guard !points.isEmpty else { return }
                    viewModel.addMosaic(points: points.map(displayPointToImagePoint))

                case .text:
                    break
                }
            }
    }

    private func updateTextDrag(from start: CGPoint, to current: CGPoint) {
        guard draftTextOrigin == nil, hypot(current.x - start.x, current.y - start.y) > 3 else { return }
        if draggingTextIndex == nil {
            draggingTextIndex = findTextAnnotation(near: displayPointToImagePoint(start), radius: 4 / currentDisplayScale)?.0
            selectedTextIndex = draggingTextIndex
        }
        if let index = draggingTextIndex, case let .text(original) = viewModel.annotations[safe: index] {
            movedText = TextAnnotation(
                origin: CGPoint(x: max(0, min(viewModel.image.size.width - 20, original.origin.x + (current.x - start.x) / currentDisplayScale)),
                                y: max(0, min(viewModel.image.size.height - 20, original.origin.y + (current.y - start.y) / currentDisplayScale))),
                text: original.text, color: original.color, fontSize: original.fontSize,
                isBold: original.isBold, isItalic: original.isItalic, isUnderline: original.isUnderline,
                maxWidth: original.maxWidth)
        }
    }

    private func finishTextDrag() {
        if let index = draggingTextIndex, let movedText, viewModel.annotations.indices.contains(index) {
            viewModel.annotations[index] = .text(movedText)
        }
        movedText = nil
        draggingTextIndex = nil
    }

    // MARK: - Tap Gesture

    private func handleTextTap(at point: CGPoint, doubleClick: Bool) {
        guard viewModel.activeTool == .text else {
            if doubleClick { triggerEditingAction(action: onDone) }
            return
        }
        if draftTextOrigin != nil {
            commitTextDraftIfNeeded()
            return
        }
        if let (index, text) = findTextAnnotation(near: displayPointToImagePoint(point), radius: 4 / currentDisplayScale) {
            selectedTextIndex = index
            guard doubleClick else { return }
            editingTextIndex = index
            viewModel.selectedColor = text.color
            viewModel.textFontSize = text.fontSize
            viewModel.textIsBold = text.isBold
            viewModel.textIsItalic = text.isItalic
            viewModel.textIsUnderline = text.isUnderline
            draftTextOrigin = imagePointToDisplayPoint(text.origin)
            draftText = text.text
        } else {
            selectedTextIndex = nil
            editingTextIndex = nil
            draftTextOrigin = clampedTextOrigin(for: point)
            draftText = ""
        }
        textEditorHeight = viewModel.textFontSize * currentDisplayScale + 8
        viewModel.hasActiveTextDraft = true
        isTextFieldFocused = true
    }

    private func textBounds(_ text: TextAnnotation) -> CGRect {
        let width = max(20, min(text.maxWidth ?? (viewModel.image.size.width - text.origin.x - 8), viewModel.image.size.width - text.origin.x))
        let bounds = (text.text as NSString).boundingRect(with: CGSize(width: width, height: 10000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: text.fontSize, weight: text.isBold ? .bold : .regular)])
        return CGRect(origin: text.origin, size: CGSize(width: min(width, max(20, ceil(bounds.width))), height: max(text.fontSize * 1.2, ceil(bounds.height))))
    }

    private func findTextAnnotation(near point: CGPoint, radius: CGFloat) -> (Int, TextAnnotation)? {
        for (index, annotation) in viewModel.annotations.enumerated().reversed() {
            if case let .text(text) = annotation, textBounds(text).insetBy(dx: -radius, dy: -radius).contains(point) {
                return (index, text)
            }
        }
        return nil
    }

    // MARK: - Annotation Drawing

    private func drawAnnotations(in context: inout GraphicsContext, annotations: [ScreenshotEditorAnnotation]) {
        for annotation in annotations {
            switch annotation {
            case let .rectangle(rectangle):
                let rect = imageRectToDisplayRect(rectangle.rect)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(rectangle.color.swiftUIColor),
                    style: StrokeStyle(lineWidth: displayStrokeWidth(for: rectangle.lineWidth))
                )

            case .highlight:
                break

            case let .arrow(arrow):
                let path = arrowPath(
                    start: imagePointToDisplayPoint(arrow.start),
                    end: imagePointToDisplayPoint(arrow.end),
                    control: arrow.controlPoint.map(imagePointToDisplayPoint),
                    lineWidth: arrow.lineWidth
                )
                context.stroke(
                    path,
                    with: .color(arrow.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: arrow.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .line(line):
                var path = Path()
                path.move(to: imagePointToDisplayPoint(line.start))
                path.addLine(to: imagePointToDisplayPoint(line.end))
                context.stroke(
                    path,
                    with: .color(line.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: line.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .pen(pen):
                var path = Path()
                let displayPoints = pen.points.map(imagePointToDisplayPoint)
                if let first = displayPoints.first {
                    path.move(to: first)
                    for point in displayPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(pen.color.swiftUIColor),
                    style: StrokeStyle(
                        lineWidth: displayStrokeWidth(for: pen.lineWidth),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            case let .text(text):
                let fontSize = max(text.fontSize * currentDisplayScale, 14)
                let weight: Font.Weight = text.isBold ? .bold : .regular

                var textView = Text(text.text)
                    .font(Font.system(size: fontSize, weight: weight))

                if text.isItalic {
                    textView = textView.italic()
                }

                if text.isUnderline {
                    textView = textView.underline()
                }

                var resolvedText = context.resolve(textView)
                resolvedText.shading = .color(text.color.swiftUIColor)
                let width = max(20, min(text.maxWidth ?? (viewModel.image.size.width - text.origin.x - 8), viewModel.image.size.width - text.origin.x)) * currentDisplayScale
                context.draw(resolvedText, in: CGRect(origin: imagePointToDisplayPoint(text.origin), size: CGSize(width: width, height: max(20, currentImageRect.height - text.origin.y * currentDisplayScale))))

            case .mosaic:
                break
            }
        }
    }

    private func arrowPath(start: CGPoint, end: CGPoint, control: CGPoint?, lineWidth: CGFloat) -> Path {
        Path(CurvedArrowGeometry.path(start: displayPointToImagePoint(start), end: displayPointToImagePoint(end),
            control: control.map(displayPointToImagePoint), lineWidth: lineWidth))
            .applying(CGAffineTransform(scaleX: currentDisplayScale, y: currentDisplayScale))
    }

    // MARK: - Text Editor

    private func draftTextEditor(at origin: CGPoint) -> some View {
        let fontSize = max(viewModel.textFontSize * currentDisplayScale, 14)
        let width = max(24, min(320, currentImageRect.width - origin.x - 8))
        let height = max(24, min(textEditorHeight, currentImageRect.height - origin.y - 8))
        return InlineTextEditor(
            text: $draftText, fontSize: fontSize,
            fontWeight: viewModel.textIsBold ? .bold : .regular,
            isItalic: viewModel.textIsItalic, isUnderline: viewModel.textIsUnderline,
            textColor: NSColor(viewModel.selectedColor.swiftUIColor), focused: isTextFieldFocused,
            onCommit: { commitTextDraftIfNeeded() }, onEscape: { discardDraftText() },
            onHeightChange: { textEditorHeight = $0 }
        )
        .frame(width: width, height: height)
        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1).padding(-3).allowsHitTesting(false))
        .position(x: origin.x + width / 2, y: origin.y + height / 2)
    }

    private var textOptions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("字号").font(.system(size: 12))
                Stepper("\(Int(viewModel.textFontSize))", value: $viewModel.textFontSize, in: 12...72, step: 2)
                    .font(.system(size: 12)).monospacedDigit()
            }
            HStack(spacing: 8) {
                textFormatToggle(icon: "bold", title: "加粗", isOn: viewModel.textIsBold) { viewModel.textIsBold.toggle() }
                textFormatToggle(icon: "italic", title: "斜体", isOn: viewModel.textIsItalic) { viewModel.textIsItalic.toggle() }
                textFormatToggle(icon: "underline", title: "下划线", isOn: viewModel.textIsUnderline) { viewModel.textIsUnderline.toggle() }
                Spacer()
                Button("完成") { commitTextDraftIfNeeded() }.disabled(draftTextOrigin == nil)
                    .help("⌘Enter 完成，Enter 换行，Esc 取消")
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Text Draft Management

    private func switchTool(to tool: ScreenshotEditorTool) {
        commitTextDraftIfNeeded()
        selectedTextIndex = nil
        viewModel.activeTool = tool
    }

    private func triggerEditingAction(action: () -> Void) {
        commitTextDraftIfNeeded()
        action()
    }

    private func commitTextDraftIfNeeded() {
        guard let draftTextOrigin else { return }
        defer {
            editingTextIndex = nil
            selectedTextIndex = nil
            self.draftTextOrigin = nil
            draftText = ""
            isTextFieldFocused = false
            viewModel.hasActiveTextDraft = false
        }

        let trimmedText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            if let index = editingTextIndex, viewModel.annotations.indices.contains(index) {
                viewModel.annotations.remove(at: index)
            }
            return
        }

        let annotation = ScreenshotEditorAnnotation.text(TextAnnotation(
            origin: displayPointToImagePoint(draftTextOrigin), text: draftText,
            color: viewModel.selectedColor, fontSize: viewModel.textFontSize,
            isBold: viewModel.textIsBold, isItalic: viewModel.textIsItalic, isUnderline: viewModel.textIsUnderline,
            maxWidth: max(24, min(320, currentImageRect.width - draftTextOrigin.x - 8)) / currentDisplayScale))
        if let index = editingTextIndex, viewModel.annotations.indices.contains(index) {
            viewModel.annotations[index] = annotation
        } else {
            viewModel.addAnnotation(annotation)
        }
    }

    private func discardDraftText() {
        editingTextIndex = nil
        selectedTextIndex = nil
        draftTextOrigin = nil
        draftText = ""
        isTextFieldFocused = false
        viewModel.hasActiveTextDraft = false
    }

    // MARK: - Crop Adjustment

    private var cropHandleOverlay: some View {
        CropHandleHitView(
            rect: isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect,
            tolerance: cropHandleHitTolerance
        )
        .gesture(cropDragGesture)
        .frame(width: layout.screenSize.width, height: layout.screenSize.height)
        .allowsHitTesting(viewModel.canAdjustCrop)
    }

    private var cropDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                let point = value.startLocation
                if cropDragEdge == nil {
                    viewModel.cancelTextExtraction()
                    let targetRect = isCropDragging ? (cropAdjustRect ?? currentImageRect) : currentImageRect
                    cropDragEdge = cropEdge(at: point, in: targetRect)
                    cropDragStart = point
                    cropOriginalRect = targetRect
                    isCropDragging = true
                }

                guard let edge = cropDragEdge,
                      let originalRect = cropOriginalRect else { return }

                let dx = value.location.x - (cropDragStart?.x ?? value.location.x)
                let dy = value.location.y - (cropDragStart?.y ?? value.location.y)

                cropAdjustRect = adjustedCropRect(originalRect, edge: edge, dx: dx, dy: dy)
            }
            .onEnded { _ in
                if let finalRect = cropAdjustRect {
                    applyCropAdjustment(finalRect)
                    currentImageRect = finalRect
                }
                cropDragEdge = nil
                cropDragStart = nil
                cropOriginalRect = nil
                isCropDragging = false
                cropAdjustRect = nil
            }
    }

    private func cropEdge(at point: CGPoint, in rect: CGRect) -> CropEdge? {
        let ht = cropHandleHitTolerance + cropHandleSize / 2
        let corners: [(CropEdge, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
        ]
        for (edge, center) in corners {
            if hypot(point.x - center.x, point.y - center.y) <= ht { return edge }
        }

        let midpoints: [(CropEdge, CGPoint)] = [
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
        ]
        for (edge, center) in midpoints {
            if hypot(point.x - center.x, point.y - center.y) <= ht { return edge }
        }

        let et = cropHandleHitTolerance
        if abs(point.y - rect.minY) <= et, point.x >= rect.minX, point.x <= rect.maxX { return .top }
        if abs(point.y - rect.maxY) <= et, point.x >= rect.minX, point.x <= rect.maxX { return .bottom }
        if abs(point.x - rect.minX) <= et, point.y >= rect.minY, point.y <= rect.maxY { return .left }
        if abs(point.x - rect.maxX) <= et, point.y >= rect.minY, point.y <= rect.maxY { return .right }

        return .move
    }

    private func adjustedCropRect(_ original: CGRect, edge: CropEdge, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY
        let minSize: CGFloat = 40
        let screenW = layout.screenSize.width
        let screenH = layout.screenSize.height

        switch edge {
        case .topLeft:     minX += dx; minY += dy
        case .top:         minY += dy
        case .topRight:    maxX += dx; minY += dy
        case .left:        minX += dx
        case .right:       maxX += dx
        case .bottomLeft:  minX += dx; maxY += dy
        case .bottom:      maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        case .move:
            var newOriginX = original.minX + dx
            var newOriginY = original.minY + dy
            newOriginX = max(0, min(newOriginX, screenW - original.width))
            newOriginY = max(0, min(newOriginY, screenH - original.height))
            return CGRect(x: newOriginX, y: newOriginY, width: original.width, height: original.height).integral
        }

        if maxX - minX < minSize {
            switch edge {
            case .topLeft, .left, .bottomLeft: minX = maxX - minSize
            default: maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            switch edge {
            case .topLeft, .top, .topRight: minY = maxY - minSize
            default: maxY = minY + minSize
            }
        }

        minX = max(0, minX)
        minY = max(0, minY)
        maxX = min(screenW, maxX)
        maxY = min(screenH, maxY)

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    private func applyCropAdjustment(_ screenRect: CGRect) {
        guard viewModel.cropInfo != nil else { return }

        let newSelectionRect = CGRect(
            x: screenRect.minX,
            y: screenRect.minY,
            width: screenRect.width,
            height: screenRect.height
        )

        guard newSelectionRect.width >= 8, newSelectionRect.height >= 8 else { return }

        viewModel.recrop(newRect: newSelectionRect)
    }

    // MARK: - Coordinate Conversion

    private func clampedDisplayPoint(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), currentImageRect.width),
            y: min(max(point.y, 0), currentImageRect.height)
        )
    }

    private func clampedTextOrigin(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 12), max(currentImageRect.width - 80, 12)),
            y: min(max(point.y, 12), max(currentImageRect.height - 40, 12))
        )
    }

    private func imagePointToDisplayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * currentDisplayScale,
            y: point.y * currentDisplayScale
        )
    }

    private func displayPointToImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / currentDisplayScale,
            y: point.y / currentDisplayScale
        )
    }

    private func imageRectToDisplayRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * currentDisplayScale,
            y: rect.origin.y * currentDisplayScale,
            width: rect.width * currentDisplayScale,
            height: rect.height * currentDisplayScale
        )
    }

    private func displayRectToImageRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x / currentDisplayScale,
            y: rect.origin.y / currentDisplayScale,
            width: rect.width / currentDisplayScale,
            height: rect.height / currentDisplayScale
        )
    }

    private func displayStrokeWidth(for imageStrokeWidth: CGFloat) -> CGFloat {
        max(imageStrokeWidth * currentDisplayScale, 2)
    }

    private var hasVisibleMosaicContent: Bool {
        viewModel.annotations.contains { annotation in
            if case .mosaic = annotation {
                return true
            }
            return false
        } || !draftMosaicPoints.isEmpty
    }
}

// MARK: - Inline Text Editor (WeChat-style)

struct InlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var fontWeight: NSFont.Weight
    var isItalic: Bool
    var isUnderline: Bool
    var textColor: NSColor
    var focused: Bool
    var onCommit: () -> Void
    var onEscape: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = InlineTextScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = InlineTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in coordinator?.updateTextSize() }
        textView.onCommit = { [weak coordinator = context.coordinator] in coordinator?.parent.onCommit() }
        textView.wantsKeyboardFocus = focused

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        // Focus immediately when attached; retain native IME ownership during composition.
        (textView as? InlineTextView)?.wantsKeyboardFocus = focused
        guard !textView.hasMarkedText() else { return }
        let style = Style(fontSize: fontSize, weight: fontWeight, italic: isItalic, underline: isUnderline, color: textColor)
        let styleChanged = context.coordinator.appliedStyle != style
        let replacedText = textView.string != text
        if styleChanged || replacedText {
            let selection = textView.selectedRange()
            let font = makeFont()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph
            ]
            if isUnderline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            textView.textStorage?.beginEditing()
            if styleChanged {
                textView.font = font
                textView.textColor = textColor
                textView.defaultParagraphStyle = paragraph
            }
            if replacedText { textView.string = text }
            textView.typingAttributes = attrs
            textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: textView.string.utf16.count))
            textView.textStorage?.endEditing()
            if replacedText {
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            } else if selection.location <= textView.string.utf16.count {
                textView.setSelectedRange(NSRange(location: selection.location,
                    length: min(selection.length, textView.string.utf16.count - selection.location)))
            }
            context.coordinator.appliedStyle = style
            context.coordinator.needsTextMeasurement = true
        }
        context.coordinator.updateTextSize()
    }

    struct Style: Equatable {
        let fontSize: CGFloat
        let weight: NSFont.Weight
        let italic: Bool
        let underline: Bool
        let color: NSColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func makeFont() -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if isItalic { traits.insert(.italic) }

        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
            .fontDescriptor
            .withSymbolicTraits(traits)

        return NSFont(descriptor: descriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var appliedStyle: Style?
        var needsTextMeasurement = true

        init(_ parent: InlineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            needsTextMeasurement = true
            updateTextSize()

        }

        func textDidBeginEditing(_ notification: Notification) {
            // Notify that the text view has focus
        }

        func textDidEndEditing(_ notification: Notification) {
            // Focus changes to style controls do not commit the draft.
        }

        func textShouldEndEditing(_ textView: NSText) -> Bool {
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return false
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }

        private var reportedHeight: CGFloat = 0
        private var measuredHeight: CGFloat = 0
        private var measuredWidth: CGFloat = 0
        private var isMeasuring = false
        private var heightNotificationScheduled = false

        func updateTextSize() {
            guard !isMeasuring, let textView, let scrollView, let container = textView.textContainer,
                  let manager = textView.layoutManager else { return }
            isMeasuring = true
            defer { isMeasuring = false }
            let width = max(24, scrollView.contentSize.width)
            if abs(width - measuredWidth) > 0.5 {
                measuredWidth = width
                container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                needsTextMeasurement = true
            }
            if needsTextMeasurement {
                manager.ensureLayout(for: container)
                measuredHeight = max(parent.fontSize * 1.25 + 4, ceil(manager.usedRect(for: container).height) + 4)
                needsTextMeasurement = false
            }
            let size = NSSize(width: width, height: max(measuredHeight, scrollView.contentSize.height))
            if textView.frame.size != size { textView.setFrameSize(size) }
            if abs(measuredHeight - reportedHeight) > 0.5 {
                reportedHeight = measuredHeight
                guard !heightNotificationScheduled else { return }
                heightNotificationScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.heightNotificationScheduled = false
                    self.parent.onHeightChange(self.reportedHeight)
                }
            }
        }

    }
}

private final class InlineTextScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
    }
}

private final class InlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var wantsKeyboardFocus = false { didSet { focusIfNeeded() } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }
    private func focusIfNeeded() {
        guard wantsKeyboardFocus, let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.command), !hasMarkedText() {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }


}
