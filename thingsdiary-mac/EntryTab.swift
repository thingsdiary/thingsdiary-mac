import SwiftUI

struct AppIcon {
	let resource: ImageResource

	static let archive = Self(resource: .iconArchive)
	static let arrowUpDown = Self(resource: .iconArrowUpDown)
	static let book = Self(resource: .iconBook)
	static let bookmark = Self(resource: .iconBookmark)
	static let check = Self(resource: .iconCheck)
	static let chevronDown = Self(resource: .iconChevronDown)
	static let chevronRight = Self(resource: .iconChevronRight)
	static let close = Self(resource: .iconX)
	static let circleX = Self(resource: .iconCircleX)
	static let inbox = Self(resource: .iconInbox)
	static let layers = Self(resource: .iconLayers)
	static let menu = Self(resource: .iconMenu)
	static let messageSquareText = Self(resource: .iconMessageSquareText)
	static let newEntry = Self(resource: .iconSquarePen)
	static let panelLeft = Self(resource: .iconPanelLeft)
	static let plus = Self(resource: .iconPlus)
	static let settings = Self(resource: .iconSettings)
	static let trash = Self(resource: .iconTrash)
	static let trashEmpty = Self(resource: .iconTrashEmpty)
}

struct AppIconImage: View {
	let icon: AppIcon
	let size: CGFloat

	var body: some View {
		Image(icon.resource)
			.renderingMode(.template)
			.resizable()
			.scaledToFit()
			.frame(width: size, height: size)
	}
}

struct TabIconButton: View {
	let icon: AppIcon
	let iconSize: CGFloat
	let action: () -> Void

	init(
		icon: AppIcon,
		iconSize: CGFloat = 13,
		action: @escaping () -> Void
	) {
		self.icon = icon
		self.iconSize = iconSize
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			AppIconImage(icon: icon, size: iconSize)
				.frame(width: 28, height: 28)
				.contentShape(.rect)
		}
		.buttonStyle(AppHoverButtonStyle(cornerRadius: 5, backgroundInset: 3))
		.frame(width: 28, height: 28)
	}
}

struct AppHoverButtonStyle: ButtonStyle {
	var isActive = false
	var isSelected = false
	var baseOpacity = 0.0
	var cornerRadius: CGFloat = 7
	var backgroundInset: CGFloat = 0

	func makeBody(configuration: Configuration) -> some View {
		AppHoverButtonBody(
			configuration: configuration,
			isActive: isActive,
			isSelected: isSelected,
			baseOpacity: baseOpacity,
			cornerRadius: cornerRadius,
			backgroundInset: backgroundInset
		)
	}

	private struct AppHoverButtonBody: View {
		let configuration: ButtonStyle.Configuration
		let isActive: Bool
		let isSelected: Bool
		let baseOpacity: Double
		let cornerRadius: CGFloat
		let backgroundInset: CGFloat
		@State private var isHovered = false

		private var backgroundColor: Color {
			if isSelected {
				return Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.16)
			}
			if configuration.isPressed { return Color.primary.opacity(0.16) }
			if isActive { return Color.primary.opacity(0.14) }
			if isHovered { return Color.primary.opacity(0.1) }
			return Color.primary.opacity(baseOpacity)
		}

		var body: some View {
			configuration.label
				.background {
					RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
						.fill(backgroundColor)
						.padding(backgroundInset)
				}
				.onHover { isHovered = $0 }
				.animation(.easeOut(duration: 0.1), value: isHovered)
				.animation(.easeOut(duration: 0.08), value: configuration.isPressed)
				.animation(.easeOut(duration: 0.1), value: isActive)
				.animation(.easeOut(duration: 0.1), value: isSelected)
		}
	}
}

struct IconButton: View {
	let icon: AppIcon
	let usesTitlebarBackground: Bool
	let iconSize: CGFloat
	let action: () -> Void

	init(
		icon: AppIcon,
		usesTitlebarBackground: Bool = false,
		iconSize: CGFloat = 18,
		action: @escaping () -> Void
	) {
		self.icon = icon
		self.usesTitlebarBackground = usesTitlebarBackground
		self.iconSize = iconSize
		self.action = action
	}

	var body: some View {
		Button(action: action) {
			AppIconImage(icon: icon, size: iconSize)
				.frame(width: 30, height: 30)
				.contentShape(.rect)
		}
		.buttonStyle(AppHoverButtonStyle(cornerRadius: 6))
		.frame(width: 30, height: 30)
		.background {
			if usesTitlebarBackground {
				TitlebarMaterialBackground()
			}
		}
	}
}

struct BrowserTab: View {
	let accessibilityIdentifier: String
	let closeAccessibilityIdentifier: String
	let title: String
	var titleIsHidden = false
	let width: CGFloat
	let isActive: Bool
	let isDirty: Bool
	let isPinned: Bool
	let isPreview: Bool
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

	private var accessibleTitle: String {
		titleIsHidden ? "Hidden entry" : title
	}

	private var tabButton: some View {
		Button(action: activate) {
			HStack(spacing: 6) {
				if isPinned {
					Image(systemName: "pin.fill")
						.font(.system(size: 9, weight: .semibold))
						.foregroundStyle(.secondary)
				}

				if isDirty {
					Circle()
						.fill(.secondary)
						.frame(width: 6, height: 6)
				}

				Text(title)
					.italic(isPreview)
					.lineLimit(1)
					.redacted(reason: titleIsHidden ? .placeholder : [])
					.frame(maxWidth: .infinity, alignment: .leading)
					.foregroundStyle(isActive || isHovered ? Color.primary : Color.secondary)
			}
			.padding(.leading, 9)
			.padding(.trailing, 6)
			.frame(width: width, height: 30)
			.contentShape(.rect)
			.mask { titleMask }
		}
		.buttonStyle(.plain)
		.accessibilityElement(children: .ignore)
		.accessibilityAddTraits(.isButton)
		.accessibilityIdentifier(accessibilityIdentifier)
		.accessibilityLabel(accessibleTitle)
		.accessibilityValue(
			(isPinned ? "Pinned, " : "")
				+ (isPreview ? "Preview, " : "")
				+ (isDirty ? "Unsaved changes" : "Saved")
		)
	}

	var body: some View {
		tabButton
			.overlay(alignment: .trailing) {
				if showsCloseButton {
					TabIconButton(icon: .close, iconSize: 12, action: close)
						.padding(.trailing, 1)
						.accessibilityIdentifier(closeAccessibilityIdentifier)
						.accessibilityLabel("Close \(accessibleTitle)")
						.help("Close \(accessibleTitle)")
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
