import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var store: DataStore
    @State private var trails: [Trail] = []

    var body: some View {
        NavigationStack {
            TrailListView(trails: trails, title: "收藏",
                          emptyText: "还没有收藏的步道")
                .task { await reload() }
                .onChange(of: store.favorites) {
                    Task { await reload() }
                }
        }
    }

    private func reload() async {
        guard let db = store.db else {
            trails = []
            return
        }
        let ids = Array(store.favorites)
        trails = await db.run { $0.trails(ids: ids) }
    }
}
