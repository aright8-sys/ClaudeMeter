import SwiftUI

/// 简洁的环形进度指示器，中心显示百分比。
struct ProgressRing: View {
    let fraction: Double          // 0...1+
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10

    private var clamped: Double { min(max(fraction, 0), 1) }

    private var color: Color {
        switch fraction {
        case ..<0.7: return .green
        case ..<0.9: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: clamped)
            VStack(spacing: 2) {
                Text(Format.percent(fraction))
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("额度")
                    .font(.system(size: size * 0.12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
