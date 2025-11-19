import Foundation
import Vision

class ContentFilter {

    enum FilterMode {
        case allText        // Extract all text
        case mainContent    // Extract only main content
    }

    /// Filter extracted text to focus on main content
    static func filterText(_ text: String, mode: FilterMode) -> String {
        guard mode == .mainContent else {
            return text
        }

        let lines = text.components(separatedBy: .newlines)

        // Remove common UI elements and noise
        let filteredLines = lines.filter { line in
            !shouldFilterLine(line)
        }

        // Find the main content block
        let mainContent = extractMainContentBlock(from: filteredLines)

        return mainContent.joined(separator: "\n")
    }

    /// Filter OCR observations to focus on main content area
    static func filterOCRObservations(_ observations: [VNRecognizedTextObservation], mode: FilterMode) -> [VNRecognizedTextObservation] {
        guard mode == .mainContent else {
            return observations
        }

        // Step 1: Filter out UI elements and noise
        let contentObservations = observations.filter { observation in
            guard let text = observation.topCandidates(1).first?.string else { return false }
            return !shouldFilterLine(text)
        }

        if contentObservations.isEmpty {
            return observations
        }

        // Step 2: Find the main content region
        let mainRegion = findMainContentRegion(observations: contentObservations)

        // Step 3: Filter observations to those in the main region
        let filteredObservations = contentObservations.filter { observation in
            isInMainRegion(observation.boundingBox, mainRegion: mainRegion)
        }

        return filteredObservations.isEmpty ? observations : filteredObservations
    }

    /// Determine if a line should be filtered out
    private static func shouldFilterLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty lines
        if trimmed.isEmpty {
            return true
        }

        // Skip very short lines (likely UI elements)
        if trimmed.count < 3 {
            return true
        }

        // Common navigation and UI patterns
        let uiPatterns = [
            "^(Home|About|Contact|Menu|Login|Sign in|Sign up|Subscribe|Search)$",
            "^(Share|Tweet|Like|Follow|Comment)$",
            "^(Previous|Next|Back|Forward|Close|×)$",
            "^(Skip to|Jump to|Go to).*",
            "^\\d+\\s*(mins?|hours?|days?)\\s+ago$",
            "^©.*\\d{4}.*$",  // Copyright notices
            "^Cookie(s)?.*",
            "^Accept.*cookie.*",
            "^Privacy Policy.*",
            "^Terms.*Service.*",
            "^All Rights Reserved.*",
            "^Advertisement$",
            "^\\[Ad\\]$",
            "^Sponsored$",
            "^\\d+\\s+comment(s)?$",
            "^\\d+\\s+(view|like|share)(s)?$",
        ]

        for pattern in uiPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        // Filter out lines that are mostly URLs
        if isURL(trimmed) {
            return true
        }

        // Filter out lines with mostly special characters or numbers
        let alphaCount = trimmed.filter { $0.isLetter }.count
        let totalCount = trimmed.count
        if totalCount > 0 && Double(alphaCount) / Double(totalCount) < 0.4 {
            return true
        }

        return false
    }

    /// Check if text is a URL
    private static func isURL(_ text: String) -> Bool {
        let urlPattern = "^(https?://|www\\.|[a-zA-Z0-9-]+\\.(com|net|org|edu|gov|io|co)).*"
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        return false
    }

    /// Extract main content block from filtered lines
    private static func extractMainContentBlock(from lines: [String]) -> [String] {
        if lines.isEmpty {
            return lines
        }

        // Group consecutive lines into blocks
        var blocks: [[String]] = []
        var currentBlock: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                    currentBlock = []
                }
            } else {
                currentBlock.append(line)
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }

        // Find the largest block (likely main content)
        guard let mainBlock = blocks.max(by: { $0.count < $1.count }) else {
            return lines
        }

        // Only return the main block if it's significantly larger than others
        let totalLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if mainBlock.count >= max(5, totalLines / 3) {
            return mainBlock
        }

        return lines
    }

    /// Find the main content region from OCR observations
    private static func findMainContentRegion(observations: [VNRecognizedTextObservation]) -> CGRect {
        guard !observations.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        // Calculate text density in a grid
        let gridSize = 20
        var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)

        for observation in observations {
            let bounds = observation.boundingBox
            let centerX = Int((bounds.origin.x + bounds.width / 2) * CGFloat(gridSize))
            let centerY = Int((bounds.origin.y + bounds.height / 2) * CGFloat(gridSize))

            let x = min(max(centerX, 0), gridSize - 1)
            let y = min(max(centerY, 0), gridSize - 1)

            grid[y][x] += 1
        }

        // Find the region with highest text density
        var maxDensity = 0
        var maxRegion = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        // Use a sliding window to find dense regions
        let windowSize = gridSize / 2
        for y in 0...(gridSize - windowSize) {
            for x in 0...(gridSize - windowSize) {
                var density = 0
                for dy in 0..<windowSize {
                    for dx in 0..<windowSize {
                        density += grid[y + dy][x + dx]
                    }
                }

                if density > maxDensity {
                    maxDensity = density
                    let fx = CGFloat(x) / CGFloat(gridSize)
                    let fy = CGFloat(y) / CGFloat(gridSize)
                    let fw = CGFloat(windowSize) / CGFloat(gridSize)
                    let fh = CGFloat(windowSize) / CGFloat(gridSize)
                    maxRegion = CGRect(x: fx, y: fy, width: fw, height: fh)
                }
            }
        }

        // Expand the region slightly to avoid cutting off text
        return maxRegion.insetBy(dx: -0.1, dy: -0.1)
    }

    /// Check if a bounding box is in the main region
    private static func isInMainRegion(_ bounds: CGRect, mainRegion: CGRect) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return mainRegion.contains(center)
    }

    /// Calculate text quality score (higher = more likely to be main content)
    static func textQualityScore(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return 0.0
        }

        var score = 1.0

        // Longer text is better
        let length = Double(trimmed.count)
        score *= min(length / 50.0, 2.0)

        // More complete sentences are better
        let sentenceEndings = trimmed.filter { ".!?".contains($0) }.count
        score *= (1.0 + Double(sentenceEndings) * 0.2)

        // Proper capitalization is better
        let words = trimmed.components(separatedBy: .whitespaces)
        let capitalizedWords = words.filter { $0.first?.isUppercase == true }.count
        if !words.isEmpty {
            let capitalizationRatio = Double(capitalizedWords) / Double(words.count)
            if capitalizationRatio > 0.1 && capitalizationRatio < 0.8 {
                score *= 1.2
            }
        }

        // Penalize all-caps text (likely headers/navigation)
        let allCapsRatio = Double(trimmed.filter { $0.isUppercase }.count) / Double(trimmed.count)
        if allCapsRatio > 0.7 {
            score *= 0.3
        }

        return score
    }
}
