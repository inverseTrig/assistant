import SwiftUI

struct TextDisplayWindow: View {
    @Binding var isPresented: Bool
    let extractedText: String

    @State private var isPinned = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extracted Text")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Pin button
                Button(action: {
                    isPinned.toggle()
                }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin window" : "Pin window")

                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(extractedText, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Close button
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Text(extractedText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 600, height: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// Window controller to manage the display window
class TextDisplayWindowController {
    private var window: NSWindow?

    func show(text: String) {
        // Close existing window if any
        close()

        // Create SwiftUI view
        let contentView = TextDisplayWindowView(text: text, onClose: { [weak self] in
            self?.close()
        })

        // Create and configure window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Text Extraction"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        self.window = window

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

// SwiftUI view wrapper
private struct TextDisplayWindowView: View {
    let text: String
    let onClose: () -> Void

    @State private var isPinned = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Extracted Text")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Pin button
                Button(action: {
                    isPinned.toggle()
                    if let window = NSApp.keyWindow {
                        window.level = isPinned ? .floating : .normal
                    }
                }) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin window" : "Pin window")

                // Copy button
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}
