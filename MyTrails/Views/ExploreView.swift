import SwiftUI
import MapKit
import CoreLocation

/// Explore 首页定位：请求权限并取一次定位，用于把首屏聚焦到用户附近
@MainActor
final class LocationAuth: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var firstFix: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            if self.firstFix == nil {
                self.firstFix = location
                self.manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct ExploreView: View {
    @EnvironmentObject private var store: DataStore
    @StateObject private var locationAuth = LocationAuth()
    @Namespace private var mapScope

    private static let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 42, longitudeDelta: 52))

    @State private var position: MapCameraPosition = .region(initialRegion)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var trails: [Trail] = []
    @State private var selected: Trail?
    @State private var showList = false
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            Map(position: $position, scope: mapScope) {
                UserAnnotation()
                ForEach(trails) { trail in
                    Annotation("", coordinate: trail.coordinate) {
                        TrailMarker(trail: trail)
                            .onTapGesture { selected = trail }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: 10) {
                    MapCompass(scope: mapScope)
                    MapUserLocationButton(scope: mapScope)
                }
                .padding(.trailing, 14)
                .padding(.bottom, 14)
            }
            .mapScope(mapScope)
            .onAppear { locationAuth.request() }
            .onChange(of: locationAuth.firstFix) {
                // 首次定位成功：聚焦到用户附近约 40km 范围，保证视野里有步道
                guard let location = locationAuth.firstFix else { return }
                withAnimation {
                    position = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)))
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                Task { await reload() }
            }
            .overlay(alignment: .top) {
                Text("显示 \(trails.count) 条步道")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 4)
            }
            .sheet(item: $selected) { trail in
                NavigationStack { TrailDetailView(trail: trail) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showList) {
                NavigationStack {
                    TrailListView(trails: trails, title: "当前区域步道")
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFilters) {
                FiltersView()
            }
            .task { await reload() }
            .onChange(of: store.filter) {
                Task { await reload() }
            }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.inline)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showList = true
                    } label: {
                        Label("列表", systemImage: "list.bullet")
                    }
                }
            }
        }
    }

    private func reload() async {
        guard let db = store.db else { return }
        let region = visibleRegion ?? Self.initialRegion
        let filter = store.filter
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        trails = await db.run {
            $0.trails(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
                      filter: filter, limit: 260)
        }
    }
}

struct TrailMarker: View {
    let trail: Trail

    var body: some View {
        Circle()
            .fill(trail.difficultyColor)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
    }
}
