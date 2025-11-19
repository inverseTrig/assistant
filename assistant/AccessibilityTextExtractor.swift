import Foundation
import ApplicationServices
import AppKit
import Vision
import CoreGraphics
import ScreenCaptureKit

class AccessibilityTextExtractor {

    enum ExtractionMethod {
        case accessibility
        case ocr
        case hybrid
    }

    // Track if we've already requested screen recording permission to avoid spamming the user
    private static var hasRequestedScreenRecordingPermission = false

    /// Check if accessibility permissions are granted
    static func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Request accessibility permissions
    static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Extract text from the currently focused application using specified method
    static func extractTextFromFocusedApp(method: ExtractionMethod = .hybrid, filterMode: ContentFilter.FilterMode = .mainContent) -> String {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost application found."
        }

        switch method {
        case .accessibility:
            return extractUsingAccessibility(app: frontmostApp, filterMode: filterMode)
        case .ocr:
            return extractUsingOCR(app: frontmostApp, filterMode: filterMode)
        case .hybrid:
            // Try accessibility first
            let accessibilityText = extractUsingAccessibility(app: frontmostApp, skipPermissionCheck: true, filterMode: filterMode)

            // If accessibility returns limited or no content, use OCR
            if accessibilityText.isEmpty || accessibilityText.contains("No text content found") || accessibilityText.count < 100 {
                return extractUsingOCR(app: frontmostApp, filterMode: filterMode)
            }

            return accessibilityText
        }
    }

    /// Extract text using Accessibility API
    private static func extractUsingAccessibility(app: NSRunningApplication, skipPermissionCheck: Bool = false, filterMode: ContentFilter.FilterMode = .mainContent) -> String {
        if !skipPermissionCheck {
            guard checkAccessibilityPermissions() else {
                requestAccessibilityPermissions()
                return "Accessibility permissions required. Please grant access in System Settings > Privacy & Security > Accessibility."
            }
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var extractedText = ""

        // Try to get focused UI element
        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if focusedResult == .success, let focused = focusedElement {
            extractedText += extractTextFromElement(focused as! AXUIElement, depth: 0, maxDepth: 5)
        }

        // If no text from focused element, try to get all text from the window
        if extractedText.isEmpty {
            var windowElement: CFTypeRef?
            let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowElement)

            if windowResult == .success, let window = windowElement {
                extractedText += extractTextFromElement(window as! AXUIElement, depth: 0, maxDepth: 5)
            }
        }

        // If still empty, try the main window
        if extractedText.isEmpty {
            var mainWindowElement: CFTypeRef?
            let mainWindowResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowElement)

            if mainWindowResult == .success, let mainWindow = mainWindowElement {
                extractedText += extractTextFromElement(mainWindow as! AXUIElement, depth: 0, maxDepth: 5)
            }
        }

        // Apply content filtering
        let filteredText = ContentFilter.filterText(extractedText, mode: filterMode)

        if filteredText.isEmpty {
            extractedText = "No text content found in the current view.\n\nApplication: \(app.localizedName ?? "Unknown")"
        } else {
            let modeLabel = filterMode == .mainContent ? "Main Content" : "All Text"
            extractedText = "Text from: \(app.localizedName ?? "Unknown") [Accessibility API - \(modeLabel)]\n\n" + filteredText
        }

        return extractedText
    }

    /// Extract text using OCR (screen capture + Vision framework)
    private static func extractUsingOCR(app: NSRunningApplication, filterMode: ContentFilter.FilterMode = .mainContent) -> String {
        var diagnostics = "=== OCR Diagnostics ===\n"
        diagnostics += "Application: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))\n"
        diagnostics += "Filter Mode: \(filterMode == .mainContent ? "Main Content" : "All Text")\n\n"

        // Check screen recording permissions (required for window capture on macOS 10.15+)
        guard checkScreenRecordingPermissions() else {
            requestScreenRecordingPermissions()
            diagnostics += "❌ Screen Recording Permission: NOT GRANTED\n"
            diagnostics += "\nPlease grant Screen Recording permission:\n"
            diagnostics += "1. Open System Settings\n"
            diagnostics += "2. Go to Privacy & Security > Screen Recording\n"
            diagnostics += "3. Enable this app\n"
            diagnostics += "4. Restart the app\n"
            return diagnostics
        }
        diagnostics += "✅ Screen Recording Permission: GRANTED\n\n"

        // Capture the frontmost window
        let (windowImage, captureDiagnostics) = captureFrontmostWindow(app: app)
        diagnostics += captureDiagnostics

        guard let image = windowImage else {
            diagnostics += "\n❌ CAPTURE FAILED\n"
            diagnostics += "\nPossible issues:\n"
            diagnostics += "- Window may not be fully visible\n"
            diagnostics += "- App may be using special rendering\n"
            diagnostics += "- Try clicking on the app window first\n"
            diagnostics += "- Try resizing the window\n"
            return diagnostics
        }

        diagnostics += "\n✅ CAPTURE SUCCESSFUL\n"
        diagnostics += "Image size: \(image.width) x \(image.height) pixels\n\n"

        // Perform OCR on the captured image with filtering
        let ocrText = performOCR(on: image, filterMode: filterMode)

        if ocrText.isEmpty {
            diagnostics += "❌ OCR: No text detected\n"
            diagnostics += "\nPossible reasons:\n"
            diagnostics += "- Window content is images/graphics only\n"
            diagnostics += "- Text is too small or blurry\n"
            diagnostics += "- Non-standard fonts\n"
            return diagnostics
        }

        diagnostics += "✅ OCR: Extracted \(ocrText.count) characters\n"
        diagnostics += "==================\n\n"

        let modeLabel = filterMode == .mainContent ? "Main Content" : "All Text"
        return "Text from: \(app.localizedName ?? "Unknown") [OCR - \(modeLabel)]\n\n" + ocrText
    }

    /// Check if screen recording permissions are granted
    private static func checkScreenRecordingPermissions() -> Bool {
        // On macOS 10.15+, we need screen recording permission to capture windows
        if #available(macOS 10.15, *) {
            // Try to get window list - if we can get it, we likely have permission
            guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                print("Failed to get window list - possible permission issue")
                return false
            }

            if windowList.isEmpty {
                print("Window list is empty - possible permission issue")
                return false
            }

            // Additional check: Try to see if we can get window names
            // If we can't see window names for other apps, we likely don't have screen recording permission
            var canSeeOtherAppWindows = false
            let currentPID = ProcessInfo.processInfo.processIdentifier

            for window in windowList {
                if let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
                   windowPID != currentPID,
                   let _ = window[kCGWindowBounds as String] as? [String: Any] {
                    canSeeOtherAppWindows = true
                    break
                }
            }

            if !canSeeOtherAppWindows {
                print("Cannot see other app windows - screen recording permission likely not granted")
                // Don't return false here as we might still be able to capture our own app
            }

            return true
        }
        return true
    }

    /// Request screen recording permissions
    private static func requestScreenRecordingPermissions() {
        // Only request once to avoid annoying the user with repeated prompts
        guard !hasRequestedScreenRecordingPermission else {
            return
        }

        hasRequestedScreenRecordingPermission = true

        // The system will automatically prompt when we try to capture
        // We can also direct the user to system settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Capture the frontmost window
    private static func captureFrontmostWindow(app: NSRunningApplication) -> (CGImage?, String) {
        var diagnostics = ""
        let pid = app.processIdentifier

        // Try modern ScreenCaptureKit first (macOS 12.3+)
        if #available(macOS 12.3, *) {
            diagnostics += "Trying ScreenCaptureKit (modern API)...\n"
            let (image, scDiag) = captureWithScreenCaptureKit(pid: pid, appName: app.localizedName ?? "Unknown")
            diagnostics += scDiag

            if let capturedImage = image {
                diagnostics += "✅ ScreenCaptureKit SUCCESS\n"
                return (capturedImage, diagnostics)
            } else {
                diagnostics += "❌ ScreenCaptureKit failed, trying legacy methods...\n\n"
            }
        }

        // Fallback to legacy CGWindowListCreateImage
        diagnostics += "Using CGWindowListCreateImage (legacy API)...\n"

        // Get list of windows for the frontmost application
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]

        guard let windows = windowList else {
            diagnostics += "❌ Failed to get window list\n"
            return (nil, diagnostics)
        }

        // Collect all windows for this app
        var appWindows: [(id: CGWindowID, layer: Int, bounds: CGRect, name: String)] = []

        for window in windows {
            if let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
               windowPID == pid,
               let windowID = window[kCGWindowNumber as String] as? CGWindowID,
               let windowLayer = window[kCGWindowLayer as String] as? Int {

                // Get window bounds to ensure it has valid size
                if let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                   let x = boundsDict["X"] as? CGFloat,
                   let y = boundsDict["Y"] as? CGFloat,
                   let width = boundsDict["Width"] as? CGFloat,
                   let height = boundsDict["Height"] as? CGFloat {

                    let bounds = CGRect(x: x, y: y, width: width, height: height)
                    let windowName = window[kCGWindowName as String] as? String ?? ""

                    // Only consider windows with reasonable size (at least 100x100)
                    if width > 100 && height > 100 {
                        appWindows.append((id: windowID, layer: windowLayer, bounds: bounds, name: windowName))
                        diagnostics += "  Window \(appWindows.count): ID=\(windowID), Layer=\(windowLayer), Size=\(Int(width))x\(Int(height))"
                        if !windowName.isEmpty {
                            diagnostics += ", Name=\"\(windowName)\"\n"
                        } else {
                            diagnostics += "\n"
                        }
                    }
                }
            }
        }

        guard !appWindows.isEmpty else {
            diagnostics += "❌ No valid windows found (>100x100) for PID \(pid)\n"
            diagnostics += "\nWindows might be too small or app has no visible windows\n"
            return (nil, diagnostics)
        }

        diagnostics += "\nFound \(appWindows.count) window(s) for \(app.localizedName ?? "app")\n\n"

        // Sort windows: prefer layer 0, then by size (larger windows first)
        appWindows.sort { w1, w2 in
            // Prefer layer 0
            if w1.layer == 0 && w2.layer != 0 {
                return true
            }
            if w1.layer != 0 && w2.layer == 0 {
                return false
            }

            // For same layer, prefer larger windows
            let area1 = w1.bounds.width * w1.bounds.height
            let area2 = w2.bounds.width * w2.bounds.height
            return area1 > area2
        }

        diagnostics += "Legacy capture attempts:\n"

        // Try multiple capture strategies
        // Strategy 1: Try capturing individual window with best resolution
        for (index, window) in appWindows.prefix(3).enumerated() {
            diagnostics += "  [\(index + 1)] Window ID \(window.id) - Best resolution + boundsIgnoreFraming... "

            if let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                window.id,
                [.bestResolution, .boundsIgnoreFraming]
            ) {
                diagnostics += "✅ SUCCESS\n"
                return (image, diagnostics)
            }
            diagnostics += "❌ Failed\n"
        }

        // Strategy 2: Try capturing without boundsIgnoreFraming
        for (index, window) in appWindows.prefix(3).enumerated() {
            diagnostics += "  [\(index + 4)] Window ID \(window.id) - Best resolution with bounds... "

            if let image = CGWindowListCreateImage(
                window.bounds,
                .optionIncludingWindow,
                window.id,
                [.bestResolution]
            ) {
                diagnostics += "✅ SUCCESS\n"
                return (image, diagnostics)
            }
            diagnostics += "❌ Failed\n"
        }

        // Strategy 3: Try capturing with nominal resolution
        for (index, window) in appWindows.prefix(3).enumerated() {
            diagnostics += "  [\(index + 7)] Window ID \(window.id) - Nominal resolution... "

            if let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                window.id,
                [.nominalResolution]
            ) {
                diagnostics += "✅ SUCCESS\n"
                return (image, diagnostics)
            }
            diagnostics += "❌ Failed\n"
        }

        // Strategy 4: Try using the window bounds as rect
        if let firstWindow = appWindows.first {
            diagnostics += "  [10] Window ID \(firstWindow.id) - Bounded with no options... "
            if let image = CGWindowListCreateImage(
                firstWindow.bounds,
                .optionIncludingWindow,
                firstWindow.id,
                []
            ) {
                diagnostics += "✅ SUCCESS\n"
                return (image, diagnostics)
            }
            diagnostics += "❌ Failed\n"
        }

        diagnostics += "\n❌ All \(appWindows.count * 3 + 1) capture strategies failed\n"
        return (nil, diagnostics)
    }

    /// Capture window using modern ScreenCaptureKit API
    @available(macOS 12.3, *)
    private static func captureWithScreenCaptureKit(pid: pid_t, appName: String) -> (CGImage?, String) {
        var diagnostics = ""
        let semaphore = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?
        var errorMessage: String?
        var windowCount: Int = 0
        var windowInfo: String?

        Task {
            do {
                // Get available content
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Find windows for our PID
                let targetWindows = content.windows.filter { $0.owningApplication?.processID == pid }
                windowCount = targetWindows.count

                guard let window = targetWindows.first(where: { $0.frame.width > 100 && $0.frame.height > 100 }) else {
                    errorMessage = "No suitable windows found (all too small or none exist)"
                    semaphore.signal()
                    return
                }

                windowInfo = "\(window.title ?? "Untitled") (\(Int(window.frame.width))x\(Int(window.frame.height)))"

                // Create filter for specific window
                let filter = SCContentFilter(desktopIndependentWindow: window)

                // Configure capture
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width) * 2  // Retina resolution
                config.height = Int(window.frame.height) * 2

                // Capture screenshot
                capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                semaphore.signal()
            } catch let error as NSError {
                // Check for specific error codes
                if error.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && error.code == -3801 {
                    errorMessage = "⚠️ SCREEN RECORDING PERMISSION NOT GRANTED\n"
                    errorMessage! += "  ScreenCaptureKit requires Screen Recording permission.\n"
                    errorMessage! += "  \n"
                    errorMessage! += "  TO FIX:\n"
                    errorMessage! += "  1. Open System Settings\n"
                    errorMessage! += "  2. Go to Privacy & Security > Screen Recording\n"
                    errorMessage! += "  3. Make sure this app is listed and ENABLED (checked)\n"
                    errorMessage! += "  4. Restart this app\n"
                } else {
                    errorMessage = "ScreenCaptureKit error: \(error.localizedDescription)\n"
                    errorMessage! += "Error code: \(error.code) in domain: \(error.domain)\n"
                }
                semaphore.signal()
            }
        }

        // Wait for completion (with timeout)
        let result = semaphore.wait(timeout: .now() + 5)

        diagnostics += "  ScreenCaptureKit found \(windowCount) window(s) for PID \(pid)\n"

        if result == .timedOut {
            diagnostics += "  ScreenCaptureKit timed out after 5 seconds\n"
            return (nil, diagnostics)
        }

        if let error = errorMessage {
            diagnostics += "  \(error)\n"
            return (nil, diagnostics)
        }

        if let info = windowInfo {
            diagnostics += "  Capturing window: \(info)\n"
        }

        if let image = capturedImage {
            diagnostics += "  Capture completed successfully\n"
            return (image, diagnostics)
        }

        diagnostics += "  Failed to capture image (capturedImage is nil)\n"
        return (nil, diagnostics)
    }

    /// Perform OCR on a captured image
    private static func performOCR(on image: CGImage, filterMode: ContentFilter.FilterMode = .mainContent) -> String {
        var recognizedText = ""
        var allObservations: [VNRecognizedTextObservation] = []
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }

            guard error == nil else {
                print("OCR Error: \(error!.localizedDescription)")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            // Store observations for filtering
            allObservations = observations

            // Apply content filtering to observations
            let filteredObservations = ContentFilter.filterOCRObservations(observations, mode: filterMode)

            // Sort observations by vertical position (top to bottom, left to right)
            let sortedObservations = filteredObservations.sorted { obs1, obs2 in
                let bounds1 = obs1.boundingBox
                let bounds2 = obs2.boundingBox

                // Compare Y coordinates (inverted because Core Graphics coordinates)
                if abs(bounds1.origin.y - bounds2.origin.y) > 0.02 {
                    return bounds1.origin.y > bounds2.origin.y
                }

                // If on same line, compare X coordinates
                return bounds1.origin.x < bounds2.origin.x
            }

            // Extract text from observations
            var lastY: CGFloat = -1
            for observation in sortedObservations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }

                let currentY = observation.boundingBox.origin.y

                // Add line break if this is a new line
                if lastY != -1 && abs(currentY - lastY) > 0.02 {
                    recognizedText += "\n"
                }

                recognizedText += topCandidate.string + " "
                lastY = currentY
            }
        }

        // Configure the request for better accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Perform the request
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform OCR: \(error.localizedDescription)")
        }

        // Wait for completion (with timeout)
        _ = semaphore.wait(timeout: .now() + 30)

        return recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Recursively extract text from an accessibility element
    private static func extractTextFromElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> String {
        guard depth < maxDepth else { return "" }

        var result = ""

        // Try to get the value (text content)
        var value: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

        if valueResult == .success, let textValue = value as? String, !textValue.isEmpty {
            result += textValue + "\n"
        }

        // Try to get selected text
        var selectedText: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)

        if selectedResult == .success, let selected = selectedText as? String, !selected.isEmpty {
            result += "[Selected: \(selected)]\n"
        }

        // Try to get title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)

        if titleResult == .success, let titleValue = title as? String, !titleValue.isEmpty {
            result += titleValue + "\n"
        }

        // Try to get description
        var description: CFTypeRef?
        let descResult = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)

        if descResult == .success, let descValue = description as? String, !descValue.isEmpty {
            result += descValue + "\n"
        }

        // Get children and recursively extract text
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
            for child in childrenArray {
                result += extractTextFromElement(child, depth: depth + 1, maxDepth: maxDepth)
            }
        }

        return result
    }
}
