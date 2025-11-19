import Foundation
import ApplicationServices
import AppKit

class AccessibilityTextExtractor {

    /// Check if accessibility permissions are granted
    static func checkAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Request accessibility permissions
    static func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Extract text from the currently focused application
    static func extractTextFromFocusedApp() -> String {
        guard checkAccessibilityPermissions() else {
            requestAccessibilityPermissions()
            return "Accessibility permissions required. Please grant access in System Settings > Privacy & Security > Accessibility."
        }

        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return "No frontmost application found."
        }

        let pid = frontmostApp.processIdentifier
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
            extractedText = "No text content found in the current view.\n\nApplication: \(frontmostApp.localizedName ?? "Unknown")"
        } else {
            extractedText = "Text from: \(frontmostApp.localizedName ?? "Unknown")\n\n" + extractedText
        }

        return extractedText
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
