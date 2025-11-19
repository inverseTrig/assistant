# Text Extraction Assistant

A macOS application that allows you to extract text content from any application using a global hotkey and the Accessibility API.

## Features

- **Global Hotkey**: Press `⌘ + ⇧ + E` from any application to extract visible text
- **Accessibility API**: Uses macOS Accessibility API to extract text from focused windows
- **Floating Display Window**: Shows extracted text in a floating, resizable window
- **Copy to Clipboard**: Easily copy extracted text with one click
- **Pin Window**: Keep the extraction window on top of other windows

## Setup Instructions

### 1. Build and Run

Open the project in Xcode and build it:

```bash
open assistant.xcodeproj
```

### 2. Grant Accessibility Permissions

When you first run the application and try to use the text extraction feature, macOS will prompt you to grant Accessibility permissions.

You can also manually grant permissions:

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Click on **Accessibility**
4. Add the Assistant app and enable it

### 3. Disable App Sandbox (if needed)

The app has been configured to run without sandboxing to allow global hotkey registration and accessibility access. The entitlements file has been updated accordingly.

## How to Use

### Using the Global Hotkey

1. Run the Assistant app
2. Switch to any application you want to extract text from
3. Press `⌘ + ⇧ + E`
4. The extracted text will appear in a floating window

### Using the Test Button

1. Run the Assistant app
2. Click the **"Test Text Extraction"** button in the main window
3. The app will extract text from the currently focused window (which will be the Assistant app itself)

## Features of the Extraction Window

- **Scrollable View**: Browse through extracted text
- **Text Selection**: Select and copy specific portions of text
- **Pin Button**: Keep the window on top of all other windows
- **Copy Button**: Copy all extracted text to clipboard
- **Close Button**: Dismiss the extraction window

## Technical Details

### Components

1. **HotkeyManager.swift**: Manages global hotkey registration using Carbon framework
   - Hotkey: Command + Shift + E (⌘ + ⇧ + E)
   - Uses Carbon Event Manager for system-wide key monitoring

2. **AccessibilityTextExtractor.swift**: Extracts text using macOS Accessibility API
   - Recursively traverses UI element hierarchy
   - Extracts values, titles, descriptions, and selected text
   - Handles focused elements, windows, and main windows

3. **TextDisplayWindow.swift**: Displays extracted text in a floating window
   - Floating window with pin capability
   - Monospaced font for better readability
   - Text selection enabled
   - Copy to clipboard functionality

4. **Info.plist**: Contains privacy usage descriptions
   - NSAccessibilityUsageDescription
   - NSAppleEventsUsageDescription

5. **assistant.entitlements**: App capabilities
   - App Sandbox disabled for global hotkeys
   - Apple Events automation enabled

## Troubleshooting

### Hotkey Not Working

- Make sure Accessibility permissions are granted
- Check if another app is using the same hotkey combination
- Restart the application after granting permissions

### No Text Extracted

- Some applications may not expose their text through Accessibility API
- Try clicking on the text area in the target application first
- Some secure applications (like password managers) may block text extraction for security

### Permission Prompts

- The first time you use text extraction, macOS will ask for Accessibility permissions
- Grant the permission and restart the app if needed

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building)

## License

This is a demonstration project for text extraction using macOS Accessibility API.
