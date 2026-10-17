import SwiftUI

struct TabIconButton: View {
	let systemImage: String
	let iconSize: CGFloat
	let action: () -> Void

	@State private var isHovered = false

	init(
		systemImage: String,
		iconSize: CGFloat = 13,
		action: @escaping () -> Void
	) {
		self.systemImage = systemImage
		self.iconSize = iconSize
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			ZStack {
				RoundedRectangle(cornerRadius: 5, style: .continuous)
					.fill(Color.primary.opacity(isHovered ? 0.1 : 0))
					.frame(width: 22, height: 22)

				Image(systemName: systemImage)
					.font(.system(size: iconSize, weight: .semibold))
			}
			.frame(width: 28, height: 28)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.frame(width: 28, height: 28)
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.1), value: isHovered)
	}
}

struct IconButton: View {
	let systemImage: String
	let usesTitlebarBackground: Bool
	let action: () -> Void

	@State private var isHovered = false

	init(
		systemImage: String,
		usesTitlebarBackground: Bool = false,
		action: @escaping () -> Void
	) {
		self.systemImage = systemImage
		self.usesTitlebarBackground = usesTitlebarBackground
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			ZStack {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(Color.primary.opacity(isHovered ? 0.1 : 0))
					.frame(width: 30, height: 30)

				Image(systemName: systemImage)
					.font(.system(size: 13, weight: .semibold))
			}
			.frame(width: 30, height: 30)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.frame(width: 30, height: 30)
		.background {
			if usesTitlebarBackground {
				TitlebarMaterialBackground()
			}
		}
		.onHover { isHovered = $0 }
		.animation(.easeOut(duration: 0.1), value: isHovered)
	}
}

struct EntryTab: View {
	let entryID: String
	let title: String
	let width: CGFloat
	let isActive: Bool
	let isDirty: Bool
	let isDragged: Bool
	let horizontalOffset: CGFloat
	let activate: () -> Void
	let close: () -> Void
	let reorder: (CGFloat) -> Void
	let finishReordering: () -> Void

	@State private var isHovered = false

	private var showsCloseButton: Bool {
		isActive || isHovered
	}

	var body: some View {
		Button(action: activate) {
			HStack(spacing: 6) {
				if isDirty {
					Circle()
						.fill(.secondary)
						.frame(width: 6, height: 6)
				}

				Text(title)
					.lineLimit(1)
					.frame(maxWidth: .infinity, alignment: .leading)
					.foregroundStyle(isActive || isHovered ? Color.primary : Color.secondary)
			}
			.padding(.leading, 9)
			.padding(.trailing, 6)
			.frame(width: width, height: 30)
			.mask { titleMask }
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier("entry-tab.\(entryID)")
		.accessibilityValue(isDirty ? "Unsaved changes" : "Saved")
		.overlay(alignment: .trailing) {
			if showsCloseButton {
				TabIconButton(systemImage: "xmark", iconSize: 10, action: close)
					.padding(.trailing, 1)
					.accessibilityIdentifier("entry-tab.close.\(entryID)")
					.accessibilityLabel("Close \(title)")
					.help("Close \(title)")
			}
		}
		.background(
			isActive
				? Color.primary.opacity(0.14)
				: Color.primary.opacity(isHovered ? 0.08 : 0),
			in: RoundedRectangle(cornerRadius: 7, style: .continuous)
		)
		.overlay {
			RoundedRectangle(cornerRadius: 7, style: .continuous)
				.stroke(isActive ? Color.primary.opacity(0.16) : .clear)
		}
		.animation(.easeOut(duration: 0.12), value: isActive)
		.animation(.easeOut(duration: 0.12), value: isHovered)
		.contentShape(.rect)
		.offset(x: horizontalOffset)
		.scaleEffect(isDragged ? 1.025 : 1)
		.shadow(
			color: .black.opacity(isDragged ? 0.16 : 0),
			radius: 5,
			y: 2
		)
		.zIndex(isDragged ? 3 : 1)
		.highPriorityGesture(
			DragGesture(minimumDistance: 4)
				.onChanged { reorder($0.translation.width) }
				.onEnded { _ in finishReordering() }
		)
		.onHover { isHovered = $0 }
	}

	@ViewBuilder private var titleMask: some View {
		if showsCloseButton {
			HStack(spacing: 0) {
				Color.white
				LinearGradient(
					colors: [.white, .clear],
					startPoint: .leading,
					endPoint: .trailing
				)
				.frame(width: 12)
				Color.clear.frame(width: 28)
			}
		} else {
			Color.white
		}
	}
}
