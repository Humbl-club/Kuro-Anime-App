import SwiftUI

// MARK: - Kuro Header (Shared)
struct KuroHeader: View {
    public let currentSection: String
    @Binding var showProfile: Bool

    init(currentSection: String, showProfile: Binding<Bool>) {
        self.currentSection = currentSection
        self._showProfile = showProfile
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("KURO")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.kuroTextTertiary)

                    Spacer()

                    Text(currentSection)
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.5)
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showProfile.toggle()
                    }) {
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("M")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.black)
                            )
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens settings")
                }
                .padding(.horizontal, max(geometry.size.width * 0.05, 16))
                .padding(.vertical, max(geometry.size.height * 0.2, 12))

                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 44)
        .padding(.top, 0)
    }
}

// MARK: - Page Dots (Shared)
struct PageDots: View {
    public let count: Int
    public let currentIndex: Int

    init(count: Int, currentIndex: Int) {
        self.count = count
        self.currentIndex = currentIndex
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(Color.black.opacity(index == currentIndex ? 1.0 : 0.2))
                    .frame(width: 6, height: 6)
                    .scaleEffect(index == currentIndex ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: currentIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .accessibilityHidden(true)
    }
}
