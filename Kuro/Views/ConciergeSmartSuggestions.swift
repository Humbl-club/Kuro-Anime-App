#if DEBUG
// ConciergeSmartSuggestions.swift
// Kuro
//
// Smart suggestion bar for Concierge input field with context-aware completions
// and filters that adapt based on user input patterns.
//

import SwiftUI

// MARK: - Suggestion Model

/// Represents a single suggestion item
struct Suggestion: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let text: String
    let completion: String
    let color: Color
    let category: SuggestionCategory
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SuggestionCategory: String, CaseIterable {
    case genre = "Genre"
    case format = "Format"
    case length = "Length"
    case time = "Time"
    case importAction = "Import"
}

// MARK: - Suggestion Generator

/// Generates context-aware suggestions based on user input
final class SuggestionGenerator {
    
    // MARK: - Genre Patterns
    
    private let genrePatterns: [String: [(icon: String, text: String, completion: String, color: Color)]] = [
        "funny": [
            ("😄", "Comedy", "comedy", .orange),
            ("😂", "Parody", "parody", .yellow),
            ("🎭", "Slice of Life", "slice of life", .pink)
        ],
        "laugh": [
            ("😄", "Comedy", "comedy", .orange),
            ("😂", "Parody", "parody", .yellow),
            ("🎭", "Slice of Life", "slice of life", .pink)
        ],
        "comedy": [
            ("😄", "Comedy", "comedy", .orange),
            ("😂", "Parody", "parody", .yellow),
            ("🎪", "Gag", "gag", .yellow)
        ],
        "action": [
            ("⚔️", "Action", "action", .red),
            ("🥋", "Martial Arts", "martial arts", .orange),
            ("🔫", "Military", "military", .green)
        ],
        "fight": [
            ("⚔️", "Action", "action", .red),
            ("🥋", "Martial Arts", "martial arts", .orange),
            ("👊", "Shounen", "shounen", .blue)
        ],
        "battle": [
            ("⚔️", "Action", "action", .red),
            ("🥋", "Martial Arts", "martial arts", .orange),
            ("⚡", "Super Power", "super power", .purple)
        ],
        "sad": [
            ("😢", "Drama", "drama", .indigo),
            ("💔", "Tragedy", "tragedy", .purple),
            ("🌸", "Slice of Life", "slice of life", .pink)
        ],
        "cry": [
            ("😢", "Drama", "drama", .indigo),
            ("💔", "Tragedy", "tragedy", .purple),
            ("🎭", "Psychological", "psychological", .teal)
        ],
        "depress": [
            ("😢", "Drama", "drama", .indigo),
            ("💔", "Tragedy", "tragedy", .purple),
            ("🌧️", "Dark", "dark", .gray)
        ],
        "scary": [
            ("👻", "Horror", "horror", .purple),
            ("🔮", "Supernatural", "supernatural", .indigo),
            ("🧟", "Thriller", "thriller", .red)
        ],
        "horror": [
            ("👻", "Horror", "horror", .purple),
            ("🔮", "Supernatural", "supernatural", .indigo),
            ("🩸", "Gore", "gore", .red)
        ],
        "scare": [
            ("👻", "Horror", "horror", .purple),
            ("🔮", "Supernatural", "supernatural", .indigo),
            ("🧟", "Thriller", "thriller", .red)
        ],
        "love": [
            ("💕", "Romance", "romance", .pink),
            ("💘", "Harem", "harem", .red),
            ("🌸", "Shoujo", "shoujo", .pink)
        ],
        "romance": [
            ("💕", "Romance", "romance", .pink),
            ("💘", "Harem", "harem", .red),
            ("💝", "Love Polygon", "love polygon", .pink)
        ],
        "think": [
            ("🧠", "Psychological", "psychological", .teal),
            ("🧩", "Mystery", "mystery", .indigo),
            ("🎭", "Thriller", "thriller", .red)
        ],
        "smart": [
            ("🧠", "Psychological", "psychological", .teal),
            ("🧩", "Mystery", "mystery", .indigo),
            ("📚", "School", "school", .blue)
        ],
        "future": [
            ("🤖", "Sci-Fi", "sci-fi", .cyan),
            ("🚀", "Space", "space", .blue),
            ("⚙️", "Mecha", "mecha", .gray)
        ],
        "robot": [
            ("🤖", "Sci-Fi", "sci-fi", .cyan),
            ("⚙️", "Mecha", "mecha", .gray),
            ("🔬", "Tech", "technology", .cyan)
        ],
        "magic": [
            ("🪄", "Fantasy", "fantasy", .purple),
            ("✨", "Supernatural", "supernatural", .indigo),
            ("🧙", "Magic", "magic", .blue)
        ],
        "fantasy": [
            ("🪄", "Fantasy", "fantasy", .purple),
            ("🐉", "Adventure", "adventure", .green),
            ("🏰", "Isekai", "isekai", .indigo)
        ],
        "sport": [
            ("⚽", "Sports", "sports", .green),
            ("🏀", "Team", "team sports", .orange),
            ("🏆", "Competitive", "competitive", .yellow)
        ]
    ]
    
    // MARK: - Format Suggestions
    
    private let formatSuggestions: [(icon: String, text: String, completion: String, color: Color)] = [
        ("🎬", "Movie", "movie", .purple),
        ("📺", "TV Series", "tv series", .blue),
        ("📖", "OVA", "ova", .orange),
        ("🎵", "Music", "music", .pink),
        ("🎪", "Special", "special", .green)
    ]
    
    // MARK: - Length Suggestions
    
    private let lengthSuggestions: [(icon: String, text: String, completion: String, color: Color)] = [
        ("⏱️", "Short (<12)", "short series", .cyan),
        ("📏", "Medium (12-24)", "medium series", .blue),
        ("🎬", "Long (25+)", "long series", .indigo)
    ]
    
    // MARK: - Time-Aware Suggestions
    
    private func getTimeAwareSuggestions() -> [(icon: String, text: String, completion: String, color: Color)] {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12: // Morning
            return [
                ("☀️", "Light-hearted", "light-hearted", .orange),
                ("😄", "Comedy", "comedy", .yellow),
                ("🎭", "Slice of Life", "slice of life", .pink)
            ]
        case 12..<17: // Afternoon
            return [
                ("🎯", "Action-packed", "action", .red),
                ("⚔️", "Adventure", "adventure", .green),
                ("🎪", "Shounen", "shounen", .orange)
            ]
        case 17..<22: // Evening
            return [
                ("🌆", "Any mood", "", .indigo),
                ("🎬", "Binge-worthy", "binge-worthy", .purple),
                ("💕", "Romance", "romance", .pink)
            ]
        default: // Night (22-5)
            return [
                ("🌙", "Relaxing", "relaxing", .indigo),
                ("🌃", "Binge-worthy", "binge-worthy", .purple),
                ("😢", "Emotional", "emotional", .blue)
            ]
        }
    }
    
    // MARK: - Import Detection
    
    private func detectImportSuggestions(from text: String) -> [(icon: String, text: String, completion: String, color: Color)]? {
        // Detect comma-separated titles or newline-separated
        let delimiterPattern = "[,\\n]+"
        let components = text.components(separatedBy: .init(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }
        
        guard components.count >= 2 else { return nil }
        
        return [
            ("📋", "\(components.count) titles", "confirm titles", .blue),
            ("✏️", "Edit list", "edit list", .orange),
            ("📊", "Preview", "preview", .green),
            ("🔄", "Re-parse", "re-parse", .purple)
        ]
    }
    
    // MARK: - Public API
    
    func generateSuggestions(for text: String) -> [Suggestion] {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var suggestions: [Suggestion] = []
        var usedCompletions = Set<String>()
        
        // Check for import pattern first (highest priority)
        if let importSuggestions = detectImportSuggestions(from: text) {
            for item in importSuggestions {
                suggestions.append(Suggestion(
                    icon: item.icon,
                    text: item.text,
                    completion: item.completion,
                    color: item.color,
                    category: .importAction
                ))
            }
            return suggestions
        }
        
        // Match genre patterns
        for (keyword, matches) in genrePatterns {
            if lowercased.contains(keyword) {
                for item in matches {
                    let completion = item.completion.lowercased()
                    if !usedCompletions.contains(completion) {
                        usedCompletions.insert(completion)
                        suggestions.append(Suggestion(
                            icon: item.icon,
                            text: item.text,
                            completion: item.completion,
                            color: item.color,
                            category: .genre
                        ))
                    }
                }
            }
        }
        
        // Add format suggestions if no format mentioned
        let formatKeywords = ["movie", "tv series", "ova", "special", "music"]
        let hasFormat = formatKeywords.contains { lowercased.contains($0) }
        
        if !hasFormat && suggestions.count < 4 {
            for item in formatSuggestions {
                let completion = item.completion.lowercased()
                if !usedCompletions.contains(completion) {
                    usedCompletions.insert(completion)
                    suggestions.append(Suggestion(
                        icon: item.icon,
                        text: item.text,
                        completion: item.completion,
                        color: item.color,
                        category: .format
                    ))
                }
            }
        }
        
        // Add length suggestions if no length mentioned and space available
        let lengthKeywords = ["short", "medium", "long", "episode"]
        let hasLength = lengthKeywords.contains { lowercased.contains($0) }
        
        if !hasLength && suggestions.count < 4 {
            for item in lengthSuggestions.prefix(2) {
                let completion = item.completion.lowercased()
                if !usedCompletions.contains(completion) {
                    usedCompletions.insert(completion)
                    suggestions.append(Suggestion(
                        icon: item.icon,
                        text: item.text,
                        completion: item.completion,
                        color: item.color,
                        category: .length
                    ))
                }
            }
        }
        
        // If still few suggestions, add time-aware ones
        if suggestions.isEmpty || (suggestions.count < 3 && text.count < 20) {
            let timeSuggestions = getTimeAwareSuggestions()
            for item in timeSuggestions.prefix(2) {
                let completion = item.completion.lowercased()
                if !usedCompletions.contains(completion) && !completion.isEmpty {
                    usedCompletions.insert(completion)
                    suggestions.append(Suggestion(
                        icon: item.icon,
                        text: item.text,
                        completion: item.completion,
                        color: item.color,
                        category: .time
                    ))
                }
            }
        }
        
        return Array(suggestions.prefix(5))
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let suggestion: Suggestion
    let onTap: () -> Void
    
    @State private var isPressed = false
    @State private var isHighlighted = false
    
    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 4) {
                Text(suggestion.icon)
                    .font(.system(size: 14))
                Text(suggestion.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(suggestion.color.opacity(isHighlighted ? 0.25 : 0.1))
            )
            .overlay(
                Capsule()
                    .stroke(suggestion.color.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(suggestion.color.opacity(0.9))
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleTap() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Visual feedback
        withAnimation(.easeInOut(duration: 0.1)) {
            isPressed = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isPressed = false
                isHighlighted = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onTap()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        isHighlighted = false
                    }
                }
            }
        }
    }
}

// MARK: - Smart Suggestion Bar

struct SmartSuggestionBar: View {
    @Binding var text: String
    let onSuggestionTap: (String) -> Void
    
    private let generator = SuggestionGenerator()
    @State private var suggestions: [Suggestion] = []
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isVisible && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            SuggestionChip(suggestion: suggestion) {
                                handleSuggestionTap(suggestion)
                            }
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.8)
                                .delay(Double(index) * 0.05),
                                value: suggestions
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(.systemBackground).opacity(0.95),
                            Color(.systemBackground).opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .onChange(of: text) { newValue in
            updateSuggestions(for: newValue)
        }
        .onAppear {
            updateSuggestions(for: text)
        }
    }
    
    private func updateSuggestions(for text: String) {
        let newSuggestions = generator.generateSuggestions(for: text)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            suggestions = newSuggestions
            isVisible = !newSuggestions.isEmpty
        }
    }
    
    private func handleSuggestionTap(_ suggestion: Suggestion) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if we're in import mode
        if suggestion.category == .importAction {
            onSuggestionTap(suggestion.completion)
            return
        }
        
        // For genre/format/length suggestions, append intelligently
        let lowercasedText = trimmedText.lowercased()
        let completion = suggestion.completion.lowercased()
        
        // Avoid duplicating if already mentioned
        if lowercasedText.contains(completion) {
            onSuggestionTap(trimmedText)
            return
        }
        
        // Smart append based on text ending
        var newText = trimmedText
        
        if trimmedText.isEmpty {
            newText = suggestion.completion
        } else if trimmedText.hasSuffix(",") || trimmedText.hasSuffix(" ") {
            newText = trimmedText + suggestion.completion
        } else {
            // Add appropriate connector
            let lastWord = trimmedText.components(separatedBy: .whitespaces).last?.lowercased() ?? ""
            
            if ["want", "like", "prefer", "looking", "something"].contains(lastWord) {
                newText = trimmedText + " " + suggestion.completion
            } else {
                newText = trimmedText + ", " + suggestion.completion
            }
        }
        
        onSuggestionTap(newText)
    }
}

// MARK: - Concierge Input with Suggestions

struct ConciergeInputWithSuggestions: View {
    @Binding var text: String
    let placeholder: String
    let onSend: () -> Void
    let onSuggestionTap: ((String) -> Void)?
    
    @FocusState private var isFocused: Bool
    @State private var showSuggestions = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Smart suggestion bar (appears above input)
            if showSuggestions {
                SmartSuggestionBar(text: $text) { suggestionText in
                    text = suggestionText
                    onSuggestionTap?(suggestionText)
                    
                    // Keep focus on input after suggestion tap
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
            }
            
            // Input field area
            HStack(spacing: 12) {
                // Text input
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused($isFocused)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                
                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(text.isEmpty ? .gray : .accentColor)
                        .rotationEffect(.degrees(text.isEmpty ? 0 : 0))
                }
                .disabled(text.isEmpty)
                .scaleEffect(text.isEmpty ? 0.9 : 1.0)
                .animation(.spring(response: 0.2), value: text.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: -2)
        )
    }
}

// MARK: - Preview

#Preview("Smart Suggestions Demo") {
    SmartSuggestionsDemoView()
}

struct SmartSuggestionsDemoView: View {
    @State private var text1 = ""
    @State private var text2 = "I want something funny"
    @State private var text3 = "Attack on Titan, Hunter x Hunter, Fullmetal"
    @State private var text4 = "Looking for action"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Demo 1: Empty state with time-aware suggestions
                DemoSection(title: "Empty State (Time-Aware)") {
                    ConciergeInputWithSuggestions(
                        text: $text1,
                        placeholder: "Ask Concierge anything...",
                        onSend: {},
                        onSuggestionTap: { suggestion in
                            print("Tapped: \(suggestion)")
                        }
                    )
                }
                
                // Demo 2: Genre suggestions
                DemoSection(title: "Genre Suggestions") {
                    ConciergeInputWithSuggestions(
                        text: $text2,
                        placeholder: "Ask Concierge anything...",
                        onSend: {},
                        onSuggestionTap: { suggestion in
                            print("Tapped: \(suggestion)")
                        }
                    )
                }
                
                // Demo 3: Import detection
                DemoSection(title: "Import Detection") {
                    ConciergeInputWithSuggestions(
                        text: $text3,
                        placeholder: "Paste your list...",
                        onSend: {},
                        onSuggestionTap: { suggestion in
                            print("Tapped: \(suggestion)")
                        }
                    )
                }
                
                // Demo 4: Action suggestions
                DemoSection(title: "Action Keywords") {
                    ConciergeInputWithSuggestions(
                        text: $text4,
                        placeholder: "Ask Concierge anything...",
                        onSend: {},
                        onSuggestionTap: { suggestion in
                            print("Tapped: \(suggestion)")
                        }
                    )
                }
                
                // Individual chip showcase
                DemoSection(title: "Individual Chips") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            SuggestionChip(
                                suggestion: Suggestion(
                                    icon: "😄",
                                    text: "Comedy",
                                    completion: "comedy",
                                    color: .orange,
                                    category: .genre
                                ),
                                onTap: {}
                            )
                            
                            SuggestionChip(
                                suggestion: Suggestion(
                                    icon: "⚔️",
                                    text: "Action",
                                    completion: "action",
                                    color: .red,
                                    category: .genre
                                ),
                                onTap: {}
                            )
                            
                            SuggestionChip(
                                suggestion: Suggestion(
                                    icon: "🎬",
                                    text: "Movie",
                                    completion: "movie",
                                    color: .purple,
                                    category: .format
                                ),
                                onTap: {}
                            )
                            
                            SuggestionChip(
                                suggestion: Suggestion(
                                    icon: "⏱️",
                                    text: "Short (<12)",
                                    completion: "short",
                                    color: .cyan,
                                    category: .length
                                ),
                                onTap: {}
                            )
                            
                            SuggestionChip(
                                suggestion: Suggestion(
                                    icon: "📋",
                                    text: "5 titles",
                                    completion: "confirm",
                                    color: .blue,
                                    category: .importAction
                                ),
                                onTap: {}
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct DemoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            
            content
        }
    }
}

// MARK: - Additional Preview for Testing

#Preview("Suggestion Generator Tests") {
    SuggestionGeneratorTestView()
}

struct SuggestionGeneratorTestView: View {
    let generator = SuggestionGenerator()
    let testInputs = [
        "",
        "I want something funny",
        "Something scary",
        "Looking for romance",
        "Love story",
        "Action packed",
        "Makes me cry",
        "Smart anime",
        "Future setting",
        "Naruto, Bleach, One Piece",
        "Just a single title"
    ]
    
    var body: some View {
        List {
            ForEach(testInputs, id: \.self) { input in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input: \"\(input.isEmpty ? "(empty)" : input)\"")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    let suggestions = generator.generateSuggestions(for: input)
                    
                    if suggestions.isEmpty {
                        Text("No suggestions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions) { suggestion in
                                    HStack(spacing: 4) {
                                        Text(suggestion.icon)
                                            .font(.caption)
                                        Text(suggestion.text)
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(suggestion.color.opacity(0.15))
                                    .foregroundColor(suggestion.color)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
}

#endif
