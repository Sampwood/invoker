import SwiftUI

struct StatusBarMenuView: View {
    let quitAction: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            bodyShadow
            menuBody
        }
        .offset(x: StatusBarMenuMetrics.shadowPadding, y: StatusBarMenuMetrics.shadowPadding)
        .frame(
            width: StatusBarMenuMetrics.windowWidth,
            height: StatusBarMenuMetrics.windowHeight,
            alignment: .topLeading
        )
        .background(Color.clear)
    }

    private var bodyShadow: some View {
        RoundedRectangle(cornerRadius: StatusBarMenuMetrics.bodyCornerRadius, style: .continuous)
            .fill(Color.white)
            .frame(width: StatusBarMenuMetrics.bodyWidth, height: StatusBarMenuMetrics.bodyHeight)
            .shadow(
                color: .black.opacity(StatusBarMenuMetrics.shadowOpacity),
                radius: StatusBarMenuMetrics.shadowRadius,
                x: 0,
                y: StatusBarMenuMetrics.shadowYOffset
            )
    }

    private var menuBody: some View {
        VStack(spacing: 0) {
            StatusBarMenuRow(title: StatusBarMenuContent.items[0].title, action: quitAction)
        }
        .frame(width: StatusBarMenuMetrics.bodyWidth, height: StatusBarMenuMetrics.bodyHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: StatusBarMenuMetrics.bodyCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StatusBarMenuMetrics.bodyCornerRadius, style: .continuous)
                .stroke(
                    Color.black.opacity(StatusBarMenuMetrics.bodyBorderOpacity),
                    lineWidth: StatusBarMenuMetrics.bodyBorderLineWidth
                )
        )
    }
}

private struct StatusBarMenuRow: View {
    @State private var isHovered = false

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: StatusBarMenuMetrics.textFontSize, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(
                width: StatusBarMenuMetrics.bodyWidth - 8 - StatusBarMenuMetrics.rowHorizontalPadding * 2,
                height: StatusBarMenuMetrics.rowHeight,
                alignment: .leading
            )
            .padding(.horizontal, StatusBarMenuMetrics.rowHorizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: StatusBarMenuMetrics.rowCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(isHovered ? StatusBarMenuMetrics.rowHoverOpacity : 0))
            )
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
