import SwiftUI

struct FiltersView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss

    private static let difficultyOptions: [(Int, String)] = [
        (1, "简单"), (3, "中等"), (5, "困难"), (7, "极难"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("难度") {
                    ForEach(Self.difficultyOptions, id: \.0) { value, label in
                        Toggle(label, isOn: difficultyBinding(for: value))
                    }
                }
                Section("最低评分") {
                    Picker("最低评分", selection: $store.filter.minRating) {
                        Text("不限").tag(0.0)
                        Text("4.0+").tag(4.0)
                        Text("4.5+").tag(4.5)
                    }
                    .pickerStyle(.segmented)
                }
                Section("长度") {
                    Picker("长度", selection: $store.filter.lengthBucket) {
                        ForEach(TrailFilter.LengthBucket.allCases) { bucket in
                            Text(bucket.rawValue).tag(bucket)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("州") {
                    Picker("州", selection: $store.filter.state) {
                        Text("全部").tag(String?.none)
                        ForEach(store.states, id: \.self) { state in
                            Text(state).tag(String?.some(state))
                        }
                    }
                }
                Section {
                    Button("重置筛选", role: .destructive) {
                        store.filter = TrailFilter()
                    }
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func difficultyBinding(for value: Int) -> Binding<Bool> {
        Binding(
            get: { store.filter.difficulties.contains(value) },
            set: { isOn in
                if isOn {
                    store.filter.difficulties.insert(value)
                } else {
                    store.filter.difficulties.remove(value)
                }
            })
    }
}
