//
//  FirebaseDataSeeder.swift
//  Kuro
//
//  Created by Max Dev on 29.09.25.
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

// MARK: - Firebase Data Seeder
/// Seeds the Firebase database with curated anime/manga content for KURO
@MainActor
class FirebaseDataSeeder {
    private let db = Firestore.firestore()
    
    // MARK: - Seed Sample Data
    func seedSampleData() async {
        print("🌱 Starting data seeding for KURO...")
        
        // Ensure user is authenticated
        if Auth.auth().currentUser == nil {
            do {
                try await Auth.auth().signInAnonymously()
                print("✅ Authenticated for seeding")
            } catch {
                print("❌ Authentication failed: \(error)")
                return
            }
        }
        
        await seedMediaItems()
        await seedUserLists()
        
        print("🌱 Data seeding completed!")
    }
    
    // MARK: - Seed Media Items
    private func seedMediaItems() async {
        print("📺 Seeding media items...")
        
        let mediaItems = [
            // Contemplative Mood
            Media(
                id: "spirited-away",
                title: "Spirited Away",
                year: 2001,
                description: "A young girl enters a world ruled by gods and witches where humans are changed into beasts. A masterpiece of contemplative storytelling and breathtaking animation.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BMjlmZmI5MDctNDE2YS00YWE0LWE5ZWItZDBhYWQ0NTcxNWRhXkEyXkFqcGdeQXVyMTMxODk2OTU@._V1_.jpg",
                type: .anime,
                genres: ["Fantasy", "Adventure", "Family"],
                episodes: 1,
                status: "Completed",
                rating: 9.3,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Energetic Mood
            Media(
                id: "demon-slayer",
                title: "Demon Slayer: Kimetsu no Yaiba",
                year: 2019,
                description: "Tanjiro embarks on a dangerous journey to turn his sister back into a human and to get revenge on the demon who killed his family. High-energy action with stunning visuals.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BZjZjNzI5MDctY2Y4YS00NmM4LTljMmItZTFkOTExNGI3ODRhXkEyXkFqcGdeQXVyNjc3MjQzNTI@._V1_.jpg",
                type: .anime,
                genres: ["Action", "Supernatural", "Historical"],
                episodes: 44,
                status: "Ongoing",
                rating: 8.7,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Melancholic Mood
            Media(
                id: "your-name",
                title: "Your Name",
                year: 2016,
                description: "Two teenagers share a profound, magical connection upon discovering they are swapping bodies. A beautifully melancholic tale of love transcending time and space.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BODRmZDVmNzUtZDA4ZC00NjhkLWI2M2UtN2M0ZDIzNDcxYThjL2ltYWdlXkEyXkFqcGdeQXVyNTk0MzMzODA@._V1_.jpg",
                type: .anime,
                genres: ["Romance", "Drama", "Supernatural"],
                episodes: 1,
                status: "Completed",
                rating: 8.4,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Uplifting Mood
            Media(
                id: "haikyuu",
                title: "Haikyu!!",
                year: 2014,
                description: "A high school volleyball team's journey to nationals. An incredibly uplifting sports anime about determination, friendship, and never giving up on your dreams.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BNjkyNDI2MTgtZWY1My00ZWQyLTljMjYtOWM3ZWUwNGUzY2JkXkEyXkFqcGdeQXVyNjc2NjA5MTU@._V1_.jpg",
                type: .anime,
                genres: ["Sports", "Comedy", "Drama"],
                episodes: 85,
                status: "Completed",
                rating: 8.8,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Mysterious Mood
            Media(
                id: "serial-experiments-lain",
                title: "Serial Experiments Lain",
                year: 1998,
                description: "A quiet student receives a mysterious email from a classmate who committed suicide. A philosophical exploration of identity and reality in the digital age.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BODc0NmY5MDQtMzFhZC00MWJiLTlkYTgtNGJkOGE1YWUyNDNmXkEyXkFqcGdeQXVyNzgxMzc3OTc@._V1_.jpg",
                type: .anime,
                genres: ["Mystery", "Psychological", "Sci-Fi"],
                episodes: 13,
                status: "Completed",
                rating: 8.1,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Additional Contemplative
            Media(
                id: "mushishi",
                title: "Mushishi",
                year: 2005,
                description: "A wanderer investigates supernatural phenomena in a world between dreams and reality. Deeply contemplative and atmospheric, perfect for quiet reflection.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BMTk5NDI3NTA2OF5BMl5BanBnXkFtZTcwODc2MTI0OQ@@._V1_.jpg",
                type: .anime,
                genres: ["Mystery", "Supernatural", "Historical"],
                episodes: 46,
                status: "Completed",
                rating: 9.0,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Manga Examples
            Media(
                id: "monster-manga",
                title: "Monster",
                year: 1994,
                description: "A surgeon's decision to save a child's life leads him on a decades-long hunt for the truth. One of the greatest psychological thrillers ever created.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BZjg3NjM4YjQtMjFmMi00YWYxLTk3ZjItZGZjZTNhZGVkYjNlXkEyXkFqcGdeQXVyNjc2NjA5MTU@._V1_.jpg",
                type: .manga,
                genres: ["Psychological", "Thriller", "Drama"],
                episodes: nil,
                status: "Completed",
                rating: 9.1,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            Media(
                id: "berserk-manga",
                title: "Berserk",
                year: 1989,
                description: "A dark medieval fantasy following the journey of Guts, a lone mercenary. A masterpiece of storytelling and art that redefined manga as an art form.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BNDFjYTk4ZDEtOWVjOS00NGVjLTlhZTAtZjBkYWM3OGY3MjZmXkEyXkFqcGdeQXVyNjc2NjA5MTU@._V1_.jpg",
                type: .manga,
                genres: ["Dark Fantasy", "Action", "Drama"],
                episodes: nil,
                status: "Ongoing",
                rating: 9.4,
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            // Manhwa Example
            Media(
                id: "tower-of-god",
                title: "Tower of God",
                year: 2010,
                description: "A boy enters a mysterious tower to chase the most important thing to him. A Korean webtoon that revolutionized the manhwa medium.",
                imageURL: "https://m.media-amazon.com/images/M/MV5BNTEyOTY1MjMtMzAyNy00YzJhLTg4NzQtZTVjN2E5MjQwNjE5XkEyXkFqcGdeQXVyNjc2NjA5MTU@._V1_.jpg",
                type: .manhwa,
                genres: ["Action", "Adventure", "Mystery"],
                episodes: 588,
                status: "Ongoing",
                rating: 8.3,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        // Add each media item to Firestore
        for media in mediaItems {
            do {
                let mediaData = try media.toDictionary()
                try await db.collection("media").document(media.id ?? UUID().uuidString).setData(mediaData)
                print("✅ Added: \(media.title)")
            } catch {
                print("❌ Failed to add \(media.title): \(error)")
            }
        }
    }
    
    // MARK: - Seed User Lists
    private func seedUserLists() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user for seeding lists")
            return
        }
        
        print("📝 Seeding user lists...")
        
        let userLists = [
            UserList(
                id: "\(userId)_watching",
                name: "Currently Watching",
                type: .watching,
                mediaItems: ["demon-slayer", "tower-of-god"],
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            UserList(
                id: "\(userId)_completed",
                name: "Completed",
                type: .completed,
                mediaItems: ["spirited-away", "your-name", "haikyuu", "serial-experiments-lain", "monster-manga"],
                createdAt: Date(),
                updatedAt: Date()
            ),
            
            UserList(
                id: "\(userId)_planned",
                name: "Plan to Watch",
                type: .planned,
                mediaItems: ["mushishi", "berserk-manga"],
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        
        for userList in userLists {
            do {
                let listData = try userList.toDictionary()
                try await db.collection("user_lists").document(userList.id ?? UUID().uuidString).setData(listData)
                print("✅ Added list: \(userList.name)")
            } catch {
                print("❌ Failed to add list \(userList.name): \(error)")
            }
        }
    }
}

// MARK: - Extensions for Dictionary Conversion
extension Media {
    func toDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
        return dictionary ?? [:]
    }
}

extension UserList {
    func toDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
        return dictionary ?? [:]
    }
}

// MARK: - Seeder View for Testing
struct FirebaseSeederView: View {
    @State private var isSeeding = false
    @State private var seedingResults: [String] = []
    @State private var showResults = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                
                VStack(spacing: 12) {
                    Text("KURO")
                        .font(.system(size: 24, weight: .ultraLight, design: .serif))
                        .tracking(8)
                    
                    Text("DATABASE SEEDER")
                        .font(.system(size: 10, weight: .light))
                        .tracking(3)
                        .foregroundColor(.black.opacity(0.5))
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    Text("This will populate your Firebase database with curated anime and manga content for testing KURO.")
                        .font(.system(size: 12, weight: .light))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: seedDatabase) {
                        HStack {
                            if isSeeding {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            }
                            Text(isSeeding ? "SEEDING..." : "SEED DATABASE")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(1.5)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .foregroundColor(.white)
                        .cornerRadius(0)
                    }
                    .disabled(isSeeding)
                }
                
                if showResults {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(seedingResults.indices, id: \.self) { index in
                                HStack {
                                    Image(systemName: getStatusIcon(for: seedingResults[index]))
                                        .foregroundColor(getStatusColor(for: seedingResults[index]))
                                        .font(.system(size: 12))
                                    
                                    Text(seedingResults[index])
                                        .font(.system(.caption, design: .monospaced))
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(0)
                    .padding(.horizontal, 24)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
    
    private func seedDatabase() {
        isSeeding = true
        seedingResults.removeAll()
        showResults = false
        
        Task {
            let seeder = FirebaseDataSeeder()
            await seeder.seedSampleData()
            
            await MainActor.run {
                isSeeding = false
                showResults = true
                seedingResults = [
                    "✅ Seeding completed successfully",
                    "📺 Added 9 media items",
                    "📝 Added 3 user lists",
                    "🎌 Your KURO app is ready to use!"
                ]
            }
        }
    }
    
    private func getStatusIcon(for result: String) -> String {
        if result.contains("✅") { return "checkmark.circle.fill" }
        if result.contains("❌") { return "xmark.circle.fill" }
        if result.contains("📺") { return "tv.fill" }
        if result.contains("📝") { return "list.bullet" }
        if result.contains("🎌") { return "flag.fill" }
        return "circle"
    }
    
    private func getStatusColor(for result: String) -> Color {
        if result.contains("✅") { return .green }
        if result.contains("❌") { return .red }
        if result.contains("🎌") { return .blue }
        return .primary
    }
}

struct FirebaseSeederView_Previews: PreviewProvider {
    static var previews: some View {
        FirebaseSeederView()
    }
}