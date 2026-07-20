import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        if store.phase == .ready {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: DataStore
    @State private var tab: Int
    @State private var debugTrail: Trail?

    init() {
        let initial = ProcessInfo.processInfo.environment["MT_TAB"].flatMap(Int.init) ?? 0
        _tab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            ExploreView()
                .tabItem { Label("探索", systemImage: "map.fill") }
                .tag(0)
            SearchListView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)
            HikesView()
                .tabItem { Label("记录", systemImage: "figure.hiking") }
                .tag(2)
            SavedView()
                .tabItem { Label("收藏", systemImage: "heart.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(4)
        }
        .task {
            // 调试钩子：MT_DETAIL=<关键词> 直接打开首个搜索结果详情
            if let q = ProcessInfo.processInfo.environment["MT_DETAIL"], let db = store.db {
                debugTrail = await db.run { $0.search(q, filter: TrailFilter(), limit: 1) }.first
            }
            // 调试钩子：MT_CLEAR_HIKES=1 清空全部徒步记录（含 iCloud 墓碑传播）
            if ProcessInfo.processInfo.environment["MT_CLEAR_HIKES"] != nil, !store.hikes.isEmpty {
                store.deleteHikes(at: IndexSet(0..<store.hikes.count))
            }
            // 调试钩子：MT_LOG_HIKE=<关键词> 自动为首个搜索结果创建一条徒步记录
            if let q = ProcessInfo.processInfo.environment["MT_LOG_HIKE"], let db = store.db,
               let trail = await db.run({ $0.search(q, filter: TrailFilter(), limit: 1) }).first {
                store.addHike(HikeRecord(
                    trailId: trail.id, trailName: trail.name, state: trail.state,
                    distanceMiles: trail.distanceMiles, date: .now,
                    durationMinutes: 372, notes: "风很大，山顶视野极好。"))
            }
        }
        .sheet(item: $debugTrail) { trail in
            NavigationStack { TrailDetailView(trail: trail) }
        }
    }
}
