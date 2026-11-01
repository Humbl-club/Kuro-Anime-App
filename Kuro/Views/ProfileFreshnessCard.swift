import Foundation
import SwiftUI

// Streaming availability freshness (Profile > Advanced, only while `streaming_availability_v1` is on).
// A maintenance read-out, so it sits behind the Advanced disclosure and speaks plainly: what is set
// up, what this session has checked, and whether refreshes are waiting. Hairline group on white.

struct ProfileFreshnessCard: View {
    let snapshot: ProviderAvailabilityStore.StreamingObservabilitySnapshot?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    private var german: Bool { KuroLocale.isGerman }

    private var servicesSummary: String {
        guard let snapshot else { return german ? "Wird geladen …" : "Loading …" }
        return german
            ? "\(snapshot.configuredServiceCount) gewählt von \(snapshot.registryServiceCount)"
            : "\(snapshot.configuredServiceCount) chosen of \(snapshot.registryServiceCount)"
    }

    private var cacheSummary: String {
        guard let snapshot else { return german ? "Wird geladen …" : "Loading …" }
        return german
            ? "\(snapshot.cachedVerifiedTitleCount) bestätigt · \(snapshot.cachedCatalogTitleCount) Katalogtitel in dieser Sitzung"
            : "\(snapshot.cachedVerifiedTitleCount) confirmed · \(snapshot.cachedCatalogTitleCount) catalogue titles this session"
    }

    private var queueSummary: String {
        guard let snapshot else { return german ? "Wird geladen …" : "Loading …" }
        guard let queue = snapshot.queueSummary else {
            return german ? "Status nicht verfügbar" : "Status unavailable"
        }
        if queue.urgentPendingCount == 0 {
            return german ? "Nichts wartet" : "Nothing waiting"
        }
        let minutes = max(1, Int(ceil(Double(queue.oldestPendingRequestAgeSeconds) / 60.0)))
        return german
            ? "\(queue.urgentPendingCount) warten · älteste seit \(minutes) Min."
            : "\(queue.urgentPendingCount) waiting · oldest \(minutes) min"
    }

    private var statusCaption: String {
        guard let snapshot else { return german ? "Wird geladen …" : "Loading …" }
        if !snapshot.isStreamingAvailabilityEnabled {
            return german ? "Verfügbarkeit ist ausgeschaltet." : "Availability is off."
        }
        return german
            ? "Geöffnete Titel werden zuerst geprüft. Die Zahlen gelten nur für diese Sitzung."
            : "Titles you open are checked first. Counts cover this session only."
    }

    private func reasonLabel(for key: String) -> String {
        switch key {
        case "detail_open": return german ? "geöffnete Titel" : "opened titles"
        case "user_tap": return german ? "manuelle Prüfungen" : "manual checks"
        case "scheduled": return german ? "geplant" : "scheduled"
        // An unknown server key is internal vocabulary: never echoed (rulebook §9).
        default: return german ? "sonstige" : "other"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.sm) {
                Text(german ? "Streaming-Verfügbarkeit" : "Streaming availability")
                    .font(.kuroTitle())
                    .foregroundStyle(Color.kuroInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onRefresh) {
                    Text(isRefreshing ? (german ? "Läuft …" : "Refreshing …") : (german ? "Aktualisieren" : "Refresh"))
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .underline(!isRefreshing, color: Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
            }

            VStack(alignment: .leading, spacing: 0) {
                ProfileFreshnessMetricRow(label: german ? "Dienste" : "Services", value: servicesSummary)
                Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                ProfileFreshnessMetricRow(label: german ? "Geprüft" : "Checked", value: cacheSummary)
                Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                ProfileFreshnessMetricRow(label: german ? "Warteschlange" : "Waiting", value: queueSummary)
            }

            if let snapshot, let mix = snapshot.queueSummary?.requestReasonMix, !mix.isEmpty {
                Text(mix.sorted(by: { $0.key < $1.key }).map { "\(reasonLabel(for: $0.key)) \($0.value)" }.joined(separator: " · "))
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(statusCaption)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, KuroDesignSpacing.sm)
    }
}

private struct ProfileFreshnessMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
            Text(value)
                .font(.kuroMeta())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
