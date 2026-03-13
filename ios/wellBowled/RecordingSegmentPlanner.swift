import Foundation

/// Pure planning helpers for post-session recording segment handling.
enum RecordingSegmentPlanner {
    static func existingSegments(
        _ urls: [URL],
        fileExists: (URL) -> Bool
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls where fileExists(url) {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    static func resolvedRecordingURL(
        mergedURL: URL?,
        segments: [URL],
        fallback: URL?
    ) -> URL? {
        if let mergedURL { return mergedURL }
        return segments.last ?? fallback
    }
}

