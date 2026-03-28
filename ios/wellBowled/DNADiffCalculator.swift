import Foundation

/// Computes per-parameter diffs between two BowlingDNA structs.
/// Returns rows sorted by diff magnitude (biggest first) for the compare view.
enum DNADiffCalculator {

    struct DiffRow: Identifiable {
        let id = UUID()
        let label: String
        let valueA: String
        let valueB: String
        let diffMagnitude: Double  // 0.0 = identical, 1.0 = max difference
    }

    /// Compare two DNAs and return sorted diff rows (biggest diff first).
    /// Only includes rows where both sides have values.
    static func diff(a: BowlingDNA, b: BowlingDNA) -> [DiffRow] {
        var rows: [DiffRow] = []

        // Phase 1: Run-Up
        appendCategorical(&rows, "Run-up stride", a.runUpStride, b.runUpStride)
        appendCategorical(&rows, "Run-up speed", a.runUpSpeed, b.runUpSpeed)
        appendCategorical(&rows, "Approach angle", a.approachAngle, b.approachAngle)

        // Phase 2: Gather
        appendCategorical(&rows, "Body alignment", a.gatherAlignment, b.gatherAlignment)
        appendCategorical(&rows, "Back-foot contact", a.backFootContact, b.backFootContact)
        appendCategorical(&rows, "Trunk lean", a.trunkLean, b.trunkLean)

        // Phase 3: Delivery Stride
        appendCategorical(&rows, "Stride length", a.deliveryStrideLength, b.deliveryStrideLength)
        appendCategorical(&rows, "Front arm", a.frontArmAction, b.frontArmAction)
        appendCategorical(&rows, "Head stability", a.headStability, b.headStability)

        // Phase 4: Release
        appendCategorical(&rows, "Arm path", a.armPath, b.armPath)
        appendCategorical(&rows, "Release height", a.releaseHeight, b.releaseHeight)
        appendCategorical(&rows, "Wrist position", a.wristPosition, b.wristPosition)
        appendContinuous(&rows, "Wrist angular velocity", a.wristOmegaNormalized, b.wristOmegaNormalized)
        appendContinuous(&rows, "Release wrist Y", a.releaseWristYNormalized, b.releaseWristYNormalized)

        // Phase 5: Seam/Spin
        appendCategorical(&rows, "Seam orientation", a.seamOrientation, b.seamOrientation)
        appendCategorical(&rows, "Revolutions", a.revolutions, b.revolutions)

        // Phase 6: Follow-Through
        appendCategorical(&rows, "Follow-through", a.followThroughDirection, b.followThroughDirection)
        appendCategorical(&rows, "Balance", a.balanceAtFinish, b.balanceAtFinish)

        // Quality scores
        appendContinuous(&rows, "Run-up quality", a.runUpQuality, b.runUpQuality)
        appendContinuous(&rows, "Gather quality", a.gatherQuality, b.gatherQuality)
        appendContinuous(&rows, "Delivery stride quality", a.deliveryStrideQuality, b.deliveryStrideQuality)
        appendContinuous(&rows, "Release quality", a.releaseQuality, b.releaseQuality)
        appendContinuous(&rows, "Follow-through quality", a.followThroughQuality, b.followThroughQuality)

        // Sort: biggest diff first, same-diff rows alphabetical
        rows.sort { lhs, rhs in
            if abs(lhs.diffMagnitude - rhs.diffMagnitude) > 0.001 {
                return lhs.diffMagnitude > rhs.diffMagnitude
            }
            return lhs.label < rhs.label
        }

        return rows
    }

    // MARK: - Helpers

    /// 3-value categorical: ordinal 0.0, 0.5, 1.0
    private static func appendCategorical<T: CaseIterable & Equatable & RawRepresentable>(
        _ rows: inout [DiffRow],
        _ label: String,
        _ valA: T?,
        _ valB: T?
    ) where T.RawValue == String {
        guard let a = valA, let b = valB else { return }
        let ordA = ordinal(a)
        let ordB = ordinal(b)
        rows.append(DiffRow(
            label: label,
            valueA: displayName(a.rawValue),
            valueB: displayName(b.rawValue),
            diffMagnitude: abs(ordA - ordB)
        ))
    }

    /// Continuous 0-1 value
    private static func appendContinuous(
        _ rows: inout [DiffRow],
        _ label: String,
        _ valA: Double?,
        _ valB: Double?
    ) {
        guard let a = valA, let b = valB else { return }
        rows.append(DiffRow(
            label: label,
            valueA: String(format: "%.0f%%", a * 100),
            valueB: String(format: "%.0f%%", b * 100),
            diffMagnitude: abs(a - b)
        ))
    }

    /// Generic ordinal encoding: maps enum case index to [0, 1] range.
    private static func ordinal<T: CaseIterable & Equatable>(_ value: T) -> Double {
        let all = Array(T.allCases)
        guard let idx = all.firstIndex(of: value) else { return 0 }
        let position = all.distance(from: all.startIndex, to: idx)
        guard all.count > 1 else { return 0.5 }
        return Double(position) / Double(all.count - 1)
    }

    /// "front_on" → "Front On", "round_arm" → "Round Arm"
    private static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
