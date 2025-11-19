//
//  assistantApp.swift
//  assistant
//
//  Created by Ent on 11/18/25.
//

import SwiftUI
import SwiftData

@main
struct assistantApp: App {
    @StateObject private var hotkeyManager = HotkeyManager()
    private let textDisplayController = TextDisplayWindowController()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // Initialize hotkey manager
        let manager = HotkeyManager()
        _hotkeyManager = StateObject(wrappedValue: manager)

        // Set up hotkey callback
        manager.onHotkeyPressed = { [self] in
            self.handleHotkeyPressed()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleHotkeyPressed() {
        // Get the user's preferred extraction method
        let methodString = UserDefaults.standard.string(forKey: "extractionMethod") ?? "hybrid"
        let method: AccessibilityTextExtractor.ExtractionMethod
        switch methodString {
        case "accessibility":
            method = .accessibility
        case "ocr":
            method = .ocr
        default:
            method = .hybrid
        }

        // Get the user's preferred content focus (default to true)
        let focusMainContent = UserDefaults.standard.object(forKey: "focusMainContent") as? Bool ?? true
        let filterMode: ContentFilter.FilterMode = focusMainContent ? .mainContent : .allText

        // Extract text from the focused application
        let extractedText = AccessibilityTextExtractor.extractTextFromFocusedApp(method: method, filterMode: filterMode)

        // Display the extracted text
        textDisplayController.show(text: extractedText)
    }
}
