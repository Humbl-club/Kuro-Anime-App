import SwiftUI

/// A small "load more" trigger that avoids repeated `.onAppear` spam when the user
/// bounces near the bottom of a list/grid.
///
/// It triggers at most once per `itemCount` value.
struct KuroLoadMoreSentinel: View {
    let itemCount: Int
    let hasMore: Bool
    let isLoading: Bool
    let tint: Color
    let action: () async -> Void

    @State private var lastTriggeredCount: Int = -1

    init(
        itemCount: Int,
        hasMore: Bool,
        isLoading: Bool,
        tint: Color = .black.opacity(0.6),
        action: @escaping () async -> Void
    ) {
        self.itemCount = itemCount
        self.hasMore = hasMore
        self.isLoading = isLoading
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Group {
            if hasMore {
                ProgressView()
                    .tint(tint)
                    .padding(.vertical, 18)
            }
        }
        .onAppear {
            guard hasMore, !isLoading else { return }
            // Trigger only once per itemCount; when new items arrive, itemCount changes and we can trigger again.
            guard itemCount != lastTriggeredCount else { return }
            lastTriggeredCount = itemCount
            Task { await action() }
        }
        .onChange(of: itemCount) { _, _ in
            // Allow triggering again after new items append.
            // (No-op; `onAppear` will fire when the sentinel re-enters the viewport.)
        }
    }
}

