import SwiftUI

// MARK: - Discover states (Discover + Clubs redesign §6.4; Home grammar G§11)
// Loading draws the issue's own shape in `KuroSkeleton`'s translucent ink (.08, the material foot .13),
// so it stays visible on both Discover canvases: an opening-row bar, three switch words, the four mood
// keys (56), the cover story's art (159 at 350) and foot (58), three contents rows, two index rows,
// then the scrub line.
// Offline with earlier content: a quiet band at the top of the content (8 pt radius, white @ .5, 1 pt
// `HomeInk.quietBorder`, 11 pt): "**You're offline.** Showing the last issue you loaded." and an
// ink-rule "Try again →" that keeps the band's retry.

struct DiscoverIssueSkeleton: View {
    let column: CGFloat

    private var block: Color { Color.kuroInk.opacity(KuroSkeleton.blockInkOpacity) }
    private var deepBlock: Color { Color.kuroInk.opacity(KuroSkeleton.deepBlockInkOpacity) }

    var body: some View {
        let compact = DiscoverIssueLayout.isCompact(column: column)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                bar(width: 120, height: 8)
                Spacer(minLength: 8)
                bar(width: 96, height: 12)
            }
            .frame(minHeight: 18)
            HStack(alignment: .bottom) {
                bar(width: compact ? 44 : 52, height: compact ? 20 : 24)
                Spacer(minLength: 8)
                bar(width: compact ? 74 : 90, height: compact ? 20 : 24)
                Spacer(minLength: 8)
                bar(width: compact ? 74 : 90, height: compact ? 20 : 24)
            }
            .frame(minHeight: DiscoverIssueLayout.switchMinHeight, alignment: .bottom)
            .padding(.bottom, 4)
            .padding(.top, DiscoverIssueLayout.openingToSwitch)
            // The four mood keys (2 × 2, 56 pt; usability spec §7).
            VStack(spacing: DiscoverMoodKeys.gap) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: DiscoverMoodKeys.gap) {
                        RoundedRectangle(cornerRadius: 10).fill(block).frame(height: DiscoverMoodKeys.keyHeight)
                        RoundedRectangle(cornerRadius: 10).fill(block).frame(height: DiscoverMoodKeys.keyHeight)
                    }
                }
            }
            .padding(.top, DiscoverIssueLayout.moods)
            VStack(spacing: 0) {
                Rectangle().fill(block)
                    .frame(height: DiscoverIssueLayout.artHeight(column: column, aspect: DiscoverIssueLayout.coverBannerAspect))
                HStack(spacing: KuroDesignSpacing.sm) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.18)).frame(height: 12)
                    Spacer(minLength: 64)
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.18)).frame(width: 96, height: 34)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 58)
                .background(deepBlock)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.top, DiscoverIssueLayout.openingStack)
            // The contents block: three jump rows.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 8) {
                        bar(width: 14, height: 8)
                        bar(width: 120, height: 10)
                        Spacer(minLength: 0)
                        bar(width: 18, height: 8)
                    }
                    .frame(height: DiscoverIssueLayout.contentsRow)
                }
            }
            .padding(.top, DiscoverIssueLayout.openingStack)
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 12) {
                        bar(width: 18, height: 10)
                        RoundedRectangle(cornerRadius: 2).fill(block).frame(width: 40, height: 60)
                        VStack(alignment: .leading, spacing: 8) {
                            bar(width: nil, height: 12)
                            bar(width: 72, height: 9)
                        }
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 10).fill(deepBlock).frame(width: 84, height: 34)
                    }
                    .frame(minHeight: DiscoverIssueLayout.indexRowMinHeight)
                }
            }
            .padding(.top, DiscoverIssueLayout.firstSection)
            KuroScrubLine()
                .frame(maxWidth: 96)
                .padding(.top, KuroDesignSpacing.md)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
    }

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(block)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// The quiet offline band over earlier content.
struct DiscoverOfflineBand: View {
    let retry: () -> Void

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(Text(DiscoverIssueCopy.offlineLead(german: german)).fontWeight(.semibold)) \(DiscoverIssueCopy.offlineRest(german: german))")
                .font(.kuroCustom(11, relativeTo: .footnote, maxSize: 24))
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                KuroAccessibility.impactHaptic(.light)
                retry()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(DiscoverIssueCopy.retry(german: german))
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.kuroCustom(11, weight: .medium, relativeTo: .footnote, maxSize: 24))
                    .foregroundStyle(Color.kuroInk)
                    .lineLimit(1)
                    .fixedSize()
                    Rectangle().fill(Color.kuroInk).frame(height: 1)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(DiscoverIssueCopy.retry(german: german))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HomeInk.quietBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// The cover story's place while today's pick resolves: the art window and the material foot.
struct DiscoverStorySkeleton: View {
    let column: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.kuroInk.opacity(KuroSkeleton.blockInkOpacity))
                .frame(height: DiscoverIssueLayout.artHeight(column: column, aspect: DiscoverIssueLayout.coverBannerAspect))
            Rectangle().fill(Color.kuroInk.opacity(KuroSkeleton.deepBlockInkOpacity))
                .frame(height: 58)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(KuroBrandedCopy.loadingLabel(german: KuroLocale.isGerman))
    }
}
