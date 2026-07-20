import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("数据") {
                    LabeledContent("步道数量", value: store.trailCount.formatted())
                    LabeledContent("覆盖州数", value: "\(store.states.count)")
                    LabeledContent("数据快照", value: DataStore.datasetDate)
                    LabeledContent("收藏数量", value: "\(store.favorites.count)")
                    LabeledContent("徒步记录", value: "\(store.hikes.count)")
                    LabeledContent("数据来源") {
                        Link("Bhuemann/AllTrailsDataExporter",
                             destination: URL(string: "https://github.com/Bhuemann/AllTrailsDataExporter")!)
                    }
                }
                Section {
                    Button("重新下载全量数据", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("将删除本地数据库并从服务器重新下载完整数据库（含离线路线）。")
                }
                Section("iCloud 同步") {
                    Text("收藏与徒步记录通过 iCloud 键值存储自动同步到你的所有设备（需登录 iCloud）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("说明") {
                    Text("数据为 AllTrails 公开页面的抓取快照，版权归 AllTrails 及其贡献者所有，仅供学习研究使用，请勿商用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("关于")
            .confirmationDialog("确定要重新下载吗？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("删除并重新下载", role: .destructive) {
                    store.resetAndRedownload()
                }
            }
        }
    }
}
