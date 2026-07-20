import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.trailGreen)
            Text("MyTrails")
                .font(.largeTitle.bold())
            Text("77,000+ 条美国步道 · 含离线路线\n数据快照 \(DataStore.datasetDate)")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Group {
                switch store.phase {
                case .idle:
                    Button {
                        store.startDownload()
                    } label: {
                        Label("下载离线数据库", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                case .downloading(let p):
                    progressView("正在下载数据库…", p)
                case .importing:
                    ProgressView("正在校验数据…")
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("重试") { store.startDownload() }
                            .buttonStyle(.borderedProminent)
                    }
                case .ready:
                    EmptyView()
                }
            }
            .frame(minHeight: 80)

            Spacer()
            Text("数据来自 AllTrails 公开页面抓取快照，仅供学习研究")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .task {
            if case .idle = store.phase { store.startDownload() }
        }
    }

    private func progressView(_ title: String, _ progress: Double) -> some View {
        ProgressView(value: progress) {
            Text(title).font(.subheadline)
        } currentValueLabel: {
            Text("\(Int(progress * 100))%")
        }
        .frame(maxWidth: 280)
    }
}
