import AppKit
import CoreGraphics
import Foundation
import os

enum CaptureTimingMode: String, CaseIterable, Identifiable, Codable {
    case freezeFirst = "freezeFirst"
    case liveSelect = "liveSelect"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freezeFirst:
            "触发时冻结"
        case .liveSelect:
            "选区确认时冻结"
        }
    }

    var description: String {
        switch self {
        case .freezeFirst:
            "按下快捷键就固定画面，再框选。适合弹窗、菜单等临时内容。"
        case .liveSelect:
            "实时框选，松开鼠标或单击确认后固定画面，再进入编辑。"
        }
    }

    var icon: String {
        switch self {
        case .freezeFirst:
            "snow"
        case .liveSelect:
            "cursorarrow.and.square.on.square.dashed"
        }
    }
}

enum CaptureSelectionMode {
    case framed
    case display

    var instructionTitle: String {
        switch self {
        case .framed:
            "框选截图"
        case .display:
            "移动鼠标选择屏幕"
        }
    }

    func instructionCaption(hotKeyHint: String) -> String {
        switch self {
        case .framed:
            "默认高亮指针所在窗口；单击确认窗口，拖动框选区域 • 截图后可标注、提取文字、保存或钉住 • Esc 取消 • \(hotKeyHint) 唤起"
        case .display:
            "单击目标屏幕后进入编辑菜单，可标注、提取文字、保存或钉住 • 右键或 Esc 取消"
        }
    }
}

struct ScreenSelection: Equatable {
    let displayID: CGDirectDisplayID
    let rect: CGRect
    let scaleFactor: CGFloat
}

struct WindowCaptureSelection: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
    let ownerName: String
    let windowName: String?

    func clipped(to displayBounds: CGRect) -> WindowCaptureSelection? {
        let visible = bounds.intersection(displayBounds)
        guard !visible.isNull, !visible.isEmpty else { return nil }
        return WindowCaptureSelection(windowID: windowID, bounds: visible, ownerName: ownerName, windowName: windowName)
    }

    func screenSelection(displayID: CGDirectDisplayID, displayBounds: CGRect, scaleFactor: CGFloat) -> ScreenSelection? {
        guard let visible = clipped(to: displayBounds) else { return nil }
        return ScreenSelection(displayID: displayID,
            rect: visible.bounds.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY), scaleFactor: scaleFactor)
    }

    var displayName: String {
        guard let windowName else { return ownerName }

        let trimmedName = windowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return ownerName }

        return "\(ownerName) • \(trimmedName)"
    }
}

enum ScreenshotCaptureRequest: Equatable {
    case area(ScreenSelection)
    case display(ScreenSelection)
    case window(WindowCaptureSelection)
}

@MainActor
final class CaptureCoordinator {
    var onPinnedWindowsChanged: ((Int) -> Void)?

    private var overlayWindowControllers: [SelectionOverlayWindowController] = []
    private var pinnedWindowControllers: [PinnedScreenshotWindowController] = []
    private var screenshotEditorWindowController: ScreenshotEditorWindowController?
    private var cursorIsPushed = false
    private var pinnedWindowOpacity = 1.0
    private var isPinnedWindowMousePassthroughEnabled = false
    private var framedHotKeyHint = "⌘⇧S"
    private var displayHotKeyHint = "⌘⇧F"
    var captureTimingMode: CaptureTimingMode = .liveSelect
    private var frozenScreenImages: [CGDirectDisplayID: CGImage] = [:]
    private var activeCaptureTimingMode: CaptureTimingMode?
    private let captureLogger = Logger(subsystem: "com.wuqicheng.snapboard", category: "CaptureTiming")
    private let captureDisplayImage: (CGDirectDisplayID) -> CGImage?
    private let captureBelowWindow: (CGDirectDisplayID, CGWindowID) -> CGImage?

    init(
        captureDisplayImage: @escaping (CGDirectDisplayID) -> CGImage? = { CGDisplayCreateImage($0) },
        captureBelowWindow: @escaping (CGDirectDisplayID, CGWindowID) -> CGImage? = { displayID, windowID in
            CGWindowListCreateImage(CGDisplayBounds(displayID), .optionOnScreenBelowWindow, windowID, .bestResolution)
        }
    ) {
        self.captureDisplayImage = captureDisplayImage
        self.captureBelowWindow = captureBelowWindow
    }

    func prepareCapture(displayIDs: [CGDirectDisplayID]) -> Bool {
        activeCaptureTimingMode = captureTimingMode
        frozenScreenImages = [:]
        if activeCaptureTimingMode == .freezeFirst {
            return freezeDisplays(displayIDs)
        }
        return true
    }

    func freezeDisplays(_ displayIDs: [CGDirectDisplayID], belowWindows: [CGDirectDisplayID: CGWindowID] = [:]) -> Bool {
        guard !displayIDs.isEmpty else { return false }
        var images: [CGDirectDisplayID: CGImage] = [:]
        for displayID in displayIDs {
            guard displayID != 0 else { return false }
            let image: CGImage?
            if let windowID = belowWindows[displayID] {
                // Keep the overlay on screen; composite only the windows beneath it.
                image = captureBelowWindow(displayID, windowID)
            } else {
                image = captureDisplayImage(displayID)
            }
            guard let image else { return false }
            images[displayID] = image
        }
        frozenScreenImages = images
        return true
    }

    func imageForCapture(request: ScreenshotCaptureRequest) -> NSImage? {
        guard activeCaptureTimingMode != nil else { return nil }
        if activeCaptureTimingMode == .liveSelect && frozenScreenImages.isEmpty {
            // The confirmation frame is the sole source for the crop, backdrop and later recrops.
            let displayIDs: [CGDirectDisplayID]
            switch request {
            case let .area(selection), let .display(selection):
                displayIDs = [selection.displayID]
            case let .window(selection):
                displayIDs = NSScreen.screens.filter { CGDisplayBounds($0.displayID).intersects(selection.bounds) }.map(\.displayID)
            }
            let belowWindows = Dictionary(uniqueKeysWithValues: overlayWindowControllers.compactMap { controller -> (CGDirectDisplayID, CGWindowID)? in
                guard let window = controller.window else { return nil }
                return (controller.screen.displayID, CGWindowID(window.windowNumber))
            })
            guard freezeDisplays(displayIDs, belowWindows: belowWindows) else { return nil }
        }
        return ScreenshotCapturer.cropFromFrozen(request: request, frozenImages: frozenScreenImages)
    }

    private lazy var captureSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "capture", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()
    private lazy var selectCaptureSound: NSSound? = {
        guard let url = Bundle.main.url(forResource: "select_capture", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenCapturePermission() -> Bool {
        if hasScreenCapturePermission {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func presentScreenRecordingHelp() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "SnapX 需要屏幕录制权限才能截图。授权后重新点击菜单栏按钮，或按快捷键 \(allHotKeyHints)。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    func beginFramedSelectionMode() {
        beginSelectionMode(for: .framed)
    }

    func beginDisplaySelectionMode() {
        beginSelectionMode(for: .display)
    }

    private func beginSelectionMode(for mode: CaptureSelectionMode) {
        guard overlayWindowControllers.isEmpty else { return }

        // Freeze pixels and window geometry before any overlay takes focus.
        let screens = NSScreen.screens
        let frozenWindowInfo = captureTimingMode == .freezeFirst
            ? (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            : nil
        guard prepareCapture(displayIDs: screens.map(\.displayID)) else {
            cancelSelectionMode()
            let alert = NSAlert()
            alert.messageText = "无法冻结屏幕"
            alert.informativeText = "未能保存所有屏幕的画面，本次截图已取消。请检查屏幕录制权限后重试。"
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        if activeCaptureTimingMode == .freezeFirst {
            captureSound?.play()
        } else {
            selectCaptureSound?.play()
        }

        pushCrosshairCursor()

        overlayWindowControllers = screens.compactMap { screen in
            let displayID = screen.displayID
            let frozenImage = frozenScreenImages[displayID]

            let controller = SelectionOverlayWindowController(
                screen: screen,
                mode: mode,
                hotKeyHint: hotKeyHint,
                frozenImage: frozenImage,
                frozenWindowInfo: frozenWindowInfo,
                captureHandler: { [weak self] request in
                    self?.finishCapture(with: request)
                },
                cancelHandler: { [weak self] in
                    self?.cancelSelectionMode()
                }
            )
            controller.showWindow(nil)
            controller.window?.orderFrontRegardless()
            return controller
        }

        NSApp.activate(ignoringOtherApps: true)
        let targetOverlay = overlayWindowControllers.first { $0.screen.frame.contains(NSEvent.mouseLocation) }
            ?? overlayWindowControllers.first
        targetOverlay?.window?.makeKeyAndOrderFront(nil)
    }

    func cancelSelectionMode() {
        overlayWindowControllers.forEach { $0.close() }
        overlayWindowControllers.removeAll()
        frozenScreenImages = [:]
        activeCaptureTimingMode = nil
        popCrosshairCursor()
    }

    func closeAllPinnedWindows() {
        let windows = pinnedWindowControllers
        windows.forEach { $0.close() }
    }

    func pinImage(_ image: NSImage) {
        presentPinnedWindow(for: image)
    }

    func updatePinnedWindowOpacity(_ opacity: Double) {
        pinnedWindowOpacity = min(max(opacity, 0.25), 1)
        pinnedWindowControllers.forEach { $0.setWindowOpacity(pinnedWindowOpacity) }
    }

    func updatePinnedWindowMousePassthrough(_ enabled: Bool) {
        isPinnedWindowMousePassthroughEnabled = enabled
        pinnedWindowControllers.forEach { $0.setMousePassthrough(enabled) }
    }

    func updateHotKeyHints(framed: String, display: String) {
        framedHotKeyHint = framed
        displayHotKeyHint = display
    }

    private var hotKeyHint: String {
        framedHotKeyHint
    }

    private var allHotKeyHints: String {
        "\(framedHotKeyHint) / \(displayHotKeyHint)"
    }

    private func finishCapture(with request: ScreenshotCaptureRequest) {
        let captureStarted = CACurrentMediaTime()
        let image = imageForCapture(request: request)
        let frameReady = CACurrentMediaTime()
        defer {
            let captureMilliseconds = (frameReady - captureStarted) * 1000
            let editorMilliseconds = (CACurrentMediaTime() - frameReady) * 1000
            captureLogger.info("Confirmation frame: \(captureMilliseconds, privacy: .public) ms; editor preparation: \(editorMilliseconds, privacy: .public) ms")
        }

        guard let image else {
            NSSound.beep()
            cancelSelectionMode()
            return
        }

        // Hold the confirmation frame while the editor builds its first view hierarchy.
        for controller in overlayWindowControllers {
            if let frame = frozenScreenImages[controller.screen.displayID] {
                controller.freeze(frame)
            }
        }
        if activeCaptureTimingMode == .liveSelect { captureSound?.play() }

        // For area and window captures, provide the full screen image so the editor can re-crop on handle drag
        var fullScreenImage: NSImage?
        var cropInfo: ScreenshotEditorCropInfo?

        switch request {
        case let .area(selection):
            let result = resolveFullScreenImage(displayID: selection.displayID)
            fullScreenImage = result.image
            if let fullScreenImage {
                cropInfo = ScreenshotEditorCropInfo(
                    fullScreenImage: fullScreenImage,
                    selectionRect: selection.rect,
                    displayID: selection.displayID,
                    scaleFactor: selection.scaleFactor
                )
            }

        case let .window(selection):
            for screen in NSScreen.screens {
                guard screen.displayID != 0,
                      let screenSelection = selection.screenSelection(displayID: screen.displayID,
                        displayBounds: CGDisplayBounds(screen.displayID), scaleFactor: screen.backingScaleFactor) else { continue }

                let result = resolveFullScreenImage(displayID: screen.displayID)
                fullScreenImage = result.image
                if let fullScreenImage {
                    cropInfo = ScreenshotEditorCropInfo(
                        fullScreenImage: fullScreenImage,
                        selectionRect: screenSelection.rect,
                        displayID: screen.displayID,
                        scaleFactor: screen.backingScaleFactor
                    )
                }
                break
            }

        case .display:
            break
        }

        if transitionSelectionOverlayToEditor(with: image, request: request, fullScreenImage: fullScreenImage, cropInfo: cropInfo) {
            return
        }

        cancelSelectionMode()
        presentCapturedImage(image, request: request, cropInfo: cropInfo)
    }

    func resolveFullScreenImage(displayID: CGDirectDisplayID) -> (image: NSImage?, displayID: CGDirectDisplayID) {
        let matchingScreen = NSScreen.screens.first { s in
            s.displayID == displayID
        }
        if let frozenCG = frozenScreenImages[displayID] {
            let screenSize = matchingScreen?.frame.size ?? CGSize(width: frozenCG.width, height: frozenCG.height)
            return (NSImage(cgImage: frozenCG, size: screenSize), displayID)
        }
        return (nil, displayID)
    }

    private func presentCapturedImage(_ image: NSImage, request: ScreenshotCaptureRequest, cropInfo: ScreenshotEditorCropInfo? = nil) {
        let sourceRect = editorSourceRect(for: request)
        presentCapturedImage(image, sourceRect: sourceRect, cropInfo: cropInfo)
    }

    private func presentCapturedImage(_ image: NSImage, sourceRect: CGRect?, cropInfo: ScreenshotEditorCropInfo? = nil, existingWindow: NSWindow? = nil) {
        screenshotEditorWindowController?.close()

        let controller = ScreenshotEditorWindowController(
            image: image,
            sourceRect: sourceRect,
            cropInfo: cropInfo,
            existingWindow: existingWindow,
            onPin: { [weak self] editedImage in
                self?.presentPinnedWindow(for: editedImage)
            },
            onCopy: { [weak self] editedImage in
                ScreenshotHistory.shared.add(image)
                self?.copyToPasteboard(editedImage)
            },
            onClose: { [weak self] in
                self?.screenshotEditorWindowController = nil
            }
        )

        screenshotEditorWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func transitionSelectionOverlayToEditor(with image: NSImage, request: ScreenshotCaptureRequest, fullScreenImage: NSImage? = nil, cropInfo: ScreenshotEditorCropInfo? = nil) -> Bool {
        guard let sourceRect = editorSourceRect(for: request),
              let targetIndex = overlayWindowControllers.firstIndex(where: { $0.contains(globalRect: sourceRect) }),
              let transitionWindow = overlayWindowControllers[targetIndex].takeWindowForTransition() else {
            return false
        }

        let controllersToClose = overlayWindowControllers.enumerated().compactMap { index, controller in
            index == targetIndex ? nil : controller
        }
        overlayWindowControllers.removeAll()
        frozenScreenImages = [:]
        activeCaptureTimingMode = nil

        controllersToClose.forEach { $0.close() }

        popCrosshairCursor()
        presentCapturedImage(image, sourceRect: sourceRect, cropInfo: cropInfo, existingWindow: transitionWindow)
        return true
    }

    private func presentPinnedWindow(for image: NSImage) {
        let windowController = PinnedScreenshotWindowController(image: image) { [weak self] controller in
            self?.removePinnedWindow(controller)
        }

        windowController.setWindowOpacity(pinnedWindowOpacity)
        windowController.setMousePassthrough(isPinnedWindowMousePassthroughEnabled)
        pinnedWindowControllers.append(windowController)
        onPinnedWindowsChanged?(pinnedWindowControllers.count)
        windowController.showWindow(nil)
        windowController.window?.orderFrontRegardless()
    }

    private func removePinnedWindow(_ controller: PinnedScreenshotWindowController) {
        pinnedWindowControllers.removeAll { $0 === controller }
        onPinnedWindowsChanged?(pinnedWindowControllers.count)
    }

    private func editorSourceRect(for request: ScreenshotCaptureRequest) -> CGRect? {
        switch request {
        case let .area(selection):
            globalRect(for: selection)

        case let .display(selection):
            globalRect(for: selection)

        case let .window(selection):
            cocoaGlobalRect(forWindowScreenRect: selection.bounds)
        }
    }

    private func globalRect(for selection: ScreenSelection) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { screen in
            guard screen.displayID != 0 else {
                return false
            }

            return screen.displayID == selection.displayID
        }) else {
            return nil
        }

        return CGRect(
            x: screen.frame.minX + selection.rect.minX,
            y: screen.frame.maxY - selection.rect.maxY,
            width: selection.rect.width,
            height: selection.rect.height
        )
    }

    private func cocoaGlobalRect(forWindowScreenRect rect: CGRect) -> CGRect {
        let desktopTopEdge = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return CGRect(
            x: rect.minX,
            y: desktopTopEdge - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func pushCrosshairCursor() {
        guard !cursorIsPushed else { return }
        cursorIsPushed = true
        NSCursor.crosshair.push()
    }

    private func popCrosshairCursor() {
        guard cursorIsPushed else { return }
        cursorIsPushed = false
        NSCursor.pop()
    }
}

enum ScreenshotCapturer {
    @MainActor
    static func capture(request: ScreenshotCaptureRequest) -> NSImage? {
        switch request {
        case let .area(selection):
            captureArea(selection: selection)

        case let .display(selection):
            captureDisplay(selection: selection)

        case let .window(selection):
            captureWindow(selection: selection)
        }
    }

    /// Crop from a pre-captured frozen full-screen image.
    @MainActor
    static func cropFromFrozen(request: ScreenshotCaptureRequest, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        switch request {
        case let .area(selection):
            cropFrozenArea(selection: selection, frozenImages: frozenImages)

        case let .display(selection):
            cropFrozenDisplay(selection: selection, frozenImages: frozenImages)

        case let .window(selection):
            // Window capture in freeze-first mode: crop the window bounds from the frozen screen
            cropFrozenWindow(selection: selection, frozenImages: frozenImages)
        }
    }

    @MainActor
    private static func captureArea(selection: ScreenSelection) -> NSImage? {
        let captureRect = selection.rect.integral

        guard let image = CGDisplayCreateImage(selection.displayID, rect: captureRect) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.rect.size)
    }

    @MainActor
    private static func captureDisplay(selection: ScreenSelection) -> NSImage? {
        guard let image = CGDisplayCreateImage(selection.displayID) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.rect.size)
    }

    @MainActor
    private static func captureWindow(selection: WindowCaptureSelection) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            selection.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return NSImage(cgImage: image, size: selection.bounds.size)
    }

    // MARK: - Freeze-first cropping

    @MainActor
    private static func cropFrozenArea(selection: ScreenSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        guard let fullImage = frozenImages[selection.displayID] else { return nil }

        let cropRect = CGRect(
            x: selection.rect.minX * selection.scaleFactor,
            y: selection.rect.minY * selection.scaleFactor,
            width: selection.rect.width * selection.scaleFactor,
            height: selection.rect.height * selection.scaleFactor
        ).integral

        guard let cropped = fullImage.cropping(to: cropRect) else { return nil }
        return NSImage(cgImage: cropped, size: selection.rect.size)
    }

    @MainActor
    private static func cropFrozenDisplay(selection: ScreenSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        guard let fullImage = frozenImages[selection.displayID] else { return nil }
        return NSImage(cgImage: fullImage, size: selection.rect.size)
    }

    @MainActor
    private static func cropFrozenWindow(selection: WindowCaptureSelection, frozenImages: [CGDirectDisplayID: CGImage]) -> NSImage? {
        for screen in NSScreen.screens {
            guard screen.displayID != 0,
                  let screenSelection = selection.screenSelection(displayID: screen.displayID,
                    displayBounds: CGDisplayBounds(screen.displayID), scaleFactor: screen.backingScaleFactor) else { continue }
            if let image = cropFrozenArea(selection: screenSelection, frozenImages: frozenImages) { return image }
        }
        return nil
    }
}
