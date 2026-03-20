import Foundation
import SwiftUI

struct ProfileFreshnessCard: View {
    let snapshot: SupabaseService.StreamingObservabilitySnapshot?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var servicesSummary: String {
        guard let snapshot else { return "Loading..." }
        return "\(snapshot.configuredServiceCount) configured / \(snapshot.registryServiceCount) available"
    }

    private var cacheSummary: String {
        guard let snapshot else { return "Loading..." }
        return "\(snapshot.cachedVerifiedTitleCount) verified cached / \(snapshot.cachedCatalogTitleCount) provider rows"
    }

    private var queueSummary: String {
        guard let snapshot else { return "Loading..." }
        guard let queue = snapshot.queueSummary else { return "Queue status unavailable" }
        if queue.urgentPendingCount == 0 {
            return "No urgent refreshes waiting"
        }

        let minutes = max(1, Int(ceil(Double(queue.oldestPendingRequestAgeSeconds) / 60.0)))
        return "\(queue.urgentPendingCount) urgent pending · oldest \(minutes)m"
    }

    private var statusCaption: String {
        guard let snapshot else { return "Streaming freshness is syncing..." }
        if !snapshot.isStreamingAvailabilityEnabled {
            return "Streaming availability is off; freshness data is limited to local cache."
        }
        if snapshot.queueSummary?.urgentPendingCount ?? 0 > 0 {
            return "Recent detail opens and manual checks are prioritized first."
        }
        return "Freshness checks are up to date."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("FRESHNESS")
                    .font(.kuroMicro(weight: .medium))
                    .tracking(2.0)
                    .foregroundColor(.kuroBlack60)

                Spacer(minLength: 0)

                Button(action: onRefresh) {
                    HStack(spacing: 5) {
                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text(isRefreshing ? "REFRESHING" : "REFRESH")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(0.8)
                    }
                    .foregroundColor(.kuroBlack60)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.kuroBlack05)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            VStack(alignment: .leading, spacing: 10) {
                ProfileFreshnessMetricRow(
                    label: "Streaming services",
                    value: servicesSummary,
                    icon: "dot.radiowaves.left.and.right"
                )

                ProfileFreshnessMetricRow(
                    label: "Availability cache",
                    value: cacheSummary,
                    icon: "checkmark.seal"
                )

                ProfileFreshnessMetricRow(
                    label: "Refresh queue",
                    value: queueSummary,
                    icon: "clock.arrow.circlepath"
                )
            }

            if let snapshot, let mix = snapshot.queueSummary?.requestReasonMix, !mix.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(mix.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key) \(value)")
                            .font(.kuroMicro(weight: .medium))
                            .tracking(0.6)
                            .foregroundColor(.kuroBlack60)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.kuroBlack05)
                            )
                    }
                }
            }

            Text(statusCaption)
                .font(.kuroMicro(weight: .light))
                .foregroundColor(.kuroTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                .fill(Color.kuroSecondaryBackground.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: KuroRadius.lg, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}

private struct ProfileFreshnessMetricRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.kuroBlack60)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack60)
                Text(value)
                    .font(.kuroBody(weight: .light))
                    .foregroundColor(.kuroBlack80)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
