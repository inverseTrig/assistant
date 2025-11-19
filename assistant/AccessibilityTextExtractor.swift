import Foundation
import ApplicationServices
import AppKit
import Vision
import CoreGraphics

class AccessibilityTextExtractor {

    enum ExtractionMethod {
        case accessibility
        case ocr
        case hybrid
    }

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
    static func extractTextFromFocusedApp(method: ExtractionMethod = .hybrid) -> String {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost application found."
        }

        switch method {
        case .accessibility:
            return extractUsingAccessibility(app: frontmostApp)
        case .ocr:
            return extractUsingOCR(app: frontmostApp)
        case .hybrid:
            // Try accessibility first
            let accessibilityText = extractUsingAccessibility(app: frontmostApp, skipPermissionCheck: true)

            // If accessibility returns limited or no content, use OCR
            if accessibilityText.isEmpty || accessibilityText.contains("No text content found") || accessibilityText.count < 100 {
                return extractUsingOCR(app: frontmostApp)
            }

            return accessibilityText
        }
    }

    /// Extract text using Accessibility API
    private static func extractUsingAccessibility(app: NSRunningApplication, skipPermissionCheck: Bool = false) -> String {
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

        if extractedText.isEmpty {
            extractedText = "No text content found in the current view.\n\nApplication: \(app.localizedName ?? "Unknown")"
        } else {
            extractedText = "Text from: \(app.localizedName ?? "Unknown") [Accessibility API]\n\n" + extractedText
        }

        return extractedText
    }

    /// Extract text using OCR (screen capture + Vision framework)
    private static func extractUsingOCR(app: NSRunningApplication) -> String {
        // Check screen recording permissions (required for window capture on macOS 10.15+)
        guard checkScreenRecordingPermissions() else {
            requestScreenRecordingPermissions()
            return "Screen recording permissions required for OCR. Please grant access in System Settings > Privacy & Security > Screen Recording and restart the app."
        }

        // Capture the frontmost window
        guard let windowImage = captureFrontmostWindow(app: app) else {
            return "Failed to capture window for OCR.\n\nApplication: \(app.localizedName ?? "Unknown")"
        }

        // Perform OCR on the captured image
        let ocrText = performOCR(on: windowImage)

        if ocrText.isEmpty {
            return "No text detected via OCR.\n\nApplication: \(app.localizedName ?? "Unknown")"
        }

        return "Text from: \(app.localizedName ?? "Unknown") [OCR]\n\n" + ocrText
    }

    /// Check if screen recording permissions are granted
    private static func checkScreenRecordingPermissions() -> Bool {
        // On macOS 10.15+, we need screen recording permission to capture windows
        // We'll try to capture and see if it works
        if #available(macOS 10.15, *) {
            // Attempt a test capture to check permissions
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            return windowList != nil && !windowList!.isEmpty
        }
        return true
    }

    /// Request screen recording permissions
    private static func requestScreenRecordingPermissions() {
        // The system will automatically prompt when we try to capture
        // We can also direct the user to system settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Capture the frontmost window
    private static func captureFrontmostWindow(app: NSRunningApplication) -> CGImage? {
        let pid = app.processIdentifier

        // Get list of windows for the frontmost application
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]

        guard let windows = windowList else { return nil }

        // Find the frontmost window for this app
        var targetWindowID: CGWindowID?
        for window in windows {
            if let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
               windowPID == pid,
               let windowLayer = window[kCGWindowLayer as String] as? Int,
               windowLayer == 0 {
                if let windowID = window[kCGWindowNumber as String] as? CGWindowID {
                    targetWindowID = windowID
                    break
                }
            }
        }

        guard let windowID = targetWindowID else { return nil }

        // Capture the window
        let windowImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        )

        return windowImage
    }

    /// Perform OCR on a captured image
    private static func performOCR(on image: CGImage) -> String {
        var recognizedText = ""
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

            // Sort observations by vertical position (top to bottom, left to right)
            let sortedObservations = observations.sorted { obs1, obs2 in
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
