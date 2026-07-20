import SwiftUI

struct SearchListView: View {
    @EnvironmentObject private var store: DataStore
    @State private var query = ""
    @State private var results: [Trail] = []
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            TrailListView(trails: results, title: "全部步道")
                .searchable(text: $query, prompt: "搜索步道、公园或州名")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFilters = true
                        } label: {
                            Label("筛选", systemImage: store.filter.isActive
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .sheet(isPresented: $showFilters) {
                    FiltersView()
                }
                .task { await reload() }
                .onChange(of: query) {
                    Task { await reload() }
                }
                .onChange(of: store.filter) {
                    Task { await reload() }
                }
        }
    }

    private func reload() async {
        guard let db = store.db else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        let filter = store.filter
        results = await db.run {
            q.isEmpty ? $0.top(filter: filter, limit: 200) : $0.search(q, filter: filter, limit: 200)
        }
    }
}
