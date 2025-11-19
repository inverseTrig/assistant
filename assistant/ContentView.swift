//
//  ContentView.swift
//  assistant
//
//  Created by Ent on 11/18/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var textDisplayController = TextDisplayWindowController()
    @AppStorage("extractionMethod") private var extractionMethod: String = "hybrid"
    @AppStorage("focusMainContent") private var focusMainContent: Bool = true

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            VStack(spacing: 20) {
                Text("Text Extraction Assistant")
                    .font(.title)
                    .fontWeight(.bold)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Hotkey Feature")
                        .font(.headline)

                    HStack(spacing: 5) {
                        Text("Press")
                        KeySymbol(text: "⌘")
                        Text("+")
                        KeySymbol(text: "⇧")
                        Text("+")
                        KeySymbol(text: "E")
                        Text("to extract text from any application")
                    }

                    Text("The hotkey works globally across all applications. It will extract visible text content from the currently focused window using the macOS Accessibility API.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)

                    Text("Note: You may need to grant Accessibility permissions in System Settings > Privacy & Security > Accessibility")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.top, 5)

                    Divider()
                        .padding(.vertical, 5)

                    Text("Extraction Method")
                        .font(.headline)

                    Picker("Method", selection: $extractionMethod) {
                        Text("Hybrid (Smart)").tag("hybrid")
                        Text("Accessibility API").tag("accessibility")
                        Text("OCR (Screen Capture)").tag("ocr")
                    }
                    .pickerStyle(.segmented)

                    Text(extractionMethodDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)

                    if extractionMethod == "ocr" || extractionMethod == "hybrid" {
                        Text("Note: Screen Recording permission is required for OCR. Grant access in System Settings > Privacy & Security > Screen Recording")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 5)
                    }

                    Divider()
                        .padding(.vertical, 5)

                    Text("Content Focus")
                        .font(.headline)

                    Toggle(isOn: $focusMainContent) {
                        Text("Focus on main content")
                    }
                    .toggleStyle(.switch)

                    Text(focusMainContent ? "Filters out navigation, ads, and UI elements to show only the main content." : "Extracts all text from the page without filtering.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)

                    Button(action: testTextExtraction) {
                        Label("Test Text Extraction", systemImage: "text.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 10)
                }
                .frame(maxWidth: 400)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)

                Spacer()
            }
            .padding()
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }

    private var extractionMethodDescription: String {
        switch extractionMethod {
        case "hybrid":
            return "Tries Accessibility API first, falls back to OCR for browsers and complex apps. Best for general use."
        case "accessibility":
            return "Fast, uses native Accessibility API. Works best with native macOS apps and text editors."
        case "ocr":
            return "Uses screen capture and optical character recognition. Best for browsers and apps that don't expose text via Accessibility API."
        default:
            return ""
        }
    }

    private func testTextExtraction() {
        let method: AccessibilityTextExtractor.ExtractionMethod
        switch extractionMethod {
        case "accessibility":
            method = .accessibility
        case "ocr":
            method = .ocr
        default:
            method = .hybrid
        }

        let filterMode: ContentFilter.FilterMode = focusMainContent ? .mainContent : .allText
        let extractedText = AccessibilityTextExtractor.extractTextFromFocusedApp(method: method, filterMode: filterMode)
        textDisplayController.show(text: extractedText)
    }
}

// Helper view for displaying keyboard symbols
struct KeySymbol: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(5)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
