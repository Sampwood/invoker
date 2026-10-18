import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var viewModel: SystemMonitorViewModel

    let openCachesAction: () -> Void

    var body: some View {
        let snapshot = viewModel.snapshot

        VStack(alignment: .leading, spacing: 0) {
            header
            metricGrid(snapshot: snapshot)
            footer
        }
        .padding(22)
        .frame(width: 560, height: 388)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                viewModel.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("系统监控")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text("实时查看这台 Mac 的运行状态")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            Button {
                viewModel.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("刷新")
            .accessibilityLabel("刷新系统状态")
        }
        .padding(.bottom, 18)
    }

    private func metricGrid(snapshot: SystemMonitorSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            MetricCard(
                title: "处理器",
                value: percentage(snapshot.cpuUsage),
                detail: "当前总占用",
                systemImage: "cpu",
                tint: .blue,
                progress: snapshot.cpuUsage
            )
            MetricCard(
                title: "内存",
                value: percentage(snapshot.memoryUsage),
                detail: "\(bytes(snapshot.usedMemory)) / \(bytes(snapshot.totalMemory))",
                systemImage: "memorychip",
                tint: .purple,
                progress: snapshot.memoryUsage
            )
            MetricCard(
                title: "磁盘",
                value: percentage(ratio(used: snapshot.usedDisk, total: snapshot.totalDisk)),
                detail: "\(bytes(snapshot.usedDisk)) / \(bytes(snapshot.totalDisk))",
                systemImage: "internaldrive",
                tint: .orange,
                progress: ratio(used: snapshot.usedDisk, total: snapshot.totalDisk)
            )
            MetricCard(
                title: "运行时间",
                value: duration(snapshot.uptime),
                detail: "系统已连续运行",
                systemImage: "clock",
                tint: .green,
                progress: nil
            )
        }
    }

    private var footer: some View {
        HStack {
            Label("数据每 2 秒刷新", systemImage: "waveform.path.ecg")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Spacer()

            Button("在 Finder 中查看缓存") {
                openCachesAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 18)
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func ratio(used: UInt64, total: UInt64) -> Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    private func duration(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = value >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: value) ?? "--"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .lineLimit(1)

            if let progress {
                ProgressView(value: progress)
                    .tint(tint)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}
