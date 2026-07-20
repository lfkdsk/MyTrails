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
    /// AllTrails 品牌绿 #428A13
    static let trailGreen = Color(red: 0.259, green: 0.541, blue: 0.075)
    /// AllTrails 深绿 #2C5601
    static let trailDark = Color(red: 0.173, green: 0.337, blue: 0.004)
}
