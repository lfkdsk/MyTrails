import SwiftUI

@main
struct MyTrailsApp: App {
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.trailGreen)
        }
    }
}

extension Color {
    /// AllTrails 风格主色
    static let trailGreen = Color(red: 0.26, green: 0.54, blue: 0.14)
}
