import Foundation

/// Source of a release timestamp candidate.
enum DeliveryTimestampSource: String, Equatable {
    case live
    case gemini
    case hybrid
}

/// Release timestamp candidate in recording-relative seconds.
struct DeliveryTimestampCandidate: Equatable {
    let timestamp: Double
    let confidence: Double
    let source: DeliveryTimestampSource

    var clampedConfidence: Double {
        min(max(confidence, 0), 1)
    }
}

/// Rolling window descriptor for chunked detection.
struct DeliverySegmentWindow: Equatable {
    let index: Int
    let start: Double
    let end: Double

    var duration: Double {
        max(end - start, 0)
    }
}

enum DeliveryBatchPlanner {

    static func scheduleSegments(
        totalDuration: Double,
        segmentDuration: Double,
        segmentOverlap: Double
    ) -> [DeliverySegmentWindow] {
        let safeTotal = max(totalDuration, 0)
        guard safeTotal > 0 else { return [] }

        let safeSegmentDuration = max(segmentDuration, 1)
        let maxAllowedOverlap = max(safeSegmentDuration - 0.1, 0)
        let safeOverlap = min(max(segmentOverlap, 0), maxAllowedOverlap)
        let stride = max(safeSegmentDuration - safeOverlap, 0.1)

        var windows: [DeliverySegmentWindow] = []
        var start = 0.0
        var index = 0

        while start < safeTotal {
            let end = min(start + safeSegmentDuration, safeTotal)
            windows.append(DeliverySegmentWindow(index: index, start: start, end: end))
            if end >= safeTotal { break }
            start += stride
            index += 1
        }

        return windows
    }

    static func mergeCandidates(
        candidates: [DeliveryTimestampCandidate],
        dedupeWindow: Double,
        sessionDuration: Double?
    ) -> [DeliveryTimestampCandidate] {
        guard !candidates.isEmpty else { return [] }

        let safeWindow = max(dedupeWindow, 0)
        let maxDuration = sessionDuration.map { max($0, 0) }

        let normalized = candidates.map { candidate in
            let boundedTimestamp: Double
            if let maxDuration {
                boundedTimestamp = min(max(candidate.timestamp, 0), maxDuration)
            } else {
                boundedTimestamp = max(candidate.timestamp, 0)
            }
            return DeliveryTimestampCandidate(
                timestamp: boundedTimestamp,
                confidence: candidate.clampedConfidence,
                source: candidate.source
            )
        }
        .sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.confidence > rhs.confidence
        }

        var merged: [DeliveryTimestampCandidate] = []
        var current = normalized[0]

        for candidate in normalized.dropFirst() {
            if abs(candidate.timestamp - current.timestamp) <= safeWindow {
                current = mergePair(current, candidate)
            } else {
                merged.append(current)
                current = candidate
            }
        }

        merged.append(current)
        return merged
    }

    private static func mergePair(
        _ left: DeliveryTimestampCandidate,
        _ right: DeliveryTimestampCandidate
    ) -> DeliveryTimestampCandidate {
        let winner: DeliveryTimestampCandidate
        if left.confidence > right.confidence {
            winner = left
        } else if right.confidence > left.confidence {
            winner = right
        } else {
            winner = left.timestamp <= right.timestamp ? left : right
        }

        let mergedSource: DeliveryTimestampSource = left.source == right.source ? winner.source : .hybrid
        let baseConfidence = max(left.confidence, right.confidence)
        let mergedConfidence = mergedSource == .hybrid
            ? min(baseConfidence + WBConfig.hybridDetectionConfidenceBoost, 1)
            : baseConfidence

        return DeliveryTimestampCandidate(
            timestamp: winner.timestamp,
            confidence: mergedConfidence,
            source: mergedSource
        )
    }
}
