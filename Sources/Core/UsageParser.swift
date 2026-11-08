import Foundation

/// Extracts usage rows from the server-rendered OpenCode workspace page.
///
/// The page marks its data with `data-slot` attributes:
///
///     <div data-slot="usage-item" …>
///       <div data-slot="usage-label">Claude Sonnet 4.5</div>
///       <div data-slot="usage-value">$3.42</div>
///       <div data-slot="reset-time">Resets in 2 days</div>
///       <div data-slot="progress-bar" style="width: 42%" …>
///
/// This mirrors the previous cheerio-based Node scraper with no dependencies.
enum UsageParser {
    static func parse(_ html: String) -> [UsageItem] {
        let itemMarker = "data-slot=\"usage-item\""
        let markers = html.ranges(of: itemMarker)
        guard !markers.isEmpty else { return [] }

        var items: [UsageItem] = []
        for (index, marker) in markers.enumerated() {
            let segment = String(html[marker.lowerBound..<(index + 1 < markers.count
                ? markers[index + 1].lowerBound
                : html.endIndex)])
            if let item = parseItem(segment) {
                items.append(item)
            }
        }
        return items
    }

    private static func parseItem(_ segment: String) -> UsageItem? {
        guard let label = slotText(in: segment, slot: "usage-label"), !label.isEmpty,
              let percent = barPercent(in: segment)
        else { return nil }

        let reset = slotText(in: segment, slot: "reset-time") ?? ""
        return UsageItem(
            label: label,
            value: slotText(in: segment, slot: "usage-value") ?? "",
            percent: percent,
            reset: reset,
            resetShort: shortReset(reset))
    }

    /// Text of the `data-slot="<slot>"` element: all text nodes within that
    /// element (its true closing tag found by div balance), tags stripped.
    private static func slotText(in segment: String, slot: String) -> String? {
        guard let start = segment.range(of: "data-slot=\"\(slot)\"") else { return nil }
        // Skip the element's remaining attributes and the opening tag's `>`.
        var contentStart = start.upperBound
        if let tagEnd = segment[contentStart...].range(of: ">") {
            contentStart = tagEnd.upperBound
        }

        // Walk nested <div>/< /div> tags to find where this element closes.
        guard let tagRegex = try? NSRegularExpression(pattern: "<(/?)div\\b[^>]*>") else { return nil }
        var depth = 1
        var contentEnd = segment.endIndex
        for match in tagRegex.matches(in: segment, range: NSRange(segment.startIndex..., in: segment)) {
            guard let tagRange = Range(match.range, in: segment) else { continue }
            guard contentStart <= tagRange.lowerBound else { continue }
            let afterOpen = segment.index(after: tagRange.lowerBound)
            if segment[afterOpen] == "/" {
                depth -= 1
                if depth == 0 {
                    contentEnd = tagRange.lowerBound
                    break
                }
            } else {
                depth += 1
            }
        }

        let raw = String(segment[contentStart..<contentEnd])
        var text = raw
        if let innerTagRegex = try? NSRegularExpression(pattern: "<[^>]*>") {
            text = innerTagRegex.stringByReplacingMatches(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw),
                withTemplate: " ")
        }
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return decodeEntities(flattened).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Percent used, from the progress-bar inline `width: NN%` style.
    static func barPercent(in segment: String) -> Int? {
        guard let range = segment.range(of: "width:\\s*([0-9]+(?:\\.[0-9]+)?)%", options: .regularExpression)
        else { return nil }
        let number = segment[range].drop(while: { !$0.isNumber })
        guard let value = Double(String(number).split(separator: "%").first ?? "") else { return nil }
        return min(100, max(0, Int(value.rounded(.down))))
    }

    /// "Resets in 2 days" → "2d"; hours → "5h"; minutes → "3m"; other → "".
    static func shortReset(_ reset: String) -> String {
        if let days = firstInt(in: reset, pattern: "(\\d+)\\s*days?") { return "\(days)d" }
        if let hours = firstInt(in: reset, pattern: "(\\d+)\\s*hours?") { return "\(hours)h" }
        if let minutes = firstInt(in: reset, pattern: "(\\d+)\\s*minutes?") { return "\(minutes)m" }
        return ""
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[range].compactMap { $0.isNumber ? $0 : nil }
        guard let value = Int(String(digits)) else { return nil }
        return value
    }

    /// Minimal entity decoding for label text. Numeric and named entities first,
    /// then `&amp;` last so genuinely encoded markup is not double-decoded.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text

        // Numeric: &#NN; and &#xHH;
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);|&#x([0-9a-fA-F]+);") {
            let ns = result as NSString
            var replaced = ""
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                let matchRange = match.range
                if matchRange.location == NSNotFound { continue }
                replaced += ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                if matchRange.length > 0 {
                    // Only one of the two capture groups exists per match;
                    // absent groups report NSNotFound.
                    func groupText(_ index: Int) -> String {
                        let range = match.range(at: index)
                        guard range.location != NSNotFound, range.length > 0 else { return "" }
                        return ns.substring(with: range)
                    }
                    let group1 = groupText(1)
                    let group2 = groupText(2)
                    let scalar: UInt32?
                    if !group1.isEmpty {
                        scalar = UInt32(group1)
                    } else {
                        scalar = UInt32(group2, radix: 16)
                    }
                    replaced += scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
                }
                cursor = matchRange.location + matchRange.length
            }
            if cursor < ns.length {
                replaced += ns.substring(from: cursor)
            }
            result = replaced
        }

        for (entity, replacement) in [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&copy;", "©"), ("&reg;", "®"), ("&hellip;", "…"), ("&mdash;", "—"),
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
