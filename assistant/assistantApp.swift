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
        // Extract text from the focused application
        let extractedText = AccessibilityTextExtractor.extractTextFromFocusedApp()

        // Display the extracted text
        textDisplayController.show(text: extractedText)
    }
}
