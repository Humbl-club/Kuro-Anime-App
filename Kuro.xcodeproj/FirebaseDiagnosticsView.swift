import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firebase Diagnostics View
struct FirebaseDiagnosticsView: View {
    @State private var diagnosticResults: [String] = []
    @State private var isRunning = false
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                
                Button(action: runDiagnostics) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isRunning ? "Running Tests..." : "Run Firebase Diagnostics")
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isRunning)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnosticResults.indices, id: \.self) { index in
                            HStack {
                                Image(systemName: getStatusIcon(for: diagnosticResults[index]))
                                    .foregroundColor(getStatusColor(for: diagnosticResults[index]))
                                
                                Text(diagnosticResults[index])
                                    .font(.system(.caption, design: .monospaced))
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Firebase Diagnostics")
        }
    }
    
    private func runDiagnostics() {
        isRunning = true
        diagnosticResults.removeAll()
        
        Task {
            await performDiagnostics()
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    @MainActor
    private func performDiagnostics() async {
        diagnosticResults.append("🔍 Starting Firebase Diagnostics...")
        
        // Test 1: Firebase Configuration
        do {
            if FirebaseApp.app() != nil {
                diagnosticResults.append("✅ Firebase App: Configured")
                
                if let app = FirebaseApp.app() {
                    diagnosticResults.append("✅ Project ID: \(app.options.projectID)")
                    diagnosticResults.append("✅ App ID: \(app.options.googleAppID)")
                }
            } else {
                diagnosticResults.append("❌ Firebase App: Not Configured")
            }
        }
        
        await Task.sleep(1_000_000_000) // 1 second delay
        
        // Test 2: Authentication
        diagnosticResults.append("🔐 Testing Authentication...")
        
        do {
            let authResult = try await Auth.auth().signInAnonymously()
            diagnosticResults.append("✅ Auth: Anonymous sign-in successful")
            diagnosticResults.append("✅ User ID: \(authResult.user.uid)")
        } catch {
            diagnosticResults.append("❌ Auth Error: \(error.localizedDescription)")
        }
        
        await Task.sleep(1_000_000_000)
        
        // Test 3: Firestore Connection
        diagnosticResults.append("🗄️ Testing Firestore Connection...")
        
        do {
            let db = Firestore.firestore()
            let testDoc = try await db.collection("test").document("connection-test").getDocument()
            diagnosticResults.append("✅ Firestore: Connection successful")
            
            if testDoc.exists {
                diagnosticResults.append("✅ Test document exists")
            } else {
                diagnosticResults.append("ℹ️ Test document doesn't exist (normal)")
            }
        } catch {
            diagnosticResults.append("❌ Firestore Error: \(error.localizedDescription)")
        }
        
        await Task.sleep(1_000_000_000)
        
        // Test 4: Media Collection Access
        diagnosticResults.append("📺 Testing Media Collection...")
        
        do {
            let db = Firestore.firestore()
            let snapshot = try await db.collection("media").limit(to: 1).getDocuments()
            diagnosticResults.append("✅ Media Collection: Accessible")
            diagnosticResults.append("ℹ️ Found \(snapshot.documents.count) documents")
        } catch {
            diagnosticResults.append("❌ Media Collection Error: \(error.localizedDescription)")
        }
        
        diagnosticResults.append("🏁 Diagnostics Complete!")
    }
    
    private func getStatusIcon(for result: String) -> String {
        if result.contains("✅") { return "checkmark.circle.fill" }
        if result.contains("❌") { return "xmark.circle.fill" }
        if result.contains("⚠️") { return "exclamationmark.triangle.fill" }
        if result.contains("ℹ️") { return "info.circle.fill" }
        if result.contains("🔍") { return "magnifyingglass" }
        if result.contains("🔐") { return "lock.fill" }
        if result.contains("🗄️") { return "externaldrive.fill" }
        if result.contains("📺") { return "tv.fill" }
        if result.contains("🏁") { return "flag.checkered" }
        return "circle"
    }
    
    private func getStatusColor(for result: String) -> Color {
        if result.contains("✅") { return .green }
        if result.contains("❌") { return .red }
        if result.contains("⚠️") { return .orange }
        return .blue
    }
}

// MARK: - Preview
struct FirebaseDiagnosticsView_Previews: PreviewProvider {
    static var previews: some View {
        FirebaseDiagnosticsView()
    }
}