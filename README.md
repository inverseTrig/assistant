# Text Extraction Assistant

A macOS application that allows you to extract text content from any application using a global hotkey and the Accessibility API.

## Features

- **Global Hotkey**: Press `⌘ + ⇧ + E` from any application to extract visible text
- **Multiple Extraction Methods**:
  - **Hybrid Mode (Default)**: Intelligently tries Accessibility API first, falls back to OCR for browsers and complex apps
  - **Accessibility API**: Fast extraction using native macOS Accessibility API
  - **OCR Mode**: Screen capture with optical character recognition for browsers and apps that don't expose text
- **Browser Support**: Works with Safari, Chrome, Firefox, and other browsers using OCR technology
- **Intelligent Content Filtering**: Automatically filters out navigation, ads, and UI elements to focus on main content
- **Floating Display Window**: Shows extracted text in a floating, resizable window
- **Copy to Clipboard**: Easily copy extracted text with one click
- **Pin Window**: Keep the extraction window on top of other windows

## Setup Instructions

### 1. Build and Run

Open the project in Xcode and build it:

```bash
open assistant.xcodeproj
```

### 2. Grant Required Permissions

The app requires different permissions depending on the extraction method you use:

#### Accessibility Permissions (Required for Accessibility API and Hybrid mode)

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Click on **Accessibility**
4. Add the Assistant app and enable it

The app will automatically prompt you when this permission is needed.

#### Screen Recording Permissions (Required for OCR and Hybrid mode)

1. Open **System Settings**
2. Go to **Privacy & Security**
3. Click on **Screen Recording**
4. Add the Assistant app and enable it

This permission is necessary for capturing window screenshots to perform OCR. The app will prompt you when this permission is needed.

### 3. Disable App Sandbox (if needed)

The app has been configured to run without sandboxing to allow global hotkey registration and accessibility access. The entitlements file has been updated accordingly.

## How to Use

### Choosing an Extraction Method

In the main app window, you can select from three extraction methods:

1. **Hybrid (Smart)** - Recommended for most users
   - Tries Accessibility API first (fast and accurate)
   - Automatically falls back to OCR if Accessibility API returns limited results
   - Best for general use across all applications including browsers

2. **Accessibility API** - Best for native apps
   - Fast and lightweight
   - Works great with native macOS apps and text editors
   - May not work well with browsers or complex UI

3. **OCR (Screen Capture)** - Best for browsers
   - Captures the screen and uses optical character recognition
   - Works with all browsers (Safari, Chrome, Firefox, etc.)
   - Slower but more universal

### Content Focus

Toggle **"Focus on main content"** to control what text is extracted:

- **Enabled (Default)**: Intelligently filters the extracted text to show only main content
  - Removes navigation bars, menus, and sidebars
  - Filters out ads and promotional content
  - Excludes UI elements (buttons, labels)
  - Focuses on the largest content block (articles, main text)
  - Perfect for reading articles, documentation, or web pages

- **Disabled**: Extracts all text without filtering
  - Gets every piece of text from the window
  - Useful when you need complete extraction
  - Good for debugging or specific use cases

The filtering works with all extraction methods and is especially effective for browsers and complex web pages.

### Using the Global Hotkey

1. Run the Assistant app
2. Select your preferred extraction method
3. Switch to any application you want to extract text from (e.g., Safari, Chrome, a text editor)
4. Press `⌘ + ⇧ + E`
5. The extracted text will appear in a floating window

### Using the Test Button

1. Run the Assistant app
2. Select your preferred extraction method
3. Click the **"Test Text Extraction"** button in the main window
4. The app will extract text from the currently focused window

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

2. **AccessibilityTextExtractor.swift**: Extracts text using multiple methods
   - **Accessibility API Mode**: Recursively traverses UI element hierarchy
     - Extracts values, titles, descriptions, and selected text
     - Handles focused elements, windows, and main windows
   - **OCR Mode**: Uses Vision framework for optical character recognition
     - Captures window screenshots using CGWindowListCreateImage
     - Performs text recognition with VNRecognizeTextRequest
     - Sorts detected text by position (top-to-bottom, left-to-right)
   - **Hybrid Mode**: Intelligently combines both approaches
     - Tries Accessibility API first for performance
     - Falls back to OCR if limited results detected

3. **ContentFilter.swift**: Intelligent content filtering system
   - **Text Filtering**: Removes common UI patterns, navigation, ads
     - Filters short lines, URLs, copyright notices
     - Removes social media buttons and common UI text
     - Extracts main content blocks
   - **OCR Observation Filtering**: Spatial filtering for OCR results
     - Calculates text density across the screen
     - Identifies main content region
     - Filters observations outside the main region
   - **Smart Patterns**: Uses regex to identify and filter UI elements
   - Works with both Accessibility API and OCR modes

4. **TextDisplayWindow.swift**: Displays extracted text in a floating window
   - Floating window with pin capability
   - Monospaced font for better readability
   - Text selection enabled
   - Copy to clipboard functionality

5. **Info.plist**: Contains privacy usage descriptions
   - NSAccessibilityUsageDescription (for Accessibility API)
   - NSAppleEventsUsageDescription (for Apple Events)
   - NSScreenCaptureUsageDescription (for OCR screen capture)

6. **assistant.entitlements**: App capabilities
   - App Sandbox disabled for global hotkeys
   - Apple Events automation enabled

## Troubleshooting

### Hotkey Not Working

- Make sure Accessibility permissions are granted
- Check if another app is using the same hotkey combination
- Restart the application after granting permissions

### No Text Extracted

- **For Accessibility API mode**: Some applications may not expose their text through Accessibility API
  - Try clicking on the text area in the target application first
  - Switch to OCR or Hybrid mode for better browser support
  - Some secure applications (like password managers) may block text extraction for security

- **For OCR mode**:
  - Ensure Screen Recording permission is granted
  - Make sure the window is visible and not minimized
  - OCR works best with clear, high-contrast text
  - Try using a larger window size for better OCR accuracy

- **For browsers**: Use OCR or Hybrid mode for best results

### Permission Prompts

- The first time you use text extraction, macOS will ask for Accessibility permissions
- Grant the permission and restart the app if needed

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building)

## License

This is a demonstration project for text extraction using macOS Accessibility API.
