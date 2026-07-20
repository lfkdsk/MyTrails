import SwiftUI

struct HikesView: View {
    @EnvironmentObject private var store: DataStore
    @State private var showRecorder = false
    @State private var selectedHike: HikeRecord?

    private var totalKm: Double { store.hikes.reduce(0) { $0 + $1.distanceKm } }
    private var totalMinutes: Int { store.hikes.reduce(0) { $0 + $1.durationMinutes } }

    var body: some View {
        NavigationStack {
            List {
                if !store.hikes.isEmpty {
                    Section {
                        HStack(spacing: 0) {
                            SummaryCell(value: "\(store.hikes.count)", label: "次数")
                            SummaryCell(value: String(format: "%.1f", totalKm), label: "公里")
                            SummaryCell(value: String(format: "%.1f", Double(totalMinutes) / 60), label: "小时")
                        }
                    }
                    Section("全部记录") {
                        ForEach(store.hikes) { hike in
                            Button {
                                selectedHike = hike
                            } label: {
                                HikeRow(hike: hike)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            store.deleteHikes(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRecorder = true
                    } label: {
                        Label("开始记录", systemImage: "record.circle")
                    }
                }
            }
            .overlay {
                if store.hikes.isEmpty {
                    ContentUnavailableView("还没有徒步记录", systemImage: "figure.hiking",
                                           description: Text("点右上角「开始记录」，用 GPS 记录你的徒步路线"))
                }
            }
            .fullScreenCover(isPresented: $showRecorder) {
                RecordingView(trail: nil)
            }
            .sheet(item: $selectedHike) { hike in
                NavigationStack { HikeDetailView(hike: hike) }
                    .presentationDetents([.medium, .large])
            }
            .task {
                let env = ProcessInfo.processInfo.environment
                if env["MT_AUTO_RECORD"] != nil {
                    showRecorder = true
                }
                if env["MT_OPEN_LAST_HIKE"] != nil {
                    selectedHike = store.hikes.first
                }
            }
        }
    }
}

struct SummaryCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Color.trailGreen)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HikeRow: View {
    let hike: HikeRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hike.hasTrack ? "map.fill" : "figure.hiking")
                .foregroundStyle(Color.trailGreen)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(hike.trailName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(hike.date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    Label(hike.formattedDuration, systemImage: "clock")
                    Text(String(format: "%.1f km", hike.distanceKm))
                    if let rating = hike.rating, rating > 0 {
                        StarDisplay(rating: rating, size: .caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !hike.notes.isEmpty {
                    Text(hike.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
