import AppKit
import SwiftUI

private final class LabAppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApp.activate(ignoringOtherApps: true)
	}
}

@main
struct SidebarButtonLabApp: App {
	@NSApplicationDelegateAdaptor(LabAppDelegate.self) private var appDelegate

	var body: some Scene {
		WindowGroup("Sidebar design lab") {
			SidebarDesignLab()
		}
		.defaultSize(width: 1_280, height: 900)
	}
}

private enum LabPage: String, CaseIterable, Identifiable {
	case footer = "Account footer"
	case diaryPicker = "Diary picker"
	case pickerDetails = "Picker menu"
	case topics = "Topics"

	var id: Self { self }
}

private enum PickerMenuVariant: String, CaseIterable, Identifiable {
	case dividedHover
	case seamlessHover
	case dividedAlways
	case seamlessAlways
	case selectedAlways

	var id: Self { self }

	var title: String {
		switch self {
		case .dividedHover: "Divider + hover settings"
		case .seamlessHover: "Seamless + hover settings"
		case .dividedAlways: "Divider + visible settings"
		case .seamlessAlways: "Seamless + visible settings"
		case .selectedAlways: "Selected always, rest on hover"
		}
	}

	var score: Int {
		switch self {
		case .dividedHover: 22
		case .seamlessHover: 24
		case .dividedAlways: 23
		case .seamlessAlways: 25
		case .selectedAlways: 24
		}
	}

	var showsSeparator: Bool {
		switch self {
		case .dividedHover, .dividedAlways: true
		case .seamlessHover, .seamlessAlways, .selectedAlways: false
		}
	}

	var settingsMode: PickerSettingsMode {
		switch self {
		case .dividedHover, .seamlessHover: .hover
		case .dividedAlways, .seamlessAlways: .always
		case .selectedAlways: .selectedAlways
		}
	}

	var verdict: String {
		switch self {
		case .dividedHover:
			"The divider makes the selector a clear header. Hover-only settings keep the menu calm but are easier to miss."
		case .seamlessHover:
			"The navigation flows directly from the selector. Secondary actions stay quiet until the pointer reaches a diary."
		case .dividedAlways:
			"The boundary is clear and every diary action is discoverable. Repeated gears add visual noise."
		case .seamlessAlways:
			"The cleanest structure with no extra rule. Visible gears work for mouse, keyboard, and accessibility users."
		case .selectedAlways:
			"The current diary keeps an obvious settings action. Other rows reveal theirs on hover, which balances clarity and density."
		}
	}
}

private enum PickerSettingsMode {
	case hover
	case always
	case selectedAlways
}

private enum DiaryPickerVariant: String, CaseIterable, Identifiable {
	case contextRow
	case compactRow
	case sectionLabel
	case nativeButton
	case breadcrumb
	case colorIdentity
	case entryMetadata
	case prominentCard
	case centeredTitle

	var id: Self { self }

	var title: String {
		switch self {
		case .contextRow: "Current diary"
		case .compactRow: "Compact row"
		case .sectionLabel: "Labeled section"
		case .nativeButton: "Native menu button"
		case .breadcrumb: "Breadcrumb"
		case .colorIdentity: "Color identity"
		case .entryMetadata: "Diary metadata"
		case .prominentCard: "Prominent card"
		case .centeredTitle: "Centered title"
		}
	}

	var score: Int {
		switch self {
		case .contextRow: 24
		case .compactRow: 23
		case .sectionLabel: 22
		case .nativeButton: 25
		case .breadcrumb: 18
		case .colorIdentity: 21
		case .entryMetadata: 20
		case .prominentCard: 17
		case .centeredTitle: 19
		}
	}

	var verdict: String {
		switch self {
		case .contextRow:
			"Names the object and its role without adding account details. The 44 pt row remains easy to target."
		case .compactRow:
			"Uses little vertical space and still reads as a switcher. Best when the diary name is enough context."
		case .sectionLabel:
			"The label removes ambiguity at a glance. It costs height and repeats information for frequent users."
		case .nativeButton:
			"Looks and behaves like a standard macOS menu control. The border adds weight above the navigation list."
		case .breadcrumb:
			"Explains hierarchy, but thingsdiary is not a real parent destination. The extra path is mostly decorative."
		case .colorIdentity:
			"A stable diary color speeds recognition. It only works if color is part of the diary model and never carries meaning alone."
		case .entryMetadata:
			"Uses the second line for useful state instead of a generic label. Counts can become noisy and change often."
		case .prominentCard:
			"Makes the current diary unmistakable. The card competes with the selected navigation row below it."
		case .centeredTitle:
			"Feels like a navigation title and keeps the sidebar calm. Long diary names make the centered layout fragile."
		}
	}
}

private enum DemoAppearance: String, CaseIterable, Identifiable {
	case system = "System"
	case light = "Light"
	case dark = "Dark"

	var id: Self { self }

	var colorScheme: ColorScheme? {
		switch self {
		case .system: nil
		case .light: .light
		case .dark: .dark
		}
	}
}

private enum TopicState: String, CaseIterable, Identifiable {
	case populated = "2 topics"
	case empty = "Empty"
	case collapsed = "Collapsed"

	var id: Self { self }
}

private enum FooterVariant: String, CaseIterable, Identifiable {
	case accountRow
	case diarySwitcher
	case twoLineIdentity
	case richPopover
	case topContextUtilities
	case topContextAccount
	case stackedTopContexts

	var id: Self { self }

	var title: String {
		switch self {
		case .accountRow: "Account row"
		case .diarySwitcher: "Diary switcher"
		case .twoLineIdentity: "Two-line identity"
		case .richPopover: "Rich popover"
		case .topContextUtilities: "Top diary + utilities"
		case .topContextAccount: "Top diary + account menu"
		case .stackedTopContexts: "Account + diary at top"
		}
	}

	var score: Int {
		switch self {
		case .accountRow: 24
		case .diarySwitcher: 21
		case .twoLineIdentity: 19
		case .richPopover: 17
		case .topContextUtilities: 22
		case .topContextAccount: 24
		case .stackedTopContexts: 20
		}
	}

	var verdict: String {
		switch self {
		case .accountRow:
			"The clearest account-level trigger. The menu can hold diaries, Settings, and Sign Out without turning the footer into a toolbar."
		case .diarySwitcher:
			"Best when people switch diaries often. Settings and Sign Out are less expected inside a diary control."
		case .twoLineIdentity:
			"Explains both account and current diary. It needs careful truncation at the 180 pt minimum width."
		case .richPopover:
			"Scales to many diaries and can add search. More custom behavior means more keyboard and VoiceOver work."
		case .topContextUtilities:
			"Makes the current diary the page context. Settings and Sign Out stay visible, but the footer starts to resemble a toolbar."
		case .topContextAccount:
			"Separates diary navigation from account actions. The username opens a small menu with Settings and Sign Out."
		case .stackedTopContexts:
			"Keeps account and diary context above navigation, with no user control in the footer. The two Personal labels make their roles harder to scan."
		}
	}
}

private enum TopicsVariant: String, CaseIterable, Identifiable {
	case balanced
	case nativeDisclosure
	case finderLabel
	case navigationWeight
	case emptyCoach

	var id: Self { self }

	var title: String {
		switch self {
		case .balanced: "Balanced header"
		case .nativeDisclosure: "Native disclosure"
		case .finderLabel: "Finder-style label"
		case .navigationWeight: "Navigation weight"
		case .emptyCoach: "Empty-state coach"
		}
	}

	var score: Int {
		switch self {
		case .nativeDisclosure: 25
		case .balanced: 24
		case .finderLabel: 22
		case .emptyCoach: 21
		case .navigationWeight: 18
		}
	}

	var verdict: String {
		switch self {
		case .balanced:
			"Matches the 30 pt row rhythm. The chevron stays visible; Add appears on hover without shifting the title."
		case .nativeDisclosure:
			"The strongest macOS convention. A leading disclosure control shows hierarchy; Add stays on the trailing edge."
		case .finderLabel:
			"A quieter section boundary for long sidebars. The smaller uppercase label is familiar but less prominent."
		case .navigationWeight:
			"Strong alignment with the rows above. The icon makes the header look a little too much like a destination."
		case .emptyCoach:
			"Adds one line of explanation only when the list is empty. Useful for onboarding, unnecessary after the first topic."
		}
	}
}

private struct SidebarDesignLab: View {
	@State private var page = LabPage.footer
	@State private var appearance = DemoAppearance.system
	@State private var topicState = TopicState.populated

	private let columns = [GridItem(.adaptive(minimum: 350, maximum: 390), spacing: 18)]

	var body: some View {
		VStack(spacing: 0) {
			header
			Divider()

			ScrollView {
				LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
					switch page {
					case .footer:
						ForEach(FooterVariant.allCases) { variant in
							CandidateCard(
								title: variant.title,
								score: variant.score,
								verdict: variant.verdict
							) {
								FooterSample(variant: variant)
							}
						}
					case .diaryPicker:
						ForEach(DiaryPickerVariant.allCases) { variant in
							CandidateCard(
								title: variant.title,
								score: variant.score,
								verdict: variant.verdict
							) {
								DiaryPickerSample(variant: variant)
							}
						}
					case .pickerDetails:
						ForEach(PickerMenuVariant.allCases) { variant in
							CandidateCard(
								title: variant.title,
								score: variant.score,
								verdict: variant.verdict
							) {
								PickerMenuSample(variant: variant)
							}
						}
					case .topics:
						ForEach(TopicsVariant.allCases) { variant in
							CandidateCard(
								title: variant.title,
								score: variant.score,
								verdict: variant.verdict
							) {
								TopicsSample(variant: variant, state: topicState)
							}
						}
					}
				}
				.padding(20)
			}

			Divider()
			footer
		}
		.frame(minWidth: 980, minHeight: 720)
		.preferredColorScheme(appearance.colorScheme)
	}

	private var header: some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 3) {
				Text("Sidebar design lab")
					.font(.title2.weight(.semibold))
				Text(pageSubtitle)
					.font(.callout)
					.foregroundStyle(.secondary)
			}

			Spacer()

			if page == .topics {
				Picker("State", selection: $topicState) {
					ForEach(TopicState.allCases) { state in
						Text(state.rawValue).tag(state)
					}
				}
				.pickerStyle(.segmented)
				.frame(width: 230)
			}

			Picker("Page", selection: $page) {
				ForEach(LabPage.allCases) { page in
					Text(page.rawValue).tag(page)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 490)

			Picker("Appearance", selection: $appearance) {
				ForEach(DemoAppearance.allCases) { option in
					Text(option.rawValue).tag(option)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 210)
		}
		.padding(20)
	}

	private var pageSubtitle: String {
		switch page {
		case .footer: "Seven account-footer patterns. Hover and click inside each sample."
		case .diaryPicker: "Nine top-of-sidebar diary selectors. No account actions or footer controls."
		case .pickerDetails:
			"Five refinements of the selected menu. Every dropdown overlays navigation and dismisses after selection or an outside click."
		case .topics: "Five Topics patterns. Change the list state to compare behavior."
		}
	}

	private var footer: some View {
		HStack {
			Label(footerSummary, systemImage: "checkmark.seal")
			Spacer()
			Text("Score /25: HIG · discovery · accessibility · hierarchy · implementation")
				.foregroundStyle(.secondary)
		}
		.font(.callout.weight(.medium))
		.padding(.horizontal, 20)
		.frame(height: 46)
	}

	private var footerSummary: String {
		switch page {
		case .footer: "Account footer lab: 7 patterns"
		case .diaryPicker: "Diary picker lab: 9 patterns"
		case .pickerDetails: "Picker menu lab: 5 patterns"
		case .topics: "Topics lab: 5 patterns"
		}
	}
}

private struct CandidateCard<Sample: View>: View {
	let title: String
	let score: Int
	let verdict: String
	@ViewBuilder let sample: () -> Sample

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .firstTextBaseline) {
				Text(title).font(.headline)
				Spacer()
				Text("\(score) / 25")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}

			sample()
				.frame(height: 340)

			Text(verdict)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(3, reservesSpace: true)
		}
		.padding(14)
		.background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color.primary.opacity(0.1), lineWidth: 1)
		}
	}
}

private struct DiaryPickerSample: View {
	let variant: DiaryPickerVariant
	@State private var menuOpen = false

	var body: some View {
		VStack(spacing: 0) {
			MiniWindowBar(title: "thingsdiary")
			Divider()

			VStack(spacing: 6) {
				Button {
					menuOpen.toggle()
				} label: {
					pickerLabel
				}
				.buttonStyle(.plain)
				.help("Switch Diary")

				if menuOpen {
					diaryMenu
				}
			}
			.padding(variant == .sectionLabel ? 8 : 6)

			Divider()

			ScrollView {
				VStack(spacing: 4) {
					SidebarRow("Entries", icon: "note.text", selected: true, count: "12")
					SidebarRow("Bookmarks", icon: "bookmark")
					MiniTopics()
					SidebarRow("Archive", icon: "archivebox")
					SidebarRow("Trash", icon: "trash")
				}
				.padding(10)
			}
		}
		.miniSidebarChrome()
	}

	@ViewBuilder
	private var pickerLabel: some View {
		switch variant {
		case .contextRow:
			selectorRow(
				icon: "book.closed.fill",
				title: "Personal",
				subtitle: "Current diary"
			)
		case .compactRow:
			selectorRow(
				icon: "book.closed",
				title: "Personal",
				subtitle: nil,
				minHeight: 34
			)
		case .sectionLabel:
			VStack(alignment: .leading, spacing: 4) {
				Text("DIARY")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 8)
				selectorRow(
					icon: "book.closed",
					title: "Personal",
					subtitle: nil,
					minHeight: 34
				)
			}
		case .nativeButton:
			selectorRow(
				icon: "book.closed",
				title: "Personal",
				subtitle: nil,
				minHeight: 36,
				background: Color.primary.opacity(0.08)
			)
		case .breadcrumb:
			HStack(spacing: 6) {
				Text("thingsdiary")
					.foregroundStyle(.secondary)
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
				Text("Personal").fontWeight(.semibold)
				Spacer(minLength: 6)
				switcherGlyph
			}
			.font(.callout)
			.padding(.horizontal, 8)
			.frame(maxWidth: .infinity, minHeight: 38)
			.contentShape(.rect)
		case .colorIdentity:
			selectorRow(
				icon: "circle.fill",
				title: "Personal",
				subtitle: "Current diary",
				iconColor: .purple
			)
		case .entryMetadata:
			selectorRow(
				icon: "book.pages.fill",
				title: "Personal",
				subtitle: "12 entries · Updated today"
			)
		case .prominentCard:
			selectorRow(
				icon: "book.closed.fill",
				title: "Personal",
				subtitle: "Daily notes",
				minHeight: 50,
				background: .accentColor.opacity(0.13)
			)
			.overlay {
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
			}
		case .centeredTitle:
			ZStack {
				HStack {
					Spacer()
					Label("Personal", systemImage: "book.closed")
						.font(.callout.weight(.semibold))
					Spacer()
				}
				HStack {
					Spacer()
					switcherGlyph
				}
			}
			.padding(.horizontal, 8)
			.frame(maxWidth: .infinity, minHeight: 38)
			.contentShape(.rect)
		}
	}

	private func selectorRow(
		icon: String,
		title: String,
		subtitle: String?,
		minHeight: CGFloat = 44,
		background: Color = .clear,
		iconColor: Color = .accentColor
	) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.font(icon == "circle.fill" ? .system(size: 10) : .body)
				.frame(width: 18)
				.foregroundStyle(iconColor)
			VStack(alignment: .leading, spacing: 0) {
				Text(title).font(.callout.weight(.semibold)).lineLimit(1)
				if let subtitle {
					Text(subtitle)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
			Spacer(minLength: 6)
			switcherGlyph
		}
		.padding(.horizontal, 8)
		.frame(maxWidth: .infinity, minHeight: minHeight)
		.contentShape(.rect)
		.background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
	}

	private var switcherGlyph: some View {
		Image(systemName: "chevron.up.chevron.down")
			.font(.caption2.weight(.semibold))
			.foregroundStyle(.secondary)
	}

	private var diaryMenu: some View {
		VStack(alignment: .leading, spacing: 2) {
			diaryChoice("Personal", selected: true)
			diaryChoice("Travel")
			diaryChoice("Research")
		}
		.menuPanel()
	}

	private func diaryChoice(_ title: String, selected: Bool = false) -> some View {
		HStack(spacing: 7) {
			if selected {
				Image(systemName: "checkmark")
					.frame(width: 15)
			} else {
				Color.clear.frame(width: 15, height: 1)
			}
			Text(title)
			Spacer()
		}
		.font(.callout)
		.padding(.horizontal, 7)
		.frame(maxWidth: .infinity, minHeight: 25)
	}
}

private struct PickerMenuSample: View {
	let variant: PickerMenuVariant
	@State private var menuOpen = true
	@State private var selectedDiary = "Personal"
	@State private var hoveredDiary: String?

	private let diaries = ["Personal", "Travel", "Research"]

	var body: some View {
		ZStack(alignment: .top) {
			sidebar

			if menuOpen {
				Color.black.opacity(0.001)
					.contentShape(.rect)
					.onTapGesture { menuOpen = false }
					.zIndex(1)

				VStack(spacing: 0) {
					dropdown
					Spacer(minLength: 0)
				}
				.padding(.top, variant.showsSeparator ? 88 : 83)
				.padding(.horizontal, 10)
				.zIndex(2)
			}
		}
		.miniSidebarChrome()
	}

	private var sidebar: some View {
		VStack(spacing: 0) {
			MiniWindowBar(title: "thingsdiary")
			Divider()

			Button {
				menuOpen.toggle()
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "book.closed")
						.frame(width: 16)
						.symbolRenderingMode(.monochrome)
						.foregroundStyle(Color(nsColor: .secondaryLabelColor))
					Text(selectedDiary).font(.callout.weight(.semibold))
					Spacer(minLength: 6)
					Image(systemName: "chevron.up.chevron.down")
						.font(.caption2.weight(.semibold))
						.frame(width: 18)
						.foregroundStyle(.secondary)
				}
				.padding(.horizontal, 11)
				.frame(maxWidth: .infinity, minHeight: 36)
				.contentShape(.rect)
				.background(
					Color.primary.opacity(0.08),
					in: RoundedRectangle(cornerRadius: 8, style: .continuous)
				)
			}
			.buttonStyle(.plain)
			.help("Switch Diary")
			.padding(
				EdgeInsets(
					top: 6,
					leading: 6,
					bottom: variant.showsSeparator ? 6 : 2,
					trailing: 6
				)
			)

			if variant.showsSeparator {
				Divider()
			}

			ScrollView {
				VStack(spacing: 4) {
					SidebarRow("Entries", icon: "note.text", selected: true, count: "12")
					SidebarRow("Bookmarks", icon: "bookmark")
					MiniTopics()
					SidebarRow("Archive", icon: "archivebox")
					SidebarRow("Trash", icon: "trash")
				}
				.padding(
					EdgeInsets(
						top: variant.showsSeparator ? 10 : 4,
						leading: 10,
						bottom: 10,
						trailing: 10
					)
				)
			}
		}
	}

	private var dropdown: some View {
		VStack(spacing: 2) {
			ForEach(diaries, id: \.self) { diary in
				diaryRow(diary)
			}

			Divider().padding(.vertical, 3)

			Button {
				menuOpen = false
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "plus")
						.frame(width: 16)
					Text("New Diary…")
					Spacer()
				}
				.padding(.horizontal, 7)
				.frame(maxWidth: .infinity, minHeight: 28)
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
		}
		.padding(6)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
		.overlay {
			RoundedRectangle(cornerRadius: 9, style: .continuous)
				.stroke(Color.primary.opacity(0.14), lineWidth: 1)
		}
		.shadow(color: .black.opacity(0.18), radius: 10, y: 4)
	}

	private func diaryRow(_ diary: String) -> some View {
		let isSelected = diary == selectedDiary
		let settingsVisible = showsSettings(for: diary, selected: isSelected)

		return HStack(spacing: 2) {
			Button {
				selectedDiary = diary
				menuOpen = false
			} label: {
				HStack(spacing: 8) {
					if isSelected {
						Image(systemName: "checkmark").frame(width: 16)
					} else {
						Color.clear.frame(width: 16, height: 1)
					}
					Text(diary)
					Spacer()
				}
				.padding(.horizontal, 7)
				.frame(maxWidth: .infinity, minHeight: 28)
				.contentShape(.rect)
			}
			.buttonStyle(.plain)

			Button {
			} label: {
				Image(systemName: "gearshape")
					.frame(width: 24, height: 24)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.opacity(settingsVisible ? 1 : 0)
			.allowsHitTesting(settingsVisible)
			.accessibilityHidden(!settingsVisible)
			.help("Settings for \(diary)")
		}
		.onHover { hovering in
			hoveredDiary = hovering ? diary : nil
		}
	}

	private func showsSettings(for diary: String, selected: Bool) -> Bool {
		switch variant.settingsMode {
		case .hover:
			hoveredDiary == diary
		case .always:
			true
		case .selectedAlways:
			selected || hoveredDiary == diary
		}
	}
}

private struct FooterSample: View {
	let variant: FooterVariant
	@State private var menuOpen = true
	@State private var diariesExpanded = true

	private var usesTopDiaryContext: Bool {
		variant == .topContextUtilities || variant == .topContextAccount
			|| variant == .stackedTopContexts
	}

	private var showsFooter: Bool {
		variant != .stackedTopContexts
	}

	var body: some View {
		VStack(spacing: 0) {
			MiniWindowBar(title: usesTopDiaryContext ? "thingsdiary" : "Personal")
			Divider()
			if usesTopDiaryContext {
				if variant == .stackedTopContexts {
					topAccountContext
					Divider()
				}
				topDiaryContext
				Divider()
			}

			ScrollView {
				VStack(spacing: 4) {
					SidebarRow("Entries", icon: "note.text", selected: true, count: "12")
					SidebarRow("Bookmarks", icon: "bookmark")
					MiniTopics()
					SidebarRow("Archive", icon: "archivebox")
					SidebarRow("Trash", icon: "trash")
				}
				.padding(10)
			}

			if showsFooter {
				Divider()
				footerControl
					.padding(8)
			}
		}
		.miniSidebarChrome()
	}

	@ViewBuilder
	private var footerControl: some View {
		switch variant {
		case .accountRow:
			menuPreview {
				triggerRow(title: "Mikhail", subtitle: nil, icon: "person.crop.circle")
			}
		case .diarySwitcher:
			menuPreview(compact: true) {
				triggerRow(title: "Personal", subtitle: nil, icon: "book.closed")
			}
		case .twoLineIdentity:
			menuPreview {
				triggerRow(title: "Mikhail", subtitle: "Personal", icon: "person.crop.circle.fill")
			}
		case .richPopover:
			VStack(spacing: 6) {
				if menuOpen { richDiaryList }
				Button {
					menuOpen.toggle()
				} label: {
					triggerRow(title: "Personal", subtitle: "mikhail@example.com", icon: "book.closed.fill")
				}
				.buttonStyle(.plain)
			}
		case .topContextUtilities:
			HStack(spacing: 6) {
				Button("Settings…", systemImage: "gearshape") {}
				Spacer()
				Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {}
			}
			.buttonStyle(.borderless)
			.controlSize(.small)
		case .topContextAccount:
			accountActionsPreview
		case .stackedTopContexts:
			EmptyView()
		}
	}

	private var topAccountContext: some View {
		HStack(spacing: 8) {
			Image(systemName: "book.closed")
				.frame(width: 18)
			VStack(alignment: .leading, spacing: 1) {
				Text("Personal").font(.callout.weight(.semibold))
				Text("mikhail@example.com").font(.caption2).foregroundStyle(.secondary)
			}
			Spacer()
			Image(systemName: "chevron.up.chevron.down")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 10)
		.frame(maxWidth: .infinity, minHeight: 44)
	}

	private var topDiaryContext: some View {
		Button {
		} label: {
			HStack(spacing: 8) {
				Image(systemName: "book.closed.fill")
					.frame(width: 18)
					.foregroundStyle(.tint)
				VStack(alignment: .leading, spacing: 1) {
					Text("Personal").font(.callout.weight(.semibold))
					Text("Current diary").font(.caption2).foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "chevron.up.chevron.down")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 10)
			.frame(maxWidth: .infinity, minHeight: 44)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.help("Switch Diary")
	}

	private var accountActionsPreview: some View {
		VStack(spacing: 6) {
			if menuOpen {
				VStack(alignment: .leading, spacing: 2) {
					menuRow("Settings…", icon: "gearshape")
					Divider().padding(.vertical, 3)
					menuRow("Sign Out", icon: "rectangle.portrait.and.arrow.right")
				}
				.menuPanel()
			}

			Button {
				menuOpen.toggle()
			} label: {
				triggerRow(title: "Mikhail", subtitle: nil, icon: "person.crop.circle")
			}
			.buttonStyle(.plain)
		}
	}

	private func menuPreview<Trigger: View>(
		compact: Bool = false,
		@ViewBuilder trigger: () -> Trigger
	) -> some View {
		VStack(spacing: 6) {
			if menuOpen {
				VStack(alignment: .leading, spacing: 2) {
					if !compact {
						Text("mikhail@example.com")
							.font(.caption)
							.foregroundStyle(.secondary)
							.padding(.horizontal, 8)
						Divider().padding(.vertical, 3)
					}

					Button {
						diariesExpanded.toggle()
					} label: {
						menuRow(
							"Diaries",
							icon: "book.closed",
							trailing: diariesExpanded ? "chevron.down" : "chevron.right"
						)
					}
					.buttonStyle(.plain)

					if diariesExpanded {
						menuRow("Personal", icon: "checkmark", indented: true)
						menuRow("Travel", icon: nil, indented: true)
						menuRow("All Diaries…", icon: nil, indented: true)
					}

					Divider().padding(.vertical, 3)
					menuRow("Settings…", icon: "gearshape")
					Divider().padding(.vertical, 3)
					menuRow("Sign Out", icon: "rectangle.portrait.and.arrow.right")
				}
				.menuPanel()
			}

			Button {
				menuOpen.toggle()
			} label: {
				trigger()
			}
			.buttonStyle(.plain)
		}
	}

	private var richDiaryList: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text("Switch diary").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
			TextField("Search diaries", text: .constant(""))
				.textFieldStyle(.roundedBorder)
			menuRow("Personal", icon: "checkmark")
			menuRow("Travel", icon: nil)
			menuRow("Research", icon: nil)
			Divider().padding(.vertical, 3)
			menuRow("Settings…", icon: "gearshape")
			menuRow("Sign Out", icon: "rectangle.portrait.and.arrow.right")
		}
		.menuPanel()
	}

	private func triggerRow(title: String, subtitle: String?, icon: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon).font(subtitle == nil ? .body : .title3).frame(width: 20)
			VStack(alignment: .leading, spacing: 0) {
				Text(title).font(.callout.weight(.medium)).lineLimit(1)
				if let subtitle {
					Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
				}
			}
			Spacer(minLength: 6)
			Image(systemName: "chevron.up.chevron.down")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 8)
		.frame(maxWidth: .infinity, minHeight: subtitle == nil ? 32 : 40)
		.contentShape(.rect)
		.background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
	}

	private func menuRow(
		_ title: String,
		icon: String?,
		trailing: String? = nil,
		indented: Bool = false
	) -> some View {
		HStack(spacing: 7) {
			if indented { Spacer().frame(width: 14) }
			if let icon { Image(systemName: icon).frame(width: 15) } else { Spacer().frame(width: 15) }
			Text(title)
			Spacer()
			if let trailing { Image(systemName: trailing).font(.caption2) }
		}
		.font(.callout)
		.padding(.horizontal, 7)
		.frame(maxWidth: .infinity, minHeight: 25)
		.contentShape(.rect)
	}
}

private struct TopicsSample: View {
	let variant: TopicsVariant
	let state: TopicState
	@State private var manualExpanded = true
	@State private var hovered = false

	private var expanded: Bool {
		state == .collapsed ? false : manualExpanded
	}

	private var empty: Bool { state == .empty }

	var body: some View {
		VStack(spacing: 0) {
			MiniWindowBar()
			Divider()

			VStack(alignment: .leading, spacing: 4) {
				SidebarRow("Entries", icon: "note.text", selected: true, count: "12")
				SidebarRow("Bookmarks", icon: "bookmark")
				Divider().padding(.vertical, 4)
				topicsBlock
				Divider().padding(.vertical, 4)
				SidebarRow("Archive", icon: "archivebox")
				SidebarRow("Trash", icon: "trash")
				Spacer()
			}
			.padding(10)
		}
		.miniSidebarChrome()
	}

	private var topicsBlock: some View {
		VStack(alignment: .leading, spacing: 3) {
			header
			if expanded {
				if empty {
					if variant != .navigationWeight {
						emptyContent
					}
				} else {
					SidebarRow("Work", icon: "circle.fill", iconColor: .blue)
					SidebarRow("Ideas", icon: "circle.fill", iconColor: .orange)
				}
			}
		}
	}

	@ViewBuilder
	private var header: some View {
		switch variant {
		case .balanced, .emptyCoach:
			balancedHeader(font: .callout.weight(.semibold), uppercase: false, showIcon: false)
		case .nativeDisclosure:
			nativeDisclosureHeader
		case .finderLabel:
			balancedHeader(font: .caption2.weight(.semibold), uppercase: true, showIcon: false)
		case .navigationWeight:
			balancedHeader(font: .body, uppercase: false, showIcon: true)
		}
	}

	private var nativeDisclosureHeader: some View {
		HStack(spacing: 7) {
			Button {
				manualExpanded.toggle()
			} label: {
				Image(systemName: expanded ? "chevron.down" : "chevron.right")
					.frame(width: 16, height: 20)
			}
			.buttonStyle(.plain)
			.help(expanded ? "Collapse Topics" : "Expand Topics")

			Text("Topics").font(.callout.weight(.semibold))
			Spacer()

			Button {
			} label: {
				Image(systemName: "plus")
					.frame(width: 18, height: 20)
					.opacity(hovered || empty ? 1 : 0)
			}
			.buttonStyle(.plain)
			.help("New Topic")
			.accessibilityLabel("New Topic")
		}
		.padding(.horizontal, 7)
		.frame(minHeight: 30)
		.contentShape(.rect)
		.onHover { hovered = $0 }
	}

	private func balancedHeader(font: Font, uppercase: Bool, showIcon: Bool) -> some View {
		HStack(spacing: 7) {
			if showIcon {
				Image(systemName: "tag").frame(width: 16).foregroundStyle(.tint)
			}
			Text(uppercase ? "TOPICS" : "Topics")
				.font(font)
				.foregroundStyle(variant == .finderLabel ? .secondary : .primary)
			Spacer()

			Button {
			} label: {
				Image(systemName: "plus")
					.frame(width: 18, height: 20)
					.opacity(hovered || empty ? 1 : 0)
			}
			.buttonStyle(.plain)
			.help("New Topic")
			.accessibilityLabel("New Topic")

			if variant != .navigationWeight || !empty {
				Button {
					manualExpanded.toggle()
				} label: {
					Image(systemName: expanded ? "chevron.down" : "chevron.right")
						.frame(width: 18, height: 20)
				}
				.buttonStyle(.plain)
				.help(expanded ? "Collapse Topics" : "Expand Topics")
			}
		}
		.padding(.horizontal, 7)
		.frame(minHeight: variant == .finderLabel ? 28 : 30)
		.contentShape(.rect)
		.onHover { hovered = $0 }
	}

	@ViewBuilder
	private var emptyContent: some View {
		if variant == .emptyCoach {
			VStack(alignment: .leading, spacing: 7) {
				Text("Group related entries for quicker access.")
					.font(.caption)
					.foregroundStyle(.secondary)
				Button("New Topic", systemImage: "plus") {}
					.buttonStyle(.bordered)
					.controlSize(.small)
			}
			.padding(.horizontal, 7)
			.padding(.bottom, 5)
		} else {
			Button {
			} label: {
				HStack(spacing: 8) {
					Image(systemName: "plus.circle")
					Text("New Topic")
					Spacer()
				}
				.padding(.horizontal, 7)
				.frame(maxWidth: .infinity, minHeight: 32)
				.contentShape(.rect)
				.foregroundStyle(.tint)
			}
			.buttonStyle(.plain)
		}
	}
}

private struct MiniWindowBar: View {
	var title = "Personal"

	var body: some View {
		HStack(spacing: 7) {
			Circle().fill(.red.opacity(0.8)).frame(width: 9, height: 9)
			Circle().fill(.yellow.opacity(0.8)).frame(width: 9, height: 9)
			Circle().fill(.green.opacity(0.8)).frame(width: 9, height: 9)
			Text(title)
				.font(.caption.weight(.medium))
				.foregroundStyle(.secondary)
			Spacer()
		}
		.padding(.horizontal, 10)
		.frame(height: 34)
		.background(.bar)
	}
}

private struct MiniTopics: View {
	var body: some View {
		VStack(spacing: 3) {
			HStack {
				Text("Topics").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
				Spacer()
				Image(systemName: "chevron.down")
					.font(.caption2)
					.frame(width: 18)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 7)
			.frame(height: 26)
			SidebarRow("Work", icon: "circle.fill", iconColor: .blue)
		}
	}
}

private struct SidebarRow: View {
	let title: String
	let icon: String
	var selected = false
	var count: String?
	var iconColor: Color?

	init(
		_ title: String,
		icon: String,
		selected: Bool = false,
		count: String? = nil,
		iconColor: Color? = nil
	) {
		self.title = title
		self.icon = icon
		self.selected = selected
		self.count = count
		self.iconColor = iconColor
	}

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: icon)
				.font(icon == "circle.fill" ? .system(size: 7) : .body)
				.frame(width: 16)
				.foregroundStyle(iconColor ?? Color.accentColor)
			Text(title)
			Spacer()
			if let count {
				Text(count)
					.font(.caption.monospacedDigit())
					.frame(width: 18)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.horizontal, 7)
		.frame(maxWidth: .infinity, minHeight: 30)
		.background(
			selected ? Color.accentColor.opacity(0.2) : Color.clear,
			in: RoundedRectangle(cornerRadius: 7)
		)
	}
}

extension View {
	fileprivate func menuPanel() -> some View {
		padding(6)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
			.overlay {
				RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.12))
			}
			.shadow(color: .black.opacity(0.12), radius: 8, y: 3)
	}

	fileprivate func miniSidebarChrome() -> some View {
		background(.regularMaterial)
			.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
			.overlay {
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.stroke(Color.primary.opacity(0.14), lineWidth: 1)
			}
	}
}
