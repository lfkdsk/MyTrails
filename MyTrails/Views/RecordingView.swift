import SwiftUI
import MapKit
import CoreLocation

/// GPS 记录界面：实时地图轨迹 + 里程/用时统计。
struct RecordingView: View {
    @EnvironmentObject private var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = TrackRecorder()

    /// 关联的步道（从详情页进入时带上；自由记录为 nil）
    let trail: Trail?

    @State private var position: MapCameraPosition
    @State private var showSaveSheet = false
    @State private var notes = ""
    @State private var rating = 0
    @State private var plannedPaths = TrailPaths()
    @State private var loadingPaths = false
    @State private var confirmExit = false
    @State private var distanceToTrail: CLLocationDistance?

    /// 距路线 500 米内才允许开始（自由记录不受限）
    private static let startProximityMeters: CLLocationDistance = 500

    private var canStart: Bool {
        guard trail != nil else { return true }
        guard let distance = distanceToTrail else { return false }
        return distance <= Self.startProximityMeters
    }

    init(trail: Trail?) {
        self.trail = trail
        if let trail {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: trail.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(plannedPaths.matched.indices, id: \.self) { index in
                        MapPolyline(coordinates: plannedPaths.matched[index])
                            .stroke(Color.orange.opacity(0.9),
                                    style: plannedPaths.isDashed
                                        ? StrokeStyle(lineWidth: 3, dash: [7, 5])
                                        : StrokeStyle(lineWidth: 4))
                    }
                    if recorder.points.count > 1 {
                        MapPolyline(coordinates: recorder.points)
                            .stroke(Color.trailGreen, lineWidth: 4)
                    }
                    if let trail {
                        Annotation(trail.name, coordinate: trail.coordinate) {
                            TrailMarker(trail: trail)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))

                controls
            }
            .navigationTitle(trail?.name ?? "GPS 记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        if recorder.state == .idle {
                            recorder.reset()
                            dismiss()
                        } else {
                            confirmExit = true
                        }
                    }
                }
            }
            .confirmationDialog("确定要退出吗？", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("放弃本次记录", role: .destructive) {
                    recorder.reset()
                    dismiss()
                }
                Button("继续记录", role: .cancel) {}
            } message: {
                Text("退出将丢弃当前未保存的轨迹")
            }
            .sheet(isPresented: $showSaveSheet) {
                saveSheet
            }
            .onAppear {
                recorder.requestPermission()
                recorder.startPreview()
            }
            .onChange(of: recorder.currentLocation) {
                updateDistanceToTrail()
            }
            .task {
                if let trail {
                    loadingPaths = true
                    plannedPaths = await TrailPathLoader.paths(around: trail, db: store.db)
                    loadingPaths = false
                    updateDistanceToTrail()
                    // 路线加载后（尚未开始录制时）把视野适配到整条路线
                    if recorder.state == .idle, !plannedPaths.matched.isEmpty {
                        var points = plannedPaths.matched.flatMap { $0 }
                        points.append(trail.coordinate)
                        let lats = points.map(\.latitude)
                        let lngs = points.map(\.longitude)
                        withAnimation {
                            position = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: (lats.min()! + lats.max()!) / 2,
                                    longitude: (lngs.min()! + lngs.max()!) / 2),
                                span: MKCoordinateSpan(
                                    latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.02),
                                    longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.02))))
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if trail != nil {
                    Group {
                        if !plannedPaths.matched.isEmpty {
                            if plannedPaths.isDashed {
                                Label("虚线：参考路线（可信度中等，请自行核对）", systemImage: "map")
                            } else {
                                Label("橙色：本步道路线（高可信 · OSM 多源）", systemImage: "map")
                            }
                        } else if !loadingPaths {
                            Label("本步道暂无收录路线", systemImage: "map.circle")
                        }
                    }
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 4)
                }
            }
            .task {
                // 调试钩子：MT_AUTO_RECORD=<秒数> 自动开始并在 N 秒后结束保存
                if let s = ProcessInfo.processInfo.environment["MT_AUTO_RECORD"], let secs = Double(s) {
                    recorder.start()
                    withAnimation {
                        position = .userLocation(fallback: .automatic)
                    }
                    try? await Task.sleep(for: .seconds(secs))
                    recorder.stop()
                    rating = 5
                    save(notes: "沿 Mist Trail 走到 Vernal Fall 桥，水汽扑面，值得五星。")
                    dismiss()
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                RecordingStat(value: String(format: "%.2f", recorder.distanceMeters / 1000), label: "公里")
                RecordingStat(value: recorder.formattedElapsed, label: "用时")
                RecordingStat(value: "\(recorder.points.count)", label: "轨迹点")
            }
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            switch recorder.state {
            case .idle:
                VStack(spacing: 8) {
                    bigButton("开始记录", icon: "record.circle.fill",
                              color: canStart ? Color.trailGreen : .gray) {
                        guard canStart else { return }
                        recorder.start()
                        withAnimation {
                            position = .userLocation(fallback: .automatic)
                        }
                    }
                    .disabled(!canStart)
                    if trail != nil, !canStart {
                        if let distance = distanceToTrail {
                            Text(String(format: "距步道 %.1f km，需在 %.0f 米内才能开始记录",
                                        distance / 1000, Self.startProximityMeters))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("正在获取你的位置…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .recording:
                bigButton("结束", icon: "stop.circle.fill", color: .red) {
                    recorder.stop()
                    showSaveSheet = true
                }
            case .finished:
                bigButton("保存记录", icon: "checkmark.circle.fill", color: Color.trailGreen) {
                    showSaveSheet = true
                }
            }

            if recorder.authorization == .denied {
                Text("定位权限被拒绝，请在系统设置中允许 MyTrails 使用位置")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    private func bigButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(color, in: Capsule())
        }
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("本次徒步") {
                    LabeledContent("距离", value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                    LabeledContent("用时", value: recorder.formattedElapsed)
                    LabeledContent("轨迹点", value: "\(recorder.points.count)")
                }
                Section("评分") {
                    StarPicker(rating: $rating)
                }
                Section("测评") {
                    TextField("写点这条步道的感受：风景、难度、路况…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button("放弃这次记录", role: .destructive) {
                        showSaveSheet = false
                        recorder.reset()
                        dismiss()
                    }
                }
            }
            .navigationTitle("保存记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save(notes: notes)
                        showSaveSheet = false
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 计算当前位置到本步道的最近距离：取「路线上最近点」与「步道口」的较小者
    /// （OSM 匹配的路段可能从离步道口较远处才开始，站在步道口必须视为在附近）
    private func updateDistanceToTrail() {
        guard let trail, let location = recorder.currentLocation else { return }
        var distance = location.distance(
            from: CLLocation(latitude: trail.latitude, longitude: trail.longitude))
        if let routeMin = plannedPaths.matched.lazy.joined()
            .map({ location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) })
            .min() {
            distance = min(distance, routeMin)
        }
        distanceToTrail = distance
    }

    private func save(notes: String) {
        store.addHike(HikeRecord(
            trailId: trail?.id,
            trailName: trail?.name ?? "自由徒步",
            state: trail?.state ?? "",
            distanceMiles: recorder.distanceMeters / 1609.34,
            date: recorder.startDate ?? Date(),
            durationMinutes: max(1, Int(recorder.elapsed / 60)),
            notes: notes,
            track: recorder.downsampledTrack(),
            rating: rating > 0 ? rating : nil))
    }
}

struct RecordingStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
