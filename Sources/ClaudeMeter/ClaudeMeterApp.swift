import SwiftUI

@main
struct ClaudeMeterApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: state)
        } label: {
            // 菜单栏图标 + 百分比 + 5 小时窗口重置倒计时(单个 Text)
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(state.statusBarText)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
