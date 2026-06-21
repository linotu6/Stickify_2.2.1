import SwiftUI

struct CloudTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .bold))
                            .frame(height: 23)

                        Text(tab.title)
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(color(for: tab))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(color(for: tab).opacity(0.12))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(7)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.68), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .frame(height: 72)
        .accessibilityElement(children: .contain)
    }

    private func color(for tab: AppTab) -> Color {
        guard selectedTab == tab else { return StickifyTheme.carbonBlack.opacity(0.68) }
        return tab == .playground ? StickifyTheme.energeticRed : StickifyTheme.classicBlue
    }
}
