// Countdown Timer Component
// Shows time until next episode airs
// Only for currently airing anime in user's collection

import SwiftUI

struct NextEpisodeCountdown: View {
    let nextAiringAt: Date?
    let nextEpisodeNumber: Int?
    @State private var timeRemaining: String = ""
    @State private var timer: Timer?

    var body: some View {
        if let airingDate = nextAiringAt,
           let episode = nextEpisodeNumber,
           airingDate > Date() {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.black.opacity(0.6))

                Text("EP \(episode) IN \(timeRemaining)")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.7))
            }
            .onAppear {
                updateCountdown()
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateCountdown()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCountdown() {
        guard let airingDate = nextAiringAt else { return }

        let now = Date()
        let interval = airingDate.timeIntervalSince(now)

        if interval <= 0 {
            timeRemaining = "NOW"
            stopTimer()
            return
        }

        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            timeRemaining = "\(days)D \(hours)H"
        } else if hours > 0 {
            timeRemaining = "\(hours)H \(minutes)M"
        } else {
            timeRemaining = "\(minutes)M"
        }
    }
}

// Helper to check if anime should show countdown
extension Anime {
    var shouldShowCountdown: Bool {
        guard let nextAiring = nextAiringAt else { return false }
        return nextAiring > Date() && status == "RELEASING"
    }
}
