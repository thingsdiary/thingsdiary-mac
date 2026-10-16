import AppKit
import SwiftUI
import ThingsDiaryClient

private struct MenuMaterialBackground: NSViewRepresentable {
	func makeNSView(context: Context) -> NSVisualEffectView {
		let view = NSVisualEffectView()
		view.blendingMode = .withinWindow
		view.material = .menu
		view.state = .followsWindowActiveState
		return view
	}

	func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct EntryDropTargetFramesKey: PreferenceKey {
	static var defaultValue: [EntryDropDestination: CGRect] = [:]

	static func reduce(
		value: inout [EntryDropDestination: CGRect],
		nextValue: () -> [EntryDropDestination: CGRect]
	) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}

private struct DiarySwitcherAnchorKey: PreferenceKey {
	static var defaultValue: Anchor<CGRect>?

	static func reduce(
		value: inout Anchor<CGRect>?,
		nextValue: () -> Anchor<CGRect>?
	) {
		value = nextValue() ?? value
	}
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
	static var defaultValue: CGFloat = 220

	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		let nextValue = nextValue()
		if nextValue > 0 {
			value = nextValue
		}
	}
}

struct ContentView: View {
	@Bindable var model: ThingsDiaryAppModel

	var body: some View {
		Group {
			switch model.screen {
			case .login:
				LoginView(model: model)
			case .registration:
				RegistrationView(model: model)
			case .loading:
				ProgressView("Signing in and loading diaries…")
			case .registrationComplete(let result):
				RegistrationCompleteView(model: model, result: result)
			case .diaries(let diaries):
				DiariesView(model: model, diaries: diaries)
			case .entries(let diary, let entries):
				EntriesView(model: model, diary: diary, entries: entries)
			case .error(let message):
				ErrorView(message: message, retry: model.retry)
			}
		}
		.frame(minWidth: 520, minHeight: 420)
		.sheet(
			isPresented: Binding(
				get: { model.presentation != .none },
				set: { isPresented in
					guard !isPresented else { return }
					switch model.presentation {
					case .diaryPicker:
						model.cancelDiaryPicker()
					case .diaryCreation:
						model.cancelDiaryCreation()
					case .none:
						break
					}
				}
			)
		) {
			switch model.presentation {
			case .diaryPicker:
				DiaryPickerView(model: model)
			case .diaryCreation:
				DiaryCreationView(model: model)
			case .none:
				EmptyView()
			}
		}
	}
}

private struct RegistrationCompleteView: View {
	@Bindable var model: ThingsDiaryAppModel
	let result: ThingsDiaryRegistrationResult

	var body: some View {
		Form {
			Section("Save this secret key") {
				Text(result.secretKey)
					.textSelection(.enabled)
			}

			Section("Public keys") {
				LabeledContent("Signing", value: result.publicKeys.signing)
				LabeledContent("Encryption", value: result.publicKeys.encryption)
			}

			Button("I Saved My Secret Key") {
				Task {
					await model.continueAfterRegistration()
				}
			}
			.buttonStyle(.borderedProminent)
		}
		.formStyle(.grouped)
		.padding()
	}
}

private struct LoginView: View {
	@Bindable var model: ThingsDiaryAppModel

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("thingsdiary")
				.font(.largeTitle.bold())

			Text("Sign in to load your encrypted diaries.")
				.foregroundStyle(.secondary)

			TextField("Email", text: $model.login)
				.textContentType(.emailAddress)
				.lineLimit(1)

			SecureField("Password", text: $model.password)
				.textContentType(.password)

			SecureField("Secret key (TDKV1-…)", text: $model.secretKey)

			Text("Your password, secret key, derived keys, and token are kept in memory only.")
				.font(.caption)
				.foregroundStyle(.secondary)

			HStack {
				Button("Sign In") {
					Task {
						await model.submit()
					}
				}
				.buttonStyle(.borderedProminent)
				.disabled(!model.canSubmit)

				Button("Create Account", action: model.showRegistration)
			}
		}
		.textFieldStyle(.roundedBorder)
		.frame(maxWidth: 360)
		.padding(40)
	}
}

private struct RegistrationView: View {
	@Bindable var model: ThingsDiaryAppModel

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Create Account")
				.font(.largeTitle.bold())

			Text("The app will generate a secret key. Save it before continuing.")
				.foregroundStyle(.secondary)

			TextField("Email", text: $model.login)
				.textContentType(.emailAddress)
				.lineLimit(1)

			SecureField("Password", text: $model.password)
				.textContentType(.newPassword)

			Text("Use a valid email address and at least 8 password characters.")
				.font(.caption)
				.foregroundStyle(.secondary)

			HStack {
				Button("Create Account") {
					Task {
						await model.register()
					}
				}
				.buttonStyle(.borderedProminent)
				.disabled(!model.canRegister)

				Button("Back to Sign In", action: model.showLogin)
			}
		}
		.textFieldStyle(.roundedBorder)
		.frame(maxWidth: 420)
		.padding(40)
	}
}

private struct DiariesView: View {
	@Bindable var model: ThingsDiaryAppModel
	let diaries: [ThingsDiaryDiary]

	var body: some View {
		ContentUnavailableView {
			Label(diaries.isEmpty ? "No Diaries" : "Choose a Diary", systemImage: "book.closed")
		} description: {
			Text(
				diaries.isEmpty
					? "Create a diary to start writing entries."
					: "Open one of your diaries to continue.")
		} actions: {
			if !diaries.isEmpty {
				Button("Open Diaries", action: model.showDiaryPicker)
					.buttonStyle(.borderedProminent)
			}
			Button("Create Diary", action: model.showDiaryCreation)
		}
	}
}

private struct DiaryPickerView: View {
	@Bindable var model: ThingsDiaryAppModel

	var body: some View {
		NavigationStack {
			List(model.availableDiaries) { diary in
				Button {
					model.cancelDiaryPicker()
					Task { await model.selectDiary(diary) }
				} label: {
					VStack(alignment: .leading, spacing: 4) {
						Text(diary.title)
							.font(.headline)
						if !diary.description.isEmpty {
							Text(diary.description)
								.foregroundStyle(.secondary)
						}
						Text(diary.updatedAt, format: .dateTime)
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.accessibilityIdentifier("diary.open.\(diary.id)")
				.padding(.vertical, 4)
			}
			.accessibilityIdentifier("diary.picker")
			.navigationTitle("Diaries")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: model.cancelDiaryPicker)
						.accessibilityIdentifier("diary.cancel")
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Create Diary", systemImage: "plus", action: model.showDiaryCreation)
						.accessibilityIdentifier("diary.create")
				}
			}
		}
		.frame(minWidth: 520, minHeight: 420)
	}
}

private struct DiaryCreationView: View {
	private enum Field: Hashable {
		case title
	}

	@Bindable var model: ThingsDiaryAppModel
	@State private var title = ""
	@State private var diaryDescription = ""
	@FocusState private var focusedField: Field?

	var body: some View {
		NavigationStack {
			Form {
				TextField("Title", text: $title)
					.accessibilityIdentifier("diary.title")
					.focused($focusedField, equals: .title)
				TextField("Description", text: $diaryDescription, axis: .vertical)
					.accessibilityIdentifier("diary.description")
					.lineLimit(2...5)

				if let error = model.diaryCreationError {
					Text(error)
						.foregroundStyle(.red)
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Create Diary")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", action: model.cancelDiaryCreation)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Create") {
						let title = title
						let description = diaryDescription
						Task {
							await model.createDiary(title: title, description: description)
						}
					}
					.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
		.frame(minWidth: 420, minHeight: 280)
		.task {
			await Task.yield()
			focusedField = .title
		}
	}
}

private struct PendingEntryAction {
	let entryID: String
	let action: EntryAction
	let topicID: String?
}

private struct EntriesView: View {
	@Bindable var model: ThingsDiaryAppModel
	let diary: ThingsDiaryDiary
	let entries: [ThingsDiaryEntry]
	@State private var query = ""
	@State private var selection: DiaryNavigationSelection? = .entries
	@State private var sort: EntrySort = .newest
	@State private var newEntryContent = ""
	@State private var showingEntryCreator = false
	@State private var selectedEntryID: String?
	@State private var draftContent = ""
	@State private var showingTopicsAndTemplates = false
	@State private var showingDiaryMenu = false
	@State private var hoveredDiaryID: String?
	@State private var showingTopicCreator = false
	@State private var editingTopic: ThingsDiaryTopic?
	@State private var topicTitle = ""
	@State private var topicDescription = ""
	@State private var topicColor = ""
	@State private var topicEntryPreviewable = true
	@State private var topicDefaultTemplateID: String?
	@State private var topicsExpanded = true
	@State private var topicsHeaderHovered = false
	@State private var pendingEntryAction: PendingEntryAction?
	@State private var targetedDropDestination: EntryDropDestination?
	@State private var dropTargetFrames: [EntryDropDestination: CGRect] = [:]
	@State private var draggedEntryID: String?
	@State private var dragLocation = CGPoint.zero
	@State private var confirmingEmptyTrash = false
	@State private var editingTemplate: ThingsDiaryTemplate?
	@State private var templateContent = ""
	@State private var pendingSidebarSelection: DiaryNavigationSelection?
	@State private var isEditorFocusMode = false
	@State private var isEditorWorkspaceCompact = false
	@State private var compactWorkspacePane: CompactWorkspacePane = .editor
	@State private var sidebarVisibility: NavigationSplitViewVisibility = .all
	@State private var sidebarWidth: CGFloat = 220

	private var displayedEntries: [ThingsDiaryEntry] {
		visibleEntries(entries, selection: activeSelection, query: query, sort: sort)
	}

	private var activeSelection: DiaryNavigationSelection { selection ?? .entries }
	private var selectionIsEmpty: Bool { count(for: activeSelection) == 0 }

	private var selectedEntry: ThingsDiaryEntry? {
		entries.first { $0.id == selectedEntryID }
	}

	private func count(for selection: DiaryNavigationSelection) -> Int {
		visibleEntries(entries, selection: selection, query: "", sort: .newest).count
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $sidebarVisibility) {
			sidebar
		} detail: {
			adaptiveWorkspace
		}
		.overlayPreferenceValue(DiarySwitcherAnchorKey.self) { anchor in
			GeometryReader { proxy in
				if showingDiaryMenu, let anchor {
					let frame = proxy[anchor]

					ZStack(alignment: .topLeading) {
						Color.black.opacity(0.001)
							.contentShape(.rect)
							.onTapGesture { showingDiaryMenu = false }

						diaryMenu
							.frame(width: max(frame.width - 8, 160))
							.offset(x: frame.minX + 4, y: frame.maxY + 6)
					}
				}
			}
		}
		.navigationSplitViewStyle(.balanced)
		.onPreferenceChange(EntryDropTargetFramesKey.self) { frames in
			dropTargetFrames = frames
		}
		.onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
			guard width > 0 else { return }
			sidebarWidth = width
		}
		.overlay(alignment: .topLeading) {
			GeometryReader { proxy in
				if let draggedEntry {
					let frame = proxy.frame(in: .global)
					let localLocation = CGPoint(
						x: dragLocation.x - frame.minX,
						y: dragLocation.y - frame.minY
					)

					entryDragPreview(draggedEntry)
						.offset(
							x: localLocation.x,
							y: localLocation.y
						)
						.allowsHitTesting(false)
				}
			}
		}
		.frame(
			maxWidth: .infinity,
			minHeight: 520,
			maxHeight: .infinity
		)
		.onChange(of: selection) {
			selectedEntryID = nil
			isEditorFocusMode = false
			compactWorkspacePane = .editor
		}
		.onChange(of: selectedEntry?.id) {
			guard selectedEntry == nil, selectedEntryID != nil else { return }
			selectedEntryID = nil
			isEditorFocusMode = false
			compactWorkspacePane = .editor
		}
		.onChange(of: model.diarySettingsRequestID) {
			presentRequestedDiarySettings()
		}
		.task {
			presentRequestedDiarySettings()
		}
		.sheet(isPresented: $showingTopicsAndTemplates) {
			topicsAndTemplatesSheet
		}
		.sheet(isPresented: $showingEntryCreator) {
			entryCreatorSheet
		}
		.sheet(isPresented: $showingTopicCreator) {
			topicCreatorSheet
		}
		.alert(
			entryConfirmationTitle,
			isPresented: Binding(
				get: { pendingEntryAction != nil },
				set: { if !$0 { pendingEntryAction = nil } }
			)
		) {
			Button(entryConfirmationButtonTitle, role: .destructive) {
				confirmPendingEntryAction()
			}
			Button("Cancel", role: .cancel) { pendingEntryAction = nil }
		} message: {
			Text(entryConfirmationMessage)
		}
		.alert("Empty Trash?", isPresented: $confirmingEmptyTrash) {
			Button("Empty Trash", role: .destructive) {
				Task { await model.emptyTrash() }
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("All entries in Trash will be deleted permanently. This cannot be undone.")
		}
	}

	private var adaptiveWorkspace: some View {
		GeometryReader { proxy in
			let availableWidth = max(
				proxy.size.width - (sidebarVisibility == .detailOnly ? 0 : sidebarWidth),
				0
			)
			let compact = updatedEditorWorkspaceCompactState(
				isCompact: isEditorWorkspaceCompact,
				hasSelectedEntry: selectedEntry != nil,
				availableWidth: availableWidth,
				isDragging: draggedEntryID != nil
			)
			let layout = entryWorkspaceLayout(
				selectionIsEmpty: selectionIsEmpty,
				hasSelectedEntry: selectedEntry != nil,
				availableWidth: availableWidth,
				isEditorFocusMode: isEditorFocusMode,
				isCompact: compact,
				compactPane: compactWorkspacePane
			)

			workspace(layout: layout)
				.onAppear {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: availableWidth) {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: selectedEntry?.id) {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: draggedEntryID) {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
		}
	}

	@ViewBuilder private func workspace(layout: EntryWorkspaceLayout) -> some View {
		switch layout {
		case .listOnly:
			entryListPane(
				showsEditorButton: selectedEntry != nil && compactWorkspacePane == .list
			)
		case .split:
			HSplitView {
				entryListPane(showsEditorButton: false)
					.frame(
						minWidth: minimumEntryListWidth,
						idealWidth: 320,
						maxWidth: 440,
						maxHeight: .infinity
					)
				entryDetailPane(layout: layout)
					.frame(minWidth: minimumEntryEditorWidth, maxWidth: .infinity, maxHeight: .infinity)
			}
			.accessibilityIdentifier("workspace.split")
		case .editorOnly:
			entryDetailPane(layout: layout)
		}
	}

	private func updateEditorWorkspaceCompactState(availableWidth: CGFloat) {
		isEditorWorkspaceCompact = updatedEditorWorkspaceCompactState(
			isCompact: isEditorWorkspaceCompact,
			hasSelectedEntry: selectedEntry != nil,
			availableWidth: availableWidth,
			isDragging: draggedEntryID != nil
		)
	}

	private func entryListPane(showsEditorButton: Bool) -> some View {
		Group {
			if selectionIsEmpty {
				emptyStateView
			} else {
				VStack(spacing: 0) {
					entryListHeader
					Divider()

					if displayedEntries.isEmpty {
						emptyStateView
					} else {
						entryListScrollView
					}
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
		.searchable(text: $query)
		.toolbar {
			if showsEditorButton {
				Button {
					compactWorkspacePane = .editor
				} label: {
					Image(systemName: "doc.text")
				}
				.accessibilityIdentifier("workspace.show-editor")
				.accessibilityLabel("Show Editor")
				.help("Show Editor")
			}

			if activeSelection == .trash && !displayedEntries.isEmpty {
				Button("Empty Trash", role: .destructive) {
					confirmingEmptyTrash = true
				}
				.accessibilityIdentifier("trash.empty")
			}
		}
	}

	@ViewBuilder private func entryDetailPane(layout: EntryWorkspaceLayout) -> some View {
		if let selectedEntry {
			TextEditor(text: $draftContent)
				.accessibilityIdentifier("entry.editor")
				.disabled(selectedEntry.deletedAt != nil || selectedEntry.archived)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.toolbar {
					ToolbarItemGroup(placement: .primaryAction) {
						if isEditorFocusMode {
							Button {
								isEditorFocusMode = false
								if isEditorWorkspaceCompact {
									compactWorkspacePane = .list
								}
							} label: {
								Image(systemName: "arrow.down.right.and.arrow.up.left")
							}
							.accessibilityIdentifier("workspace.exit-editor-focus")
							.accessibilityLabel("Exit Editor Focus")
							.help("Exit Editor Focus")
						} else if layout == .split {
							Button {
								isEditorFocusMode = true
							} label: {
								Image(systemName: "arrow.up.left.and.arrow.down.right")
							}
							.accessibilityIdentifier("workspace.focus-editor")
							.accessibilityLabel("Focus Editor")
							.help("Focus Editor")
						} else {
							Button {
								compactWorkspacePane = .list
							} label: {
								Image(systemName: "list.bullet")
							}
							.accessibilityIdentifier("workspace.show-entry-list")
							.accessibilityLabel("Show Entry List")
							.help("Show Entry List")
						}

						Menu {
							entryActions(for: selectedEntry)
						} label: {
							Image(systemName: "ellipsis.circle")
						}
						.accessibilityIdentifier("entry.actions")
						.help("Entry Actions")

						if selectedEntry.deletedAt == nil && !selectedEntry.archived {
							Button("Save") {
								let entry = selectedEntry
								let content = draftContent
								Task {
									await model.updateEntry(entry, content: content)
								}
							}
							.keyboardShortcut("s", modifiers: .command)
							.disabled(!canSave(selectedEntry))
						}
					}
				}
		} else {
			ContentUnavailableView {
				Label(diary.title, systemImage: "book.closed")
			} description: {
				Text(diary.description.isEmpty ? "Your diary overview" : diary.description)
				Text(
					"\(count(for: .entries)) entries · \(count(for: .bookmarks)) bookmarks · \(count(for: .archive)) archived · \(count(for: .trash)) in trash"
				)
			}
			.accessibilityIdentifier("diary.overview")
		}
	}

	private var sidebar: some View {
		VStack(spacing: 0) {
			diarySwitcher

			ScrollView {
				VStack(alignment: .leading, spacing: 4) {
					Button {
						newEntryContent = ""
						showingEntryCreator = true
					} label: {
						HStack(spacing: 8) {
							Image(systemName: "square.and.pencil")
								.frame(width: 16)
								.foregroundStyle(.tint)
							Text("New Entry")
								.lineLimit(1)
								.truncationMode(.tail)
								.layoutPriority(1)
							Spacer(minLength: 6)
							Text("⌘N")
								.font(.caption)
								.foregroundStyle(.tertiary)
								.fixedSize()
						}
						.padding(.horizontal, 7)
						.padding(.vertical, 5)
						.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
						.contentShape(.rect)
					}
					.accessibilityIdentifier("entry.create")
					.buttonStyle(.plain)
					.keyboardShortcut("n", modifiers: .command)
					.help("Create a new entry")

					sidebarRow(
						"Entries",
						systemImage: "note.text",
						destination: .entries,
						identifier: "sidebar.entries"
					)
					sidebarRow(
						"Bookmarks",
						systemImage: "bookmark",
						destination: .bookmarks,
						identifier: "sidebar.bookmarks",
						dropDestination: .bookmarks
					)

					Divider()
						.padding(.vertical, 4)

					HStack(spacing: 8) {
						if model.topics.isEmpty {
							HStack(spacing: 8) {
								Image(systemName: "tag")
									.frame(width: 16)
									.foregroundStyle(.tint)
								Text("Topics")
									.lineLimit(1)
									.truncationMode(.tail)
									.layoutPriority(1)
								Spacer(minLength: 6)
							}
							.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
						} else {
							Button {
								toggleTopics()
							} label: {
								HStack(spacing: 8) {
									Image(systemName: "tag")
										.frame(width: 16)
										.foregroundStyle(.tint)
									Text("Topics")
										.foregroundStyle(.primary)
										.lineLimit(1)
										.truncationMode(.tail)
										.layoutPriority(1)
									Spacer(minLength: 6)
								}
								.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
								.contentShape(.rect)
							}
							.buttonStyle(.plain)
							.accessibilityIdentifier("topics.toggle")
							.accessibilityLabel(topicsExpanded ? "Collapse Topics" : "Expand Topics")
							.accessibilityValue(topicsExpanded ? "Expanded" : "Collapsed")
							.help(topicsExpanded ? "Collapse Topics" : "Expand Topics")
						}

						Button {
							beginCreatingTopic()
						} label: {
							Image(systemName: "plus")
								.frame(width: 18, height: 20)
								.opacity(topicsHeaderHovered || model.topics.isEmpty ? 1 : 0)
						}
						.buttonStyle(.plain)
						.allowsHitTesting(topicsHeaderHovered || model.topics.isEmpty)
						.accessibilityIdentifier("topic.create")
						.accessibilityLabel("New Topic")
						.help("New Topic")

						if !model.topics.isEmpty {
							Button {
								toggleTopics()
							} label: {
								Image(systemName: topicsExpanded ? "chevron.down" : "chevron.right")
									.font(.caption.weight(.semibold))
									.frame(width: 18, height: 20)
							}
							.buttonStyle(.plain)
							.accessibilityIdentifier("topics.chevron")
							.accessibilityLabel(topicsExpanded ? "Collapse Topics" : "Expand Topics")
							.accessibilityValue(topicsExpanded ? "Expanded" : "Collapsed")
							.help(topicsExpanded ? "Collapse Topics" : "Expand Topics")
						}
					}
					.padding(.horizontal, 7)
					.padding(.vertical, 5)
					.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
					.contentShape(.rect)
					.onHover { topicsHeaderHovered = $0 }

					if topicsExpanded {
						ForEach(model.topics) { topic in
							sidebarRow(
								topic.title,
								systemImage: "tag",
								destination: .topic(topic.id),
								identifier: "sidebar.topic.\(topic.id)",
								color: topicColorValue(topic.color),
								showsCount: false,
								dropDestination: .topic(topic.id),
								doubleClick: { beginEditing(topic) }
							)
						}
					}

					Divider()
						.padding(.vertical, 4)

					sidebarRow(
						"Archive",
						systemImage: "archivebox",
						destination: .archive,
						identifier: "sidebar.archive",
						dropDestination: .archive
					)
					sidebarRow(
						"Trash",
						systemImage: "trash",
						destination: .trash,
						identifier: "sidebar.trash",
						dropDestination: .trash
					)
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(maxWidth: .infinity)
		}
		.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
		.background {
			GeometryReader { proxy in
				Color.clear.preference(key: SidebarWidthPreferenceKey.self, value: proxy.size.width)
			}
		}
	}

	private var diarySwitcher: some View {
		Button {
			showingDiaryMenu.toggle()
		} label: {
			HStack(spacing: 8) {
				Image(systemName: "book.closed")
					.frame(width: 16)
					.symbolRenderingMode(.monochrome)
					.foregroundStyle(Color(nsColor: .secondaryLabelColor))
				Text(diary.title)
					.font(.callout.weight(.semibold))
					.lineLimit(1)
					.truncationMode(.tail)
					.layoutPriority(1)
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
		.accessibilityIdentifier("diary.switcher")
		.accessibilityLabel("Current diary, \(diary.title)")
		.help("Switch Diary")
		.padding(.init(top: 6, leading: 6, bottom: 2, trailing: 6))
		.anchorPreference(key: DiarySwitcherAnchorKey.self, value: .bounds) { $0 }
	}

	private var diaryMenu: some View {
		VStack(spacing: 2) {
			ScrollView {
				LazyVStack(spacing: 2) {
					ForEach(model.availableDiaries) { candidate in
						diaryMenuRow(candidate)
					}
				}
			}
			.frame(height: min(CGFloat(model.availableDiaries.count) * 30, 240))

			Divider()
				.overlay(Color(nsColor: .separatorColor))
				.padding(.vertical, 3)

			Button {
				showingDiaryMenu = false
				model.showDiaryCreation()
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
			.accessibilityIdentifier("diary.create")
		}
		.padding(6)
		.background {
			MenuMaterialBackground()
				.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
		}
		.overlay {
			RoundedRectangle(cornerRadius: 9, style: .continuous)
				.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
		}
		.shadow(color: .black.opacity(0.18), radius: 10, y: 4)
	}

	private func diaryMenuRow(_ candidate: ThingsDiaryDiary) -> some View {
		let isSelected = candidate.id == diary.id
		let settingsVisible = hoveredDiaryID == candidate.id

		return HStack(spacing: 2) {
			Button {
				showingDiaryMenu = false
				guard !isSelected else { return }
				Task { await model.selectDiary(candidate) }
			} label: {
				HStack(spacing: 8) {
					if isSelected {
						Image(systemName: "checkmark").frame(width: 16)
					} else {
						Color.clear.frame(width: 16, height: 1)
					}
					Text(candidate.title)
						.lineLimit(1)
					Spacer()
				}
				.padding(.horizontal, 7)
				.frame(maxWidth: .infinity, minHeight: 28)
				.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.accessibilityIdentifier("diary.switch.\(candidate.id)")
			.accessibilityValue(isSelected ? "Selected" : "")

			Button {
				showingDiaryMenu = false
				Task { await model.requestDiarySettings(for: candidate) }
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
			.accessibilityIdentifier("diary.settings.\(candidate.id)")
			.help("Settings for \(candidate.title)")
		}
		.onHover { hovering in
			hoveredDiaryID = hovering ? candidate.id : nil
		}
	}

	private func presentRequestedDiarySettings() {
		guard model.consumeDiarySettingsRequest(for: diary.id) else { return }
		showingDiaryMenu = false
		showingTopicsAndTemplates = true
	}

	private var entryListHeader: some View {
		HStack {
			Text(selectionTitle)
				.font(.headline)
				.accessibilityIdentifier("entry-list.title")
				.accessibilityLabel(selectionTitle)
			Spacer()
			Menu {
				Picker("Sort", selection: $sort) {
					ForEach(EntrySort.allCases) { sort in
						Text(sort.rawValue).tag(sort)
					}
				}
			} label: {
				Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
			}
		}
		.padding(.horizontal)
		.padding(.vertical, 8)
		.background(.background)
		.zIndex(1)
		.accessibilityIdentifier("entry-list.header")
	}

	private var emptyStateView: some View {
		ContentUnavailableView {
			Label(emptyStateTitle, systemImage: emptyStateSystemImage)
		} description: {
			Text(emptyStateDescription)
		} actions: {
			if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				if activeSelection == .entries {
					Button("New Entry", systemImage: "square.and.pencil") {
						newEntryContent = ""
						showingEntryCreator = true
					}
					.buttonStyle(.borderedProminent)
				} else if activeSelection == .bookmarks || isTopicSelected {
					Button("Browse Entries") {
						selection = .entries
					}
					.buttonStyle(.bordered)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accessibilityIdentifier("entry-list.empty-state")
	}

	private var entryListScrollView: some View {
		ScrollView {
			LazyVStack(spacing: 0) {
				ForEach(displayedEntries) { entry in
					entryListRow(entry)
						.padding(.horizontal)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(.background)
						.opacity(draggedEntryID == entry.id ? 0.45 : 1)
						.contentShape(.interaction, Rectangle())
						.onTapGesture {
							selectedEntryID = entry.id
							draftContent = entry.content
							compactWorkspacePane = .editor
						}
						.highPriorityGesture(entryDragGesture(for: entry))
						.accessibilityElement(children: .combine)
						.accessibilityIdentifier("entry.\(entry.id)")
						.accessibilityAddTraits(.isButton)
						.contextMenu {
							entryActions(for: entry)
						}

					Divider()
						.padding(.leading)
				}
			}
		}
		.clipped()
		.background(.background)
		.accessibilityIdentifier("entry-list.scroll")
	}

	private var pendingEntry: ThingsDiaryEntry? {
		guard let pendingEntryAction else { return nil }
		return entries.first { $0.id == pendingEntryAction.entryID }
	}

	private var entryConfirmationTitle: String {
		switch pendingEntryAction?.action {
		case .deletePermanently:
			"Delete Entry Permanently?"
		default:
			"Move Entry to Trash?"
		}
	}

	private var entryConfirmationButtonTitle: String {
		switch pendingEntryAction?.action {
		case .deletePermanently:
			"Delete Permanently"
		default:
			"Move to Trash"
		}
	}

	private var entryConfirmationMessage: String {
		let title =
			pendingEntry.map {
				entryListPresentation(content: $0.content).title
			} ?? "This entry"
		switch pendingEntryAction?.action {
		case .deletePermanently:
			return "“\(title)” will be deleted permanently. This cannot be undone."
		default:
			return "“\(title)” can be restored later from Trash."
		}
	}

	private func confirmPendingEntryAction() {
		guard let pending = pendingEntryAction,
			let entry = entries.first(where: { $0.id == pending.entryID })
		else {
			pendingEntryAction = nil
			return
		}
		pendingEntryAction = nil
		execute(pending.action, on: entry, topicID: pending.topicID)
	}

	private func performDrop(
		_ payload: EntryDragPayload,
		to destination: EntryDropDestination
	) {
		guard
			let request = resolveEntryDrop(
				payload,
				to: destination,
				diaryID: diary.id,
				entries: entries
			),
			let entry = entries.first(where: { $0.id == payload.entryID })
		else {
			return
		}

		switch request {
		case .bookmark:
			perform(.bookmark, on: entry, topicID: nil)
		case .moveToTopic(let topicID):
			perform(.moveToTopic, on: entry, topicID: topicID)
		case .archive:
			perform(.archive, on: entry, topicID: nil)
		case .moveToTrash:
			perform(.moveToTrash, on: entry, topicID: nil)
		}
	}

	private func canSave(_ entry: ThingsDiaryEntry) -> Bool {
		!draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& draftContent != entry.content
	}

	private func entryDragGesture(for entry: ThingsDiaryEntry) -> some Gesture {
		DragGesture(
			minimumDistance: 4,
			coordinateSpace: .global
		)
		.onChanged { value in
			draggedEntryID = entry.id
			dragLocation = value.location
			targetedDropDestination = dropDestination(at: value.location)
		}
		.onEnded { value in
			defer {
				targetedDropDestination = nil
				draggedEntryID = nil
			}
			guard let destination = dropDestination(at: value.location) else { return }
			performDrop(
				EntryDragPayload(diaryID: diary.id, entryID: entry.id),
				to: destination
			)
		}
	}

	private func dropDestination(at location: CGPoint) -> EntryDropDestination? {
		dropTargetFrames.first { $0.value.contains(location) }?.key
	}

	private var draggedEntry: ThingsDiaryEntry? {
		guard let draggedEntryID else { return nil }
		return entries.first { $0.id == draggedEntryID }
	}

	private func entryDragPreview(_ entry: ThingsDiaryEntry) -> some View {
		entryListRow(entry)
			.padding(.horizontal, 12)
			.padding(.vertical, 6)
			.frame(width: 280, alignment: .leading)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
			.overlay {
				RoundedRectangle(cornerRadius: 10)
					.stroke(Color.primary.opacity(0.14), lineWidth: 1)
			}
			.shadow(color: .black.opacity(0.2), radius: 12, y: 5)
			.accessibilityIdentifier("entry.drag-preview")
	}

	private func sidebarRow(
		_ title: String,
		systemImage: String,
		destination: DiaryNavigationSelection,
		identifier: String,
		color: Color? = nil,
		showsCount: Bool = true,
		dropDestination: EntryDropDestination? = nil,
		doubleClick: (() -> Void)? = nil
	) -> some View {
		let isDropTargeted = dropDestination != nil && dropDestination == targetedDropDestination
		let dropTint = dropDestination == .trash ? Color.red : color ?? Color.accentColor

		return Button {
			guard let doubleClick,
				let event = NSApp.currentEvent,
				event.type == .leftMouseUp
			else {
				selection = destination
				return
			}

			if event.clickCount > 1 {
				pendingSidebarSelection = nil
				doubleClick()
			} else {
				pendingSidebarSelection = destination
				DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval) {
					guard pendingSidebarSelection == destination else { return }
					selection = destination
					pendingSidebarSelection = nil
				}
			}
		} label: {
			HStack(spacing: 8) {
				if let color {
					Circle()
						.fill(color)
						.frame(width: 8, height: 8)
						.frame(width: 16)
				} else {
					Image(systemName: systemImage)
						.frame(width: 16)
						.foregroundStyle(.tint)
				}
				Text(title)
					.lineLimit(1)
					.truncationMode(.tail)
					.layoutPriority(1)
				Spacer(minLength: 6)
				ZStack(alignment: .trailing) {
					Image(systemName: dropDestination == .trash ? "trash.fill" : "arrow.down.circle.fill")
						.foregroundStyle(dropTint)
						.opacity(isDropTargeted ? 1 : 0)
					if showsCount && count(for: destination) > 0 {
						Text(count(for: destination), format: .number)
							.font(.caption.monospacedDigit())
							.foregroundStyle(.secondary)
							.opacity(isDropTargeted ? 0 : 1)
					}
				}
				.frame(width: 18, height: 20)
			}
			.padding(.horizontal, 7)
			.padding(.vertical, 5)
			.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
			.contentShape(.rect)
			.background {
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.fill(
						isDropTargeted
							? dropTint.opacity(0.18)
							: activeSelection == destination
								? Color.accentColor.opacity(0.16)
								: Color.clear
					)
			}
			.overlay {
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.stroke(isDropTargeted ? dropTint.opacity(0.7) : Color.clear, lineWidth: 1)
			}
			.animation(.easeOut(duration: 0.12), value: isDropTargeted)
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier(identifier)
		.accessibilityValue(isDropTargeted ? "Drop target" : "")
		.background {
			GeometryReader { proxy in
				Color.clear.preference(
					key: EntryDropTargetFramesKey.self,
					value: dropDestination.map {
						[$0: proxy.frame(in: .global)]
					} ?? [:]
				)
			}
		}
	}

	private func entryActions(for entry: ThingsDiaryEntry) -> some View {
		EntryActionsMenuContent(entry: entry, topics: model.topics) { action, topicID in
			perform(action, on: entry, topicID: topicID)
		}
	}

	private func perform(
		_ action: EntryAction,
		on entry: ThingsDiaryEntry,
		topicID: String?
	) {
		if entryActionRequiresConfirmation(action, content: entry.content) {
			pendingEntryAction = PendingEntryAction(
				entryID: entry.id,
				action: action,
				topicID: topicID
			)
			return
		}
		execute(action, on: entry, topicID: topicID)
	}

	private func execute(
		_ action: EntryAction,
		on entry: ThingsDiaryEntry,
		topicID: String?
	) {
		let clearsSelection = shouldClearSelection(
			after: action,
			entry: entry,
			topicID: topicID
		)
		Task {
			switch action {
			case .bookmark:
				if !entry.bookmarked {
					await model.toggleBookmark(entry)
				}
			case .toggleBookmark:
				await model.toggleBookmark(entry)
			case .toggleArchive:
				await model.toggleArchive(entry)
			case .archive:
				if !entry.archived {
					await model.toggleArchive(entry)
				}
			case .duplicate:
				await model.duplicateEntry(entry)
			case .moveToTopic:
				await model.moveEntry(entry, toTopicID: topicID)
			case .moveToTrash:
				await model.moveToTrash(entry)
			case .restore:
				await model.restoreEntry(entry)
			case .deletePermanently:
				await model.deleteEntryPermanently(entry)
			}

			if clearsSelection {
				selectedEntryID = nil
			}
		}
	}

	private func shouldClearSelection(
		after action: EntryAction,
		entry: ThingsDiaryEntry,
		topicID: String?
	) -> Bool {
		guard selectedEntryID == entry.id else { return false }
		switch action {
		case .bookmark:
			return false
		case .toggleBookmark:
			return activeSelection == .bookmarks
		case .toggleArchive, .archive, .moveToTrash, .restore, .deletePermanently:
			return true
		case .moveToTopic:
			guard case .topic(let selectedTopicID) = activeSelection else {
				return false
			}
			return selectedTopicID != topicID
		case .duplicate:
			return false
		}
	}

	private var entryCreatorSheet: some View {
		NavigationStack {
			Form {
				if !model.templates.isEmpty {
					Menu("Use Template") {
						ForEach(model.templates) { template in
							Button(template.content.isEmpty ? "Empty Template" : String(template.content.prefix(40))) {
								newEntryContent = template.content
							}
						}
					}
				}
				TextEditor(text: $newEntryContent)
					.accessibilityIdentifier("entry.new-content")
					.frame(minHeight: 220)
			}
			.formStyle(.grouped)
			.navigationTitle("New Entry")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { showingEntryCreator = false }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Create") {
						let content = newEntryContent
						Task {
							await model.createEntry(content: content)
							selection = .entries
							showingEntryCreator = false
						}
					}
					.disabled(newEntryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
		.frame(minWidth: 520, minHeight: 380)
	}

	@ViewBuilder
	private func entryListRow(_ entry: ThingsDiaryEntry) -> some View {
		let presentation = entryListPresentation(content: entry.content)
		let topic = model.topics.first { $0.id == entry.topicID }
		VStack(alignment: .leading, spacing: 5) {
			HStack(spacing: 7) {
				if let topic {
					Circle()
						.fill(topicColorValue(topic.color))
						.frame(width: 8, height: 8)
						.accessibilityLabel("Topic: \(topic.title)")
				}
				Text(presentation.title)
					.font(.headline)
					.lineLimit(1)
				Spacer(minLength: 8)
				if entry.bookmarked {
					Image(systemName: "bookmark.fill")
						.foregroundStyle(.tint)
						.accessibilityLabel("Bookmarked")
				}
				Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			if !entry.previewHidden,
				topic?.entryPreviewable != false,
				let preview = presentation.preview
			{
				Text(preview)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(3)
			}
			if entry.archived {
				Label("Archived", systemImage: "archivebox.fill")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else if entry.deletedAt != nil {
				Label("In Trash", systemImage: "trash.fill")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.contentShape(.rect)
		.padding(.vertical, 5)
	}

	private var emptyStateTitle: String {
		if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return "No Results"
		}
		return switch activeSelection {
		case .entries: "No Entries Yet"
		case .bookmarks: "No Bookmarks Yet"
		case .topic: "No Entries in This Topic"
		case .archive: "Archive is empty"
		case .trash: "Trash is empty"
		}
	}

	private var emptyStateDescription: String {
		if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return "Try another search term."
		}
		return switch activeSelection {
		case .entries: "Create your first entry to start writing in this diary."
		case .bookmarks: "Bookmark entries you want to find quickly."
		case .topic: "Move an existing entry into this topic to keep related writing together."
		case .archive: "Archive entries you want to keep without showing in your main list."
		case .trash: "Deleted entries appear here until permanently removed."
		}
	}

	private var emptyStateSystemImage: String {
		switch activeSelection {
		case .bookmarks: "bookmark"
		case .topic: "tag"
		case .archive: "archivebox"
		case .trash: "trash"
		case .entries: "note.text"
		}
	}

	private var isTopicSelected: Bool {
		if case .topic = activeSelection {
			return true
		}
		return false
	}

	private let topicColors = [
		"#94A3B8", "#93C5FD", "#86EFAC", "#A3E635", "#2DD4BF",
		"#FCD34D", "#F4A261", "#E76F51", "#E9C46A", "#B5838D", "#C4B5FD",
	]

	private func topicColorValue(_ hex: String) -> Color {
		Color(topicHex: hex) ?? .secondary
	}

	private func toggleTopics() {
		withAnimation(.snappy(duration: 0.18)) {
			topicsExpanded.toggle()
		}
	}

	private func beginCreatingTopic() {
		topicTitle = ""
		topicDescription = ""
		topicColor = topicColors[0]
		topicEntryPreviewable = true
		topicDefaultTemplateID = nil
		editingTopic = nil
		showingTopicCreator = true
	}

	private func beginEditing(_ topic: ThingsDiaryTopic) {
		editingTopic = topic
		topicTitle = topic.title
		topicDescription = topic.description
		topicColor = topic.color.isEmpty ? topicColors[0] : topic.color
		topicEntryPreviewable = topic.entryPreviewable
		topicDefaultTemplateID = topic.defaultTemplateID
		showingTopicCreator = true
	}

	private var topicCreatorSheet: some View {
		NavigationStack {
			Form {
				TextField("Title", text: $topicTitle)
					.accessibilityIdentifier("topic.title")
					.onChange(of: topicTitle) {
						if topicTitle.count > maximumTopicTitleLength {
							topicTitle = String(topicTitle.prefix(maximumTopicTitleLength))
						}
					}
				TextField("Description", text: $topicDescription, axis: .vertical)
					.accessibilityIdentifier("topic.description")
					.lineLimit(2...5)
				Picker("Default Template", selection: $topicDefaultTemplateID) {
					Text("None").tag(String?.none)
					ForEach(model.templates) { template in
						Text(template.content.isEmpty ? "Empty Template" : String(template.content.prefix(40)))
							.tag(Optional(template.id))
					}
				}
				Toggle("Show entry previews", isOn: $topicEntryPreviewable)
					.accessibilityIdentifier("topic.entry-previews")
				LabeledContent("Color") {
					HStack(spacing: 10) {
						ForEach(topicColors, id: \.self) { color in
							Button {
								topicColor = color
							} label: {
								Circle()
									.fill(topicColorValue(color))
									.frame(width: 20, height: 20)
									.overlay {
										if topicColor == color {
											Circle().stroke(.primary, lineWidth: 2)
										}
									}
							}
							.buttonStyle(.plain)
							.accessibilityLabel("Topic color \(color)")
						}
					}
				}
			}
			.formStyle(.grouped)
			.navigationTitle(editingTopic == nil ? "New Topic" : "Edit Topic")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						showingTopicCreator = false
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(editingTopic == nil ? "Create" : "Save") {
						let title = topicTitle
						let description = topicDescription
						let color = topicColor
						let entryPreviewable = topicEntryPreviewable
						let defaultTemplateID = topicDefaultTemplateID
						let topic = editingTopic
						let existingTopicIDs = Set(model.topics.map(\.id))
						Task {
							if let topic {
								await model.updateTopic(
									topic,
									title: title,
									description: description,
									color: color,
									entryPreviewable: entryPreviewable,
									defaultTemplateID: defaultTemplateID
								)
							} else {
								await model.createTopic(
									title: title,
									description: description,
									color: color,
									entryPreviewable: entryPreviewable,
									defaultTemplateID: defaultTemplateID
								)
								if let createdTopic = model.topics.first(where: {
									!existingTopicIDs.contains($0.id)
								}) {
									selection = .topic(createdTopic.id)
								}
							}
							showingTopicCreator = false
						}
					}
					.disabled(normalizedTopicTitle(topicTitle).isEmpty)
				}
			}
		}
		.frame(minWidth: 560, minHeight: 420)
	}

	private var selectionTitle: String {
		switch activeSelection {
		case .entries: "Entries"
		case .bookmarks: "Bookmarks"
		case .topic(let topicID): model.topics.first(where: { $0.id == topicID })?.title ?? "Topic"
		case .archive: "Archive"
		case .trash: "Trash"
		}
	}

	private var topicsAndTemplatesSheet: some View {
		NavigationStack {
			Form {
				Section("Topics") {
					ForEach(model.topics) { topic in
						Button {
							showingTopicsAndTemplates = false
							DispatchQueue.main.async { beginEditing(topic) }
						} label: {
							HStack {
								Circle()
									.fill(topicColorValue(topic.color))
									.frame(width: 9, height: 9)
								Text(topic.title)
								Spacer()
								Image(systemName: "chevron.right")
									.foregroundStyle(.secondary)
							}
						}
					}
					Button("New Topic", systemImage: "plus") {
						showingTopicsAndTemplates = false
						DispatchQueue.main.async {
							editingTopic = nil
							topicTitle = ""
							topicDescription = ""
							topicColor = topicColors[0]
							topicEntryPreviewable = true
							topicDefaultTemplateID = nil
							showingTopicCreator = true
						}
					}
				}

				Section("Templates") {
					ForEach(model.templates) { template in
						Button(template.content.isEmpty ? "Empty Template" : String(template.content.prefix(40))) {
							editingTemplate = template
							templateContent = template.content
						}
					}
					TextEditor(text: $templateContent)
						.frame(minHeight: 100)
					Button(editingTemplate == nil ? "Create Template" : "Save Template") {
						let template = editingTemplate
						let content = templateContent
						Task {
							if let template {
								await model.updateTemplate(template, content: content)
							} else {
								await model.createTemplate(content: content)
							}
							editingTemplate = nil
							templateContent = ""
						}
					}
					if editingTemplate != nil {
						Button("New Template") {
							editingTemplate = nil
							templateContent = ""
						}
					}
				}
			}
			.navigationTitle("Topics & Templates")
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { showingTopicsAndTemplates = false }
				}
			}
		}
		.frame(minWidth: 460, minHeight: 520)
	}
}

private struct EntryActionsMenuContent: View {
	let entry: ThingsDiaryEntry
	let topics: [ThingsDiaryTopic]
	let perform: (EntryAction, String?) -> Void

	var body: some View {
		let actions = availableEntryActions(for: entry)

		if actions.contains(.restore) {
			Button("Restore", systemImage: "arrow.uturn.backward") {
				perform(.restore, nil)
			}
		}

		if actions.contains(.toggleBookmark) {
			Button(
				entry.bookmarked ? "Remove Bookmark" : "Bookmark",
				systemImage: entry.bookmarked ? "bookmark.slash" : "bookmark"
			) {
				perform(.toggleBookmark, nil)
			}
		}

		if actions.contains(.toggleArchive) {
			Button(
				entry.archived ? "Restore from Archive" : "Archive",
				systemImage: entry.archived ? "tray.and.arrow.up" : "archivebox"
			) {
				perform(.toggleArchive, nil)
			}
		}

		if actions.contains(.moveToTopic) {
			Menu("Move to Topic", systemImage: "tag") {
				Button("Unfiled") {
					perform(.moveToTopic, nil)
				}
				ForEach(topics) { topic in
					Button(topic.title) {
						perform(.moveToTopic, topic.id)
					}
				}
			}
		}

		if actions.contains(.duplicate) {
			Button("Duplicate", systemImage: "plus.square.on.square") {
				perform(.duplicate, nil)
			}
		}

		if actions.contains(.moveToTrash) || actions.contains(.deletePermanently) {
			Divider()
		}

		if actions.contains(.moveToTrash) {
			Button("Move to Trash", systemImage: "trash", role: .destructive) {
				perform(.moveToTrash, nil)
			}
		}

		if actions.contains(.deletePermanently) {
			Button(
				"Delete Permanently",
				systemImage: "trash.slash",
				role: .destructive
			) {
				perform(.deletePermanently, nil)
			}
		}
	}
}

extension Color {
	fileprivate init?(topicHex: String) {
		let value = topicHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
		self.init(
			red: Double((number >> 16) & 0xff) / 255,
			green: Double((number >> 8) & 0xff) / 255,
			blue: Double(number & 0xff) / 255
		)
	}
}

private struct ErrorView: View {
	let message: String
	let retry: () -> Void

	var body: some View {
		ContentUnavailableView {
			Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
		} description: {
			Text(message)
		} actions: {
			Button("Back to Sign In", action: retry)
		}
	}
}

#Preview {
	ContentView(model: ThingsDiaryAppModel())
}
