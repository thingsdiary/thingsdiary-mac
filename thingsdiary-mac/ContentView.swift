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

private struct WorkspaceShortcutMonitor: NSViewRepresentable {
	let save: () -> Bool
	let create: () -> Bool
	let selectNextTab: () -> Bool
	let selectPreviousTab: () -> Bool

	final class MonitorView: NSView {
		var windowDidChange: ((NSWindow?) -> Void)?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			windowDidChange?(window)
		}
	}

	final class Coordinator {
		weak var window: NSWindow?
		var save: () -> Bool
		var create: () -> Bool
		var selectNextTab: () -> Bool
		var selectPreviousTab: () -> Bool
		private var monitor: Any?

		init(
			save: @escaping () -> Bool,
			create: @escaping () -> Bool,
			selectNextTab: @escaping () -> Bool,
			selectPreviousTab: @escaping () -> Bool
		) {
			self.save = save
			self.create = create
			self.selectNextTab = selectNextTab
			self.selectPreviousTab = selectPreviousTab
		}

		func install() {
			guard monitor == nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
				guard let self, window?.isKeyWindow == true else { return event }
				let modifiers = event.modifierFlags.intersection([
					.command, .control, .option, .shift,
				])
				let handled = switch (event.keyCode, modifiers) {
				case (1, .command), (1, .control): save()
				case (45, .command), (17, .command): create()
				case (48, .control): selectNextTab()
				case (48, .shift): selectPreviousTab()
				default: false
				}
				return handled ? nil : event
			}
		}

		func remove() {
			guard let monitor else { return }
			NSEvent.removeMonitor(monitor)
			self.monitor = nil
		}

		deinit {
			remove()
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(
			save: save,
			create: create,
			selectNextTab: selectNextTab,
			selectPreviousTab: selectPreviousTab
		)
	}

	func makeNSView(context: Context) -> NSView {
		let view = MonitorView(frame: .zero)
		view.windowDidChange = { [weak coordinator = context.coordinator] window in
			coordinator?.window = window
		}
		context.coordinator.install()
		return view
	}

	func updateNSView(_ view: NSView, context: Context) {
		context.coordinator.save = save
		context.coordinator.create = create
		context.coordinator.selectNextTab = selectNextTab
		context.coordinator.selectPreviousTab = selectPreviousTab
	}

	static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
		coordinator.remove()
	}
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
					.accessibilityIdentifier("auth.generated-secret-key")
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
				.accessibilityIdentifier("auth.email")

			SecureField("Password", text: $model.password)
				.textContentType(.password)
				.accessibilityIdentifier("auth.password")

			SecureField("Secret key (TDKV1-…)", text: $model.secretKey)
				.accessibilityIdentifier("auth.secret-key")

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
				.keyboardShortcut(.defaultAction)
				.disabled(!model.canSubmit)
				.accessibilityIdentifier("auth.sign-in")

				Button("Create Account", action: model.showRegistration)
				.accessibilityIdentifier("auth.show-registration")
			}
		}
		.textFieldStyle(.roundedBorder)
		.frame(maxWidth: 360)
		.padding(40)
		.background(AuthenticationWindowChrome())
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
				.accessibilityIdentifier("auth.email")

			SecureField("Password", text: $model.password)
				.textContentType(.newPassword)
				.accessibilityIdentifier("auth.password")

			SecureField("Confirm password", text: $model.passwordConfirmation)
				.textContentType(.newPassword)
				.accessibilityIdentifier("auth.password-confirmation")

			if !model.passwordConfirmation.isEmpty && model.password != model.passwordConfirmation {
				Text("Passwords do not match.")
					.font(.caption)
					.foregroundStyle(.red)
					.accessibilityIdentifier("auth.password-mismatch")
			}

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
				.keyboardShortcut(.defaultAction)
				.disabled(!model.canRegister)
				.accessibilityIdentifier("auth.register")

				Button("Back to Sign In", action: model.showLogin)
				.accessibilityIdentifier("auth.show-login")
			}
		}
		.textFieldStyle(.roundedBorder)
		.frame(maxWidth: 420)
		.padding(40)
		.background(AuthenticationWindowChrome())
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

private struct PendingBrowserTabClose {
	let tabID: WorkspaceTabID
	let title: String
}

private enum EntryDraftSaveOutcome {
	case saved
	case changedWhileSaving
	case failed
}

private struct EntriesView: View {
	private let listPaneHorizontalInset = workspaceTitlebarHorizontalInset
	private let minimumSidebarWidth: CGFloat = 180
	private let maximumSidebarWidth: CGFloat = 300

	@Bindable var model: ThingsDiaryAppModel
	let diary: ThingsDiaryDiary
	let entries: [ThingsDiaryEntry]
	@State private var query = ""
	@State private var searchIsFocused = false
	@State private var searchResetID = 0
	@State private var selection: DiaryNavigationSelection? = .entries
	@State private var tabs = BrowserTabsState<WorkspaceTabID>()
	@State private var draftsByEntryID: [String: String] = [:]
	@FocusState private var editorIsFocused: Bool
	@State private var showingDiaryEditor = false
	@State private var diaryTitle = ""
	@State private var diaryDescription = ""
	@State private var diaryEditError: String?
	@State private var diarySaveInProgress = false
	@State private var showingDiaryMenu = false
	@State private var hoveredDiaryID: String?
	@State private var showingTopicCreator = false
	@State private var editingTopic: ThingsDiaryTopic?
	@State private var topicPendingDeletion: ThingsDiaryTopic?
	@State private var topicTitle = ""
	@State private var topicDescription = ""
	@State private var topicColor = ""
	@State private var topicEntryPreviewable = true
	@State private var topicDefaultTemplateID: String?
	@State private var topicsExpanded = true
	@State private var topicsHeaderHovered = false
	@State private var pendingEntryAction: PendingEntryAction?
	@State private var pendingBrowserTabClose: PendingBrowserTabClose?
	@State private var pendingBrowserTabCloseQueue: [WorkspaceTabID] = []
	@State private var browserTabCloseSaveError: String?
	@State private var tabSavingBeforeClose: WorkspaceTabID?
	@State private var targetedDropDestination: EntryDropDestination?
	@State private var dropTargetFrames: [EntryDropDestination: CGRect] = [:]
	@State private var draggedEntryID: String?
	@State private var dragLocation = CGPoint.zero
	@State private var confirmingEmptyTrash = false
	@State private var templateDraftsByID: [String: String] = [:]
	@State private var templatePendingDeletion: ThingsDiaryTemplate?
	@State private var isEntryListCollapsed = false
	@State private var isEditorWorkspaceCompact = false
	@State private var compactWorkspacePane: CompactWorkspacePane = .editor
	@State private var currentWorkspaceLayout = EntryWorkspaceLayout.listOnly
	@State private var availableWorkspaceWidth: CGFloat = 0
	@State private var dragStartEntryListWidth: CGFloat?
	@State private var dragStartSidebarWidth: CGFloat?
	@State private var availableBrowserTabsWidth: CGFloat = 0
	@State private var browserTabReorderSession: TabReorderSession<WorkspaceTabID>?
	@State private var trafficLightsTrailingInset: CGFloat = 76
	@State private var sidebarToggleInSidebar = true
	@Namespace private var workspaceControlsNamespace
	@SceneStorage("entries.preferredSidebarWidth") private var preferredSidebarWidth = 220.0
	@SceneStorage("entries.preferredListWidth") private var preferredEntryListWidth = 320.0

	private var displayedEntries: [ThingsDiaryEntry] {
		visibleEntries(listEntries, selection: activeSelection, query: query, sort: .newest)
	}

	private var listEntries: [ThingsDiaryEntry] {
		entries.filter { !model.entryDraftIDsHiddenFromList.contains($0.id) }
	}

	private var activeSelection: DiaryNavigationSelection { selection ?? .entries }
	private var selectionIsEmpty: Bool { count(for: activeSelection) == 0 }

	private var selectedEntry: ThingsDiaryEntry? {
		guard case .entry(let entryID) = tabs.activeTabID else { return nil }
		return entries.first { $0.id == entryID }
	}

	private var selectedDraftContent: String {
		guard let selectedEntry else { return "" }
		return draftsByEntryID[selectedEntry.id] ?? selectedEntry.content
	}

	private var selectedDraftBinding: Binding<String> {
		Binding(
			get: { selectedDraftContent },
			set: { value in
				guard case .entry(let entryID) = tabs.activeTabID else { return }
				tabs.promote(.entry(entryID))
				draftsByEntryID[entryID] = value
			}
		)
	}

	private var selectedTemplate: ThingsDiaryTemplate? {
		guard case .template(let templateID) = tabs.activeTabID else { return nil }
		return model.templates.first { $0.id == templateID }
	}

	private var selectedTemplateDraft: String {
		guard let selectedTemplate else { return "" }
		return templateDraftsByID[selectedTemplate.id] ?? selectedTemplate.content
	}

	private var selectedTemplateDraftBinding: Binding<String> {
		Binding(
			get: { selectedTemplateDraft },
			set: { value in
				guard case .template(let templateID) = tabs.activeTabID else { return }
				tabs.promote(.template(templateID))
				templateDraftsByID[templateID] = value
			}
		)
	}

	private var activeTabDraftBinding: Binding<String> {
		switch tabs.activeTabID {
		case .entry:
			selectedDraftBinding
		case .template:
			selectedTemplateDraftBinding
		case nil:
			.constant("")
		}
	}

	private var activeTabEditorIsReadOnly: Bool {
		guard case .entry = tabs.activeTabID, let selectedEntry else { return false }
		return selectedEntry.deletedAt != nil || selectedEntry.archived
	}

	private var canSaveActiveTab: Bool {
		switch tabs.activeTabID {
		case .entry:
			guard let selectedEntry else { return false }
			return canSave(selectedEntry)
		case .template(let templateID):
			guard let selectedTemplate else { return false }
			return model.templateDraftIDs.contains(templateID)
				|| selectedTemplateDraft != selectedTemplate.content
		case nil:
			return false
		}
	}

	private func tabPersistedContent(_ tabID: WorkspaceTabID) -> String {
		switch tabID {
		case .entry(let entryID):
			entries.first { $0.id == entryID }?.content ?? ""
		case .template(let templateID):
			model.templates.first { $0.id == templateID }?.content ?? ""
		}
	}

	private func tabDraftContent(_ tabID: WorkspaceTabID) -> String {
		switch tabID {
		case .entry(let entryID):
			return draftsByEntryID[entryID] ?? tabPersistedContent(tabID)
		case .template(let templateID):
			return templateDraftsByID[templateID] ?? tabPersistedContent(tabID)
		}
	}

	private func tabTitle(_ tabID: WorkspaceTabID) -> String {
		switch tabID {
		case .entry:
			entryListPresentation(content: tabDraftContent(tabID)).title
		case .template:
			templateListPresentation(content: tabDraftContent(tabID)).title
		}
	}

	private var validTabIDs: Set<WorkspaceTabID> {
		Set(entries.map { .entry($0.id) } + model.templates.map { .template($0.id) })
	}

	private var effectiveListWidth: CGFloat {
		effectiveEntryListWidth(
			preferredWidth: CGFloat(preferredEntryListWidth),
			availableWidth: availableWorkspaceWidth
		)
	}

	private var browserTabCloseAlertPresented: Binding<Bool> {
		Binding(
			get: { pendingBrowserTabClose != nil },
			set: { isPresented in
				if !isPresented {
					pendingBrowserTabClose = nil
					browserTabCloseSaveError = nil
				}
			}
		)
	}

	private func count(for selection: DiaryNavigationSelection) -> Int {
		if selection == .templates {
			return model.templates.count
		}
		return visibleEntries(listEntries, selection: selection, query: "", sort: .newest).count
	}

	var body: some View {
		workspaceShell
			.onChange(of: selection) {
				query = ""
				searchIsFocused = false
				searchResetID += 1
			}
			.onChange(of: selectionIsEmpty) {
				guard selectionIsEmpty else { return }
				query = ""
				searchIsFocused = false
				searchResetID += 1
			}
			.onChange(of: entries.map(\.id)) { entryIDs in
				let validTabIDs = Set(
					entryIDs.map(WorkspaceTabID.entry)
						+ model.templates.map { WorkspaceTabID.template($0.id) }
				)
				tabs.reconcile(validTabIDs: validTabIDs)
			}
			.onChange(of: entries) { previousEntries, updatedEntries in
				for updatedEntry in updatedEntries {
					guard
						let previousEntry = previousEntries.first(where: {
							$0.id == updatedEntry.id
						}),
						previousEntry.content != updatedEntry.content,
						let currentDraft = draftsByEntryID[updatedEntry.id]
					else { continue }
					draftsByEntryID[updatedEntry.id] = reconciledDraftAfterRemoteUpdate(
						currentDraft: currentDraft,
						previousPersistedContent: previousEntry.content,
						updatedPersistedContent: updatedEntry.content
					)
				}
			}
			.onChange(of: model.templates.map(\.id)) { templateIDs in
				let validTabIDs = Set(
					entries.map { WorkspaceTabID.entry($0.id) }
						+ templateIDs.map(WorkspaceTabID.template)
				)
				tabs.reconcile(validTabIDs: validTabIDs)
			}
			.onChange(of: model.templates) { previousTemplates, updatedTemplates in
				for updatedTemplate in updatedTemplates {
					guard
						let previousTemplate = previousTemplates.first(where: {
							$0.id == updatedTemplate.id
						}),
						previousTemplate.content != updatedTemplate.content,
						let currentDraft = templateDraftsByID[updatedTemplate.id]
					else { continue }
					templateDraftsByID[updatedTemplate.id] = reconciledDraftAfterRemoteUpdate(
						currentDraft: currentDraft,
						previousPersistedContent: previousTemplate.content,
						updatedPersistedContent: updatedTemplate.content
					)
				}
			}
			.onChange(of: model.diaryEditRequestID) {
				presentRequestedDiaryEditor()
			}
			.task { presentRequestedDiaryEditor() }
			.sheet(isPresented: $showingDiaryEditor) { diaryEditorSheet }
			.sheet(isPresented: $showingTopicCreator) { topicCreatorSheet }
			.alert(
				"Delete Topic?",
				isPresented: Binding(
					get: { topicPendingDeletion != nil },
					set: { if !$0 { topicPendingDeletion = nil } }
				)
			) {
				if topicPendingDeletionEntryCount == 0 {
					Button("Delete Topic", role: .destructive) {
						deletePendingTopic(deleteEntries: false)
					}
				} else {
					Button("Delete Entries", role: .destructive) {
						deletePendingTopic(deleteEntries: true)
					}
					Button("Keep Entries") {
						deletePendingTopic(deleteEntries: false)
					}
				}
				Button("Cancel", role: .cancel) { topicPendingDeletion = nil }
			} message: {
				Text(topicDeletionMessage)
			}
			.alert(
				entryConfirmationTitle,
				isPresented: Binding(
					get: { pendingEntryAction != nil },
					set: { if !$0 { pendingEntryAction = nil } }
				)
			) {
				Button(entryConfirmationButtonTitle, role: .destructive) { confirmPendingEntryAction() }
				Button("Cancel", role: .cancel) { pendingEntryAction = nil }
			} message: {
				Text(entryConfirmationMessage)
			}
			.alert("Empty Trash?", isPresented: $confirmingEmptyTrash) {
				Button("Empty Trash", role: .destructive) { Task { await model.emptyTrash() } }
				Button("Cancel", role: .cancel) {}
			} message: {
				Text("All entries in Trash will be deleted permanently. This cannot be undone.")
			}
			.alert(
				"Delete Template?",
				isPresented: Binding(
					get: { templatePendingDeletion != nil },
					set: { if !$0 { templatePendingDeletion = nil } }
				)
			) {
				Button("Delete", role: .destructive) { deletePendingTemplate() }
				Button("Cancel", role: .cancel) { templatePendingDeletion = nil }
			} message: {
				Text("Topics that use this template will return to no default template.")
			}
	}

	private var workspaceShell: some View {
		HStack(spacing: 0) {
			if sidebarToggleInSidebar {
				sidebarWorkspace
					.frame(width: effectiveSidebarWidth)
					.frame(maxHeight: .infinity)

				sidebarDivider
			}

			entryWorkspace
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.animation(.easeInOut(duration: 0.24), value: sidebarToggleInSidebar)
		.animation(.easeInOut(duration: 0.24), value: isEntryListCollapsed)
		.background {
			WorkspaceShortcutMonitor(
				save: {
					guard tabs.activeTabID != nil else { return false }
					saveActiveTab()
					return true
				},
				create: {
					createDocumentForActiveSection()
					return true
				},
				selectNextTab: {
					guard tabs.openTabIDs.count > 1 else { return true }
					selectBrowserTab(offset: 1)
					return true
				},
				selectPreviousTab: {
					guard tabs.openTabIDs.count > 1 else { return true }
					selectBrowserTab(offset: -1)
					return true
				}
			)
			.frame(width: 0, height: 0)
		}
		.focusedSceneValue(
			\.entrySaveAction,
			tabs.activeTabID != nil ? { saveActiveTab() } : nil
		)
		.focusedSceneValue(
			\.entrySaveAllAction,
			tabs.openTabIDs.isEmpty ? nil : { saveAllOpenTabs() }
		)
		.focusedSceneValue(
			\.entryCreateAction,
			EntryCreationActions(
				newEntry: createEntryFromMenu,
				newBookmark: createBookmarkFromMenu,
				newTemplate: createTemplate
			)
		)
		.focusedSceneValue(
			\.selectNextTabAction,
			tabs.openTabIDs.count > 1 ? { selectBrowserTab(offset: 1) } : nil
		)
		.focusedSceneValue(
			\.selectPreviousTabAction,
			tabs.openTabIDs.count > 1 ? { selectBrowserTab(offset: -1) } : nil
		)
		.focusedSceneValue(
			\.entryCloseAction,
			tabs.activeTabID != nil
				? {
					guard let activeTabID = tabs.activeTabID else { return }
					closeBrowserTab(activeTabID)
				} : nil
		)
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
		.background(
			WorkspaceWindowChrome(
				title: selectionTitle,
				trafficLightsTrailingInset: $trafficLightsTrailingInset
			)
		)
		.ignoresSafeArea(.container, edges: .top)
		.onPreferenceChange(EntryDropTargetFramesKey.self) { frames in
			dropTargetFrames = frames
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
			maxHeight: .infinity
		)
	}

	private var sidebarWorkspace: some View {
		VStack(spacing: 0) {
			Color.clear
				.frame(maxWidth: .infinity)
				.frame(height: workspaceTitlebarHeight)
				.fixedSize(horizontal: false, vertical: true)
				.layoutPriority(1)
				.background(WorkspaceWindowDragArea())
				.overlay(alignment: .trailing) {
					if sidebarToggleInSidebar {
						workspaceNavigationControls
							.padding(.trailing, 10)
					}
				}
			sidebar
		}
		.ignoresSafeArea(.container, edges: .top)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var effectiveSidebarWidth: CGFloat {
		min(max(CGFloat(preferredSidebarWidth), minimumSidebarWidth), maximumSidebarWidth)
	}

	private var sidebarDivider: some View {
		WorkspaceVerticalResizeDivider(
			accessibilityIdentifier: "workspace.sidebar-divider",
			onChanged: { translation in
				let start = dragStartSidebarWidth ?? effectiveSidebarWidth
				dragStartSidebarWidth = start
				preferredSidebarWidth = Double(
					min(max(start + translation, minimumSidebarWidth), maximumSidebarWidth)
				)
			},
			onEnded: { dragStartSidebarWidth = nil }
		)
	}

	private var entryWorkspace: some View {
		VStack(spacing: 0) {
			workspaceHeader
			Divider()
			adaptiveWorkspace
		}
		.ignoresSafeArea(.container, edges: .top)
		.background(.background)
	}

	private var workspaceHeader: some View {
		GeometryReader { proxy in
			let availableWidth = max(proxy.size.width, 0)
			let listWidth = effectiveEntryListWidth(
				preferredWidth: CGFloat(preferredEntryListWidth),
				availableWidth: availableWidth
			)
			let browserWidth: CGFloat =
				switch currentWorkspaceLayout {
				case .listOnly: 0
				case .split: max(availableWidth - listWidth - entryListDividerWidth, 0)
				case .editorOnly: availableWidth
				}

			ZStack(alignment: .trailing) {
				HStack(spacing: 0) {
					entryListTitlebar
						.frame(
							width: currentWorkspaceLayout == .listOnly ? availableWidth : listWidth
						)
					if currentWorkspaceLayout != .listOnly {
						entryListDivider(
							isInteractive: currentWorkspaceLayout == .split,
							height: workspaceTitlebarHeight,
							accessibilityIdentifier: "workspace.entry-list-divider.header"
						)
					}
				}
					.frame(maxWidth: .infinity, alignment: .leading)
					.allowsHitTesting(currentWorkspaceLayout != .editorOnly)
					.accessibilityHidden(currentWorkspaceLayout == .editorOnly)

				HStack(spacing: 0) {
					browserTabsBar
				}
				.frame(width: browserWidth, alignment: .trailing)
				.background(TitlebarMaterialBackground())
				.clipped()
				.allowsHitTesting(currentWorkspaceLayout != .listOnly)
				.accessibilityHidden(currentWorkspaceLayout == .listOnly)
				.zIndex(1)
			}
		}
		.frame(height: workspaceTitlebarHeight)
		.fixedSize(horizontal: false, vertical: true)
		.layoutPriority(1)
		.background(TitlebarMaterialBackground())
		.overlay(alignment: .leading) {
			ZStack(alignment: .leading) {
				if !sidebarToggleInSidebar {
					workspaceHeaderNavigationControls
				}
				if !sidebarToggleInSidebar {
					workspaceHeaderNavigationDivider
						.transition(.identity)
				}
			}
		}
		.animation(.easeInOut(duration: 0.24), value: currentWorkspaceLayout)
	}

	private var entryListTitlebar: some View {
		HStack(spacing: 10) {
			Text(selectionTitle)
				.font(.headline)
				.lineLimit(1)
				.opacity(currentWorkspaceLayout != .editorOnly ? 1 : 0)
				.accessibilityHidden(currentWorkspaceLayout == .editorOnly)
				.accessibilityIdentifier("entry-list.section-title")

			Spacer(minLength: 8)

			if currentWorkspaceLayout == .listOnly, tabs.activeTabID != nil {
				Button {
					compactWorkspacePane = .editor
				} label: {
					Image(systemName: "doc.text")
				}
				.frame(width: 28, height: 28)
				.accessibilityIdentifier("workspace.show-editor")
				.accessibilityLabel("Show Editor")
				.help("Show Editor")
			}

			entryListTitlebarAction
		}
		.buttonStyle(.borderless)
		.frame(
			maxWidth: .infinity,
			minHeight: workspaceTitlebarHeight,
			maxHeight: workspaceTitlebarHeight
		)
		.padding(
			.leading,
			sidebarToggleInSidebar
				? listPaneHorizontalInset
				: workspaceHeaderNavigationControlsReservedWidth
		)
		.padding(.trailing, listPaneHorizontalInset)
		.background(WorkspaceWindowDragArea())
		.animation(.easeInOut(duration: 0.24), value: sidebarToggleInSidebar)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("entry-list.titlebar")
	}

	private var entryListTitlebarAction: some View {
		ZStack {
			entryListTitlebarActionContent
				.id(activeSelection)
				.transition(.opacity)
		}
		.frame(width: 30, height: 30)
		.opacity(
			sidebarToggleInSidebar && currentWorkspaceLayout != .editorOnly ? 1 : 0
		)
		.allowsHitTesting(
			sidebarToggleInSidebar && currentWorkspaceLayout != .editorOnly
		)
		.accessibilityHidden(
			!sidebarToggleInSidebar || currentWorkspaceLayout == .editorOnly
		)
		.animation(.easeInOut(duration: 0.16), value: activeSelection)
	}

	@ViewBuilder private var entryListTitlebarActionContent: some View {
		switch activeSelection {
		case .trash:
			IconButton(
				icon: displayedEntries.isEmpty ? .trashEmpty : .trash,
				iconSize: 18
			) {
				confirmingEmptyTrash = true
			}
			.disabled(displayedEntries.isEmpty)
			.accessibilityIdentifier("trash.empty")
			.accessibilityLabel("Empty Trash")
			.help("Empty Trash")
		case .templates:
			IconButton(icon: .newEntry, action: createTemplate)
				.accessibilityIdentifier("template.create")
				.accessibilityLabel("New Template")
				.help("New Template")
		case .archive:
			Color.clear
		case .entries, .bookmarks, .topic:
			IconButton(icon: .newEntry, action: beginCreatingEntry)
				.accessibilityIdentifier("entry.create")
				.accessibilityLabel("New Entry")
				.help("Create a new entry")
		}
	}

	private var sidebarToggleButton: some View {
		IconButton(icon: .panelLeft, action: toggleSidebar)
			.accessibilityIdentifier("sidebar.toggle")
			.accessibilityLabel(sidebarToggleInSidebar ? "Hide Sidebar" : "Show Sidebar")
			.help(sidebarToggleInSidebar ? "Hide Sidebar" : "Show Sidebar")
	}

	private var animatedSidebarToggleButton: some View {
		sidebarToggleButton
			.matchedGeometryEffect(
				id: "workspace-sidebar-toggle",
				in: workspaceControlsNamespace,
				properties: .position,
				anchor: .center
			)
			.zIndex(2)
	}

	private var entryListToggleButton: some View {
		IconButton(icon: .menu, action: toggleEntryList)
			.accessibilityIdentifier(
				currentWorkspaceLayout == .editorOnly
					? "workspace.show-entry-list"
					: "workspace.hide-entry-list"
			)
			.accessibilityLabel(
				currentWorkspaceLayout == .editorOnly ? "Show Entry List" : "Hide Entry List"
			)
			.help(currentWorkspaceLayout == .editorOnly ? "Show Entry List" : "Hide Entry List")
	}

	private var animatedEntryListToggleButton: some View {
		entryListToggleButton
			.matchedGeometryEffect(
				id: "workspace-entry-list-toggle",
				in: workspaceControlsNamespace,
				properties: .position,
				anchor: .center
			)
			.zIndex(2)
	}

	private var workspaceNavigationControls: some View {
		HStack(spacing: 4) {
			animatedSidebarToggleButton
			animatedEntryListToggleButton
		}
		.fixedSize(horizontal: true, vertical: false)
	}

	private var workspaceHeaderNavigationControls: some View {
		HStack(spacing: 8) {
			Color.clear.frame(width: trafficLightsTrailingInset)
			workspaceNavigationControls
		}
		.padding(.leading, 10)
		.fixedSize(horizontal: true, vertical: false)
	}

	private var workspaceHeaderNavigationDivider: some View {
		Rectangle()
			.fill(Color(nsColor: .separatorColor))
			.frame(width: 1, height: 24)
			.offset(
				x: 10 + trafficLightsTrailingInset + 8 + 64 + 8
			)
			.allowsHitTesting(false)
	}

	private var workspaceHeaderNavigationControlsReservedWidth: CGFloat {
		10 + trafficLightsTrailingInset + 8 + 64 + 8 + 1 + 8
	}

	private var browserTabsBar: some View {
		let tabWidth = adaptiveBrowserTabWidth(
			availableWidth: availableBrowserTabsWidth,
			tabCount: tabs.openTabIDs.count
		)

		return HStack(spacing: 8) {
			browserTabsStrip(tabWidth: tabWidth)
				.frame(maxWidth: .infinity)
		}
		.frame(maxWidth: .infinity)
		.frame(height: workspaceTitlebarHeight)
		.padding(
			.leading,
			!sidebarToggleInSidebar && currentWorkspaceLayout == .editorOnly
				? workspaceHeaderNavigationControlsReservedWidth
				: 0
		)
		.padding(.trailing, workspaceTitlebarHorizontalInset)
		.background {
			WorkspaceWindowDragArea()
		}
		.animation(.easeInOut(duration: 0.24), value: sidebarToggleInSidebar)
		.animation(.easeInOut(duration: 0.24), value: currentWorkspaceLayout)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("browser-tabs.titlebar")
		.alert(
			"Save changes to \"\(pendingBrowserTabClose?.title ?? "this tab")\"?",
			isPresented: browserTabCloseAlertPresented,
			presenting: pendingBrowserTabClose
		) { request in
			Button("Don't Save", role: .destructive) {
				closeBrowserTabImmediately(request.tabID)
				pendingBrowserTabClose = nil
				DispatchQueue.main.async {
					processNextBrowserTabClose()
				}
			}
			Button("Cancel", role: .cancel) {
				pendingBrowserTabClose = nil
				pendingBrowserTabCloseQueue = []
			}
			Button("Save") {
				saveBrowserTabBeforeClosing(request)
			}
			.keyboardShortcut(.defaultAction)
		} message: { _ in
			Text(
				browserTabCloseSaveError
					?? "If you don't save, your changes will be lost."
			)
		}
	}

	private func browserTabsStrip(tabWidth: CGFloat) -> some View {
		GeometryReader { proxy in
			let tabsContentWidth = browserTabsContentWidth(
				tabWidth: tabWidth,
				tabCount: tabs.openTabIDs.count
			)
			let createButtonOffset = browserTabCreateButtonOffset(
				availableWidth: proxy.size.width,
				tabsContentWidth: tabsContentWidth
			)
			let tabsViewportWidth = browserTabsViewportWidth(
				createButtonOffset: createButtonOffset
			)
			let createButtonIsPinned = browserTabCreateButtonIsPinned(
				availableWidth: proxy.size.width,
				tabsContentWidth: tabsContentWidth
			)
			let hidesCreateButton = shouldHideBrowserTabCreateButton(
				isReordering: browserTabReorderSession != nil,
				isPinned: createButtonIsPinned
			)

			ZStack(alignment: .leading) {
				WorkspaceWindowDragArea()

				ScrollViewReader { scrollProxy in
					ScrollView(.horizontal, showsIndicators: false) {
						ZStack(alignment: .leading) {
							if let browserTabReorderSession {
								browserTabPlaceholder(width: tabWidth)
									.offset(
										x: CGFloat(browserTabReorderSession.placeholderIndex)
											* (tabWidth + browserTabSpacing)
									)
									.animation(
										.smooth(duration: 0.16),
										value: browserTabReorderSession.placeholderIndex
									)
							}

							HStack(spacing: browserTabSpacing) {
								ForEach(Array(tabs.openTabIDs.enumerated()), id: \.element) { index, tabID in
									browserTabView(tabID, at: index, width: tabWidth)
								}
							}
						}
						.padding(.leading, browserTabLeadingPadding)
					}
					.frame(width: tabsViewportWidth, height: workspaceTitlebarHeight)
					.clipped()
					.onChange(of: tabs.activeTabID) {
						guard
							createButtonIsPinned,
							let activeTabID = tabs.activeTabID
						else { return }
						withAnimation(.easeInOut(duration: 0.16)) {
							scrollProxy.scrollTo(activeTabID, anchor: .center)
						}
					}
				}
				.frame(
					width: tabsViewportWidth,
					height: workspaceTitlebarHeight,
					alignment: .leading
				)

				IconButton(
					icon: .plus,
					usesTitlebarBackground: true,
					action: beginCreatingBrowserTab
				)
				.frame(width: browserTabCreateButtonWidth)
				.accessibilityIdentifier("browser-tab.create")
				.accessibilityLabel("New Entry")
				.help("New Entry")
				.offset(x: createButtonOffset)
				.opacity(hidesCreateButton ? 0 : 1)
				.allowsHitTesting(!hidesCreateButton)
				.accessibilityHidden(hidesCreateButton)
				.zIndex(4)
			}
			.frame(
				maxWidth: .infinity,
				maxHeight: .infinity,
				alignment: .leading
			)
			.onAppear { availableBrowserTabsWidth = proxy.size.width }
			.onChange(of: proxy.size.width) {
				availableBrowserTabsWidth = proxy.size.width
			}
		}
	}

	private func browserTabView(
		_ tabID: WorkspaceTabID,
		at index: Int,
		width: CGFloat
	) -> some View {
		return ZStack {
			Color.clear
			BrowserTab(
				accessibilityIdentifier: tabID.tabAccessibilityID,
				closeAccessibilityIdentifier: tabID.closeAccessibilityID,
				title: tabTitle(tabID),
				width: width,
				isActive: tabs.activeTabID == tabID,
				isDirty: tabDraftContent(tabID) != tabPersistedContent(tabID),
				isPinned: tabs.isPinned(tabID),
				isPreview: tabs.isPreview(tabID),
				isDragged: browserTabReorderSession?.tabID == tabID,
				horizontalOffset: browserTabReorderSession?.offset(
					forTabAt: index,
					tabWidth: width
				) ?? 0,
				activate: { activateBrowserTab(tabID) },
				close: { closeBrowserTab(tabID) },
				reorder: { translation in
					updateBrowserTabReorder(
						tabID: tabID,
						translationX: translation,
						tabWidth: width
					)
				},
				finishReordering: { finishReorderingBrowserTab(tabID) }
			)
		}
		.frame(width: width, height: workspaceTitlebarHeight)
		.contentShape(Rectangle())
		.id(tabID)
		.contextMenu {
			browserTabContextMenu(for: tabID, at: index)
		}
	}

	private func browserTabPlaceholder(width: CGFloat) -> some View {
		RoundedRectangle(cornerRadius: 7, style: .continuous)
			.fill(Color.primary.opacity(0.035))
			.overlay {
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.stroke(
						Color.secondary.opacity(0.32),
						style: StrokeStyle(lineWidth: 1, dash: [4, 3])
					)
			}
			.frame(width: width, height: 30)
			.allowsHitTesting(false)
			.accessibilityIdentifier("entry-tab.placeholder")
	}

	private var adaptiveWorkspace: some View {
		GeometryReader { proxy in
			let availableWidth = max(proxy.size.width, 0)
			let compact = updatedEditorWorkspaceCompactState(
				isCompact: isEditorWorkspaceCompact,
				hasSelectedEntry: tabs.activeTabID != nil,
				availableWidth: availableWidth,
				isDragging: draggedEntryID != nil
			)
			let layout = entryWorkspaceLayout(
				hasSelectedEntry: tabs.activeTabID != nil,
				availableWidth: availableWidth,
				isEntryListCollapsed: isEntryListCollapsed,
				isCompact: compact,
				compactPane: compactWorkspacePane
			)

			workspace(layout: layout, availableWidth: availableWidth)
				.onAppear {
					currentWorkspaceLayout = layout
					availableWorkspaceWidth = availableWidth
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: availableWidth) {
					availableWorkspaceWidth = availableWidth
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: layout) {
					currentWorkspaceLayout = layout
				}
				.onChange(of: tabs.activeTabID) {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
				.onChange(of: draggedEntryID) {
					updateEditorWorkspaceCompactState(availableWidth: availableWidth)
				}
		}
	}

	private var filteredTemplates: [ThingsDiaryTemplate] {
		let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		return model.templates
			.filter { trimmedQuery.isEmpty || $0.content.localizedCaseInsensitiveContains(trimmedQuery) }
			.sorted {
				$0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
			}
	}

	private var templateListPane: some View {
		Group {
			if model.templates.isEmpty { templateEmptyState } else { templateList }
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.background(.background)
	}

	private var templateEmptyState: some View {
		ContentUnavailableView {
			Label("Templates", systemImage: "doc.on.doc")
		} description: {
			Text("Reuse the same structure when you start a new entry.")
		} actions: {
			Button("New Template", systemImage: "square.and.pencil", action: createTemplate)
				.buttonStyle(.borderedProminent)
				.accessibilityIdentifier("template.empty-create")
		}
		.accessibilityIdentifier("template.empty-state")
	}

	private var templateList: some View {
		VStack(spacing: 0) {
			SearchBox(
				text: $query,
				isFocused: $searchIsFocused,
				resetID: searchResetID,
				prompt: "Search templates",
				accessibilityLabel: "Search Templates"
			)
			.padding(.horizontal, listPaneHorizontalInset)
			.padding(.vertical, 10)

			if filteredTemplates.isEmpty {
				ContentUnavailableView {
					Label("No Results", systemImage: "magnifyingglass")
				} description: {
					Text("Try another search term.")
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				ScrollView {
					LazyVStack(spacing: 0) {
						ForEach(filteredTemplates) { template in
							templateRow(template)
							Divider().padding(.horizontal, listPaneHorizontalInset)
						}
					}
				}
			}
		}
	}

	private func templateRow(_ template: ThingsDiaryTemplate) -> some View {
		let draft = templateDraftsByID[template.id] ?? template.content
		let presentation = templateListPresentation(content: draft)
		return Button {
			previewTemplate(template)
		} label: {
			VStack(alignment: .leading, spacing: 5) {
				HStack {
					Text(presentation.title)
						.font(.headline)
						.lineLimit(1)
					Spacer()
					Text(template.createdAt.formatted(date: .abbreviated, time: .omitted))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				if let preview = presentation.preview {
					Text(preview)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
			.padding(.horizontal, listPaneHorizontalInset)
			.padding(.vertical, 10)
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier("template.\(template.id)")
		.contextMenu {
			Button("Delete Template", systemImage: "trash", role: .destructive) {
				templatePendingDeletion = template
			}
		}
	}

	@ViewBuilder private func workspace(
		layout: EntryWorkspaceLayout,
		availableWidth: CGFloat
	) -> some View {
		let listWidth = effectiveEntryListWidth(
			preferredWidth: CGFloat(preferredEntryListWidth),
			availableWidth: availableWidth
		)
		let browserWidth: CGFloat =
			switch layout {
			case .listOnly: 0
			case .split: max(availableWidth - listWidth - entryListDividerWidth, 0)
			case .editorOnly: availableWidth
			}

		ZStack(alignment: .trailing) {
			HStack(spacing: 0) {
				entryListPane()
					.frame(width: layout == .listOnly ? availableWidth : listWidth)
					.opacity(layout == .editorOnly ? 0 : 1)
				if layout != .listOnly {
					entryListDivider(
						isInteractive: layout == .split,
						accessibilityIdentifier: "workspace.entry-list-divider.content"
					)
				}
			}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
				.allowsHitTesting(layout != .editorOnly)
				.accessibilityHidden(layout == .editorOnly)

			HStack(spacing: 0) {
				entryDetailPane(layout: layout)
					.frame(minWidth: minimumEntryEditorWidth, maxWidth: .infinity, maxHeight: .infinity)
			}
			.frame(width: browserWidth, alignment: .trailing)
			.frame(maxHeight: .infinity)
			.background(.background)
			.clipped()
			.allowsHitTesting(layout != .listOnly)
			.accessibilityHidden(layout == .listOnly)
			.zIndex(1)
			.accessibilityElement(children: .contain)
			.accessibilityIdentifier(layout == .split ? "workspace.split" : "workspace.editor")
		}
		.animation(.easeInOut(duration: 0.24), value: layout)
	}

	@ViewBuilder private func entryListDivider(
		isInteractive: Bool,
		height: CGFloat? = nil,
		accessibilityIdentifier: String
	) -> some View {
		let separator = Rectangle()
			.fill(Color(nsColor: .separatorColor))
			.frame(width: 1)
			.allowsHitTesting(false)

		if isInteractive {
			WorkspaceVerticalResizeDivider(
				accessibilityIdentifier: accessibilityIdentifier,
				height: height,
				onChanged: { translation in
					let start = dragStartEntryListWidth ?? effectiveListWidth
					dragStartEntryListWidth = start
					preferredEntryListWidth = Double(
						min(
							max(start + translation, minimumEntryListWidth),
							440
						)
					)
				},
				onEnded: { dragStartEntryListWidth = nil }
			)
		} else {
			ZStack {
				Color.clear
				separator
			}
			.frame(width: entryListDividerWidth, height: height)
			.contentShape(.rect)
			.accessibilityIdentifier(accessibilityIdentifier)
		}
	}

	private func updateEditorWorkspaceCompactState(availableWidth: CGFloat) {
		isEditorWorkspaceCompact = updatedEditorWorkspaceCompactState(
			isCompact: isEditorWorkspaceCompact,
			hasSelectedEntry: tabs.activeTabID != nil,
			availableWidth: availableWidth,
			isDragging: draggedEntryID != nil
		)
	}

	private func entryListPane() -> some View {
		Group {
			if activeSelection == .templates {
				templateListPane
			} else if selectionIsEmpty {
				emptyStateView
			} else {
				VStack(spacing: 0) {
					entryListHeader

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
	}

	@ViewBuilder private func entryDetailPane(layout: EntryWorkspaceLayout) -> some View {
		if let activeTabID = tabs.activeTabID {
			TextEditor(text: activeTabDraftBinding)
				.accessibilityIdentifier(activeTabID.editorAccessibilityID)
				.focused($editorIsFocused)
				.disabled(activeTabEditorIsReadOnly)
				.padding(.horizontal, 8)
				.padding(.vertical, 6)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(.background)
		} else if showsDiaryOverview(
			for: activeSelection,
			selectionIsEmpty: selectionIsEmpty
		) {
			diaryOverview
		} else {
			Color.clear
				.accessibilityHidden(true)
		}
	}

	private var diaryOverview: some View {
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

	private var sidebar: some View {
		VStack(spacing: 0) {
			diarySwitcher

			ScrollView {
				VStack(alignment: .leading, spacing: 4) {
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

					HStack(spacing: 8) {
						if model.topics.isEmpty {
							HStack(spacing: 8) {
								Image(systemName: "tag")
									.frame(width: 16)
									.foregroundStyle(.tint)
								Text("Topics")
									.lineLimit(1)
									.truncationMode(.tail)
									.frame(maxWidth: .infinity, alignment: .leading)
									.layoutPriority(1)
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
										.frame(maxWidth: .infinity, alignment: .leading)
										.layoutPriority(1)
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

						if topicsHeaderHovered || model.topics.isEmpty {
							Button {
								beginCreatingTopic()
							} label: {
								Image(systemName: "plus")
									.fixedSize()
							}
							.buttonStyle(.plain)
							.accessibilityIdentifier("topic.create")
							.accessibilityLabel("New Topic")
							.help("New Topic")
						}

						if !model.topics.isEmpty {
							Button {
								toggleTopics()
							} label: {
								Image(systemName: topicsExpanded ? "chevron.down" : "chevron.right")
									.font(.caption.weight(.semibold))
									.fixedSize()
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
							.contextMenu {
								Button("Edit", systemImage: "pencil") {
									beginEditing(topic)
								}
								Button("Delete", systemImage: "trash", role: .destructive) {
									topicPendingDeletion = topic
								}
							}
						}
					}

					sidebarRow(
						"Templates",
						systemImage: "doc.on.doc",
						destination: .templates,
						identifier: "sidebar.templates",
						showsCount: false
					)

					sidebarRow(
						"Archive",
						systemImage: "archivebox",
						destination: .archive,
						identifier: "sidebar.archive",
						showsCount: false,
						dropDestination: .archive
					)
					sidebarRow(
						"Trash",
						systemImage: "trash",
						destination: .trash,
						identifier: "sidebar.trash",
						showsCount: false,
						dropDestination: .trash
					)
					.overlay {
						WorkspaceContextMenuArea(
							title: "Empty Trash",
							systemImage: "trash",
							isEnabled: count(for: .trash) > 0,
							primaryAction: { selection = .trash },
							menuAction: { confirmingEmptyTrash = true }
						)
						.accessibilityHidden(true)
					}
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(maxWidth: .infinity)
		}
	}

	private var diarySwitcher: some View {
		Button {
			if showingDiaryMenu {
				showingDiaryMenu = false
			} else {
				hoveredDiaryID = nil
				showingDiaryMenu = true
			}
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
				Spacer(minLength: 0)
				Image(systemName: "chevron.up.chevron.down")
					.font(.caption2.weight(.semibold))
					.fixedSize()
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
		.accessibilityLabel("Current diary, \(diary.title)")
		.help("Switch Diary")
		.padding(.init(top: 6, leading: 6, bottom: 2, trailing: 6))
		.anchorPreference(key: DiarySwitcherAnchorKey.self, value: .bounds) { $0 }
		.accessibilityIdentifier("diary.switcher")
		.contextMenu {
			Button("Edit", systemImage: "square.and.pencil") {
				beginEditingDiary()
			}
			.accessibilityIdentifier("diary.edit.current")
		}
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
		let editControlVisible = diaryEditControlVisible(
			for: candidate.id,
			firstDiaryID: model.availableDiaries.first?.id,
			hoveredDiaryID: hoveredDiaryID
		)

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
				Task { await model.requestDiaryEdit(for: candidate) }
			} label: {
				Image(systemName: "gearshape")
					.frame(width: 24, height: 24)
					.contentShape(.rect)
			}
			.buttonStyle(.plain)
			.foregroundStyle(.secondary)
			.opacity(editControlVisible ? 1 : 0)
			.allowsHitTesting(editControlVisible)
			.accessibilityHidden(!editControlVisible)
			.accessibilityIdentifier("diary.edit.\(candidate.id)")
			.help("Edit \(candidate.title)")
		}
		.onHover { hovering in
			hoveredDiaryID = hovering ? candidate.id : nil
		}
	}

	private func presentRequestedDiaryEditor() {
		guard model.consumeDiaryEditRequest(for: diary.id) else { return }
		showingDiaryMenu = false
		beginEditingDiary()
	}

	private func beginCreatingEntry() {
		beginEntryDraft(appearsInList: true)
	}

	private func createDocumentForActiveSection() {
		if activeSelection == .templates {
			createTemplate()
		} else {
			beginCreatingEntry()
		}
	}

	private func createEntryFromMenu() {
		beginEntryDraft(appearsInList: true, inheritsSelection: false)
	}

	private func createBookmarkFromMenu() {
		selection = .bookmarks
		beginEntryDraft(appearsInList: true)
	}

	private func createTemplate() {
		Task {
			guard let template = await model.beginTemplateDraft() else { return }
			selection = .templates
			openTemplate(template)
			await Task.yield()
			editorIsFocused = true
		}
	}

	private func deletePendingTemplate() {
		guard let template = templatePendingDeletion else { return }
		templatePendingDeletion = nil
		Task {
			if await model.deleteTemplate(template) {
				templateDraftsByID.removeValue(forKey: template.id)
				closeBrowserTabImmediately(.template(template.id))
			}
		}
	}

	private func beginCreatingBrowserTab() {
		beginEntryDraft(appearsInList: true, inheritsSelection: false)
	}

	private func beginEntryDraft(
		appearsInList: Bool,
		inheritsSelection: Bool = true
	) {
		let topicID: String? =
			switch inheritsSelection ? activeSelection : .entries {
			case .topic(let topicID): topicID
			default: nil
			}
		let bookmarked = inheritsSelection && activeSelection == .bookmarks
		guard
			let draft = model.beginEntryDraft(
				appearsInList: appearsInList,
				topicID: topicID,
				bookmarked: bookmarked
			)
		else { return }
		if topicID == nil, !bookmarked {
			selection = .entries
		}
		openEntry(draft)
		Task { @MainActor in
			await Task.yield()
			editorIsFocused = true
		}
	}

	private func toggleSidebar() {
		withAnimation(.easeInOut(duration: 0.24)) {
			sidebarToggleInSidebar.toggle()
		}
	}

	private func toggleEntryList() {
		withAnimation(.easeInOut(duration: 0.24)) {
			if currentWorkspaceLayout == .editorOnly {
				isEntryListCollapsed = false
				compactWorkspacePane = .list
			} else {
				isEntryListCollapsed = true
				compactWorkspacePane = .editor
			}
		}
	}

	private func previewEntry(_ entry: ThingsDiaryEntry) {
		previewTab(.entry(entry.id))
		if draftsByEntryID[entry.id] == nil {
			draftsByEntryID[entry.id] = entry.content
		}
	}

	private func openEntry(_ entry: ThingsDiaryEntry) {
		tabs.open(.entry(entry.id))
		if draftsByEntryID[entry.id] == nil {
			draftsByEntryID[entry.id] = entry.content
		}
		compactWorkspacePane = .editor
	}

	private func previewTemplate(_ template: ThingsDiaryTemplate) {
		previewTab(.template(template.id))
		if templateDraftsByID[template.id] == nil {
			templateDraftsByID[template.id] = template.content
		}
	}

	private func openTemplate(_ template: ThingsDiaryTemplate) {
		tabs.open(.template(template.id))
		if templateDraftsByID[template.id] == nil {
			templateDraftsByID[template.id] = template.content
		}
		compactWorkspacePane = .editor
	}

	private func previewTab(_ tabID: WorkspaceTabID) {
		let replacedPreviewTabID = tabs.previewTabID
		tabs.preview(tabID)
		if replacedPreviewTabID != tabs.previewTabID, let replacedPreviewTabID {
			discardDraft(for: replacedPreviewTabID)
		}
		compactWorkspacePane = .editor
	}

	private func activateBrowserTab(_ tabID: WorkspaceTabID) {
		guard tabs.openTabIDs.contains(tabID) else { return }
		tabs.activeTabID = tabID
		compactWorkspacePane = .editor
	}

	private func selectBrowserTab(offset: Int) {
		tabs.selectTab(offset: offset)
		compactWorkspacePane = .editor
	}

	private func beginReorderingBrowserTab(_ tabID: WorkspaceTabID) {
		guard
			browserTabReorderSession == nil,
			let startIndex = tabs.openTabIDs.firstIndex(of: tabID)
		else { return }
		browserTabReorderSession = TabReorderSession(
			tabID: tabID,
			startIndex: startIndex
		)
		activateBrowserTab(tabID)
		NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
	}

	private func updateBrowserTabReorder(
		tabID: WorkspaceTabID,
		translationX: CGFloat,
		tabWidth: CGFloat
	) {
		if browserTabReorderSession == nil {
			beginReorderingBrowserTab(tabID)
		}
		guard var session = browserTabReorderSession, session.tabID == tabID else { return }
		let previousPlaceholderIndex = session.placeholderIndex
		session.update(
			translation: translationX,
			tabWidth: tabWidth,
			tabCount: tabs.openTabIDs.count,
			allowedRange: tabs.reorderRange(for: tabID)
		)
		browserTabReorderSession = session
		if session.placeholderIndex != previousPlaceholderIndex {
			NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
		}
	}

	private func finishReorderingBrowserTab(_ tabID: WorkspaceTabID) {
		guard let session = browserTabReorderSession, session.tabID == tabID else { return }
		var transaction = Transaction()
		transaction.disablesAnimations = true
		withTransaction(transaction) {
			session.commit(to: &tabs)
			browserTabReorderSession = nil
		}
	}

	@ViewBuilder private func browserTabContextMenu(
		for tabID: WorkspaceTabID,
		at index: Int
	) -> some View {
		let otherTabsToClose = tabs.closeableOtherTabIDs(keeping: tabID)
		let tabsToTheRight = Array(tabs.openTabIDs.dropFirst(index + 1))

		Button("Close", systemImage: "xmark") {
			closeBrowserTab(tabID)
		}
		Button("Close Other Tabs", systemImage: "xmark.square") {
			requestCloseBrowserTabs(otherTabsToClose)
		}
		.disabled(otherTabsToClose.isEmpty)
		Button("Close Tabs to the Right", systemImage: "arrow.right.to.line") {
			requestCloseBrowserTabs(tabsToTheRight)
		}
		.disabled(tabsToTheRight.isEmpty)

		Divider()

		Button(
			tabs.isPinned(tabID) ? "Unpin Tab" : "Pin Tab",
			systemImage: tabs.isPinned(tabID) ? "pin.slash" : "pin"
		) {
			tabs.togglePin(tabID)
		}

		Divider()
		browserTabDocumentActions(tabID)
	}

	@ViewBuilder private func browserTabDocumentActions(_ tabID: WorkspaceTabID) -> some View {
		switch tabID {
		case .entry(let entryID):
			if let entry = entries.first(where: { $0.id == entryID }) {
				entryTabDocumentActions(entry)
			}
		case .template(let templateID):
			if let template = model.templates.first(where: { $0.id == templateID }) {
				Button("Delete Template", systemImage: "trash", role: .destructive) {
					templatePendingDeletion = template
				}
			}
		}
	}

	@ViewBuilder private func entryTabDocumentActions(_ entry: ThingsDiaryEntry) -> some View {
		let isEphemeral = model.entryDraftIDs.contains(entry.id)
		let isDeleted = entry.deletedAt != nil

		Button(
			entry.bookmarked ? "Remove Bookmark" : "Add Bookmark",
			systemImage: entry.bookmarked ? "bookmark.slash" : "bookmark"
		) {
			perform(.toggleBookmark, on: entry, topicID: nil)
		}
		.disabled(isDeleted)

		Button("Duplicate", systemImage: "plus.square.on.square") {
			perform(.duplicate, on: entry, topicID: nil)
		}
		.disabled(isEphemeral || isDeleted)

		if !isDeleted,
			shouldShowTopicAssignmentMenu(
				topicCount: model.topics.count,
				currentTopicID: entry.topicID
			)
		{
			TopicAssignmentPicker(entry: entry, topics: model.topics) { topicID in
				perform(.moveToTopic, on: entry, topicID: topicID)
			}
		}

		Divider()

		Button(
			entry.archived ? "Restore from Archive" : "Archive",
			systemImage: entry.archived ? "tray.and.arrow.up" : "archivebox"
		) {
			perform(.toggleArchive, on: entry, topicID: nil)
		}
		.disabled(isEphemeral || isDeleted)

		Button("Move to Trash", systemImage: "trash", role: .destructive) {
			perform(.moveToTrash, on: entry, topicID: nil)
		}
		.disabled(isEphemeral || isDeleted)
	}

	private func closeBrowserTab(_ tabID: WorkspaceTabID) {
		requestCloseBrowserTabs([tabID])
	}

	private func requestCloseBrowserTabs(_ tabIDs: [WorkspaceTabID]) {
		guard pendingBrowserTabClose == nil else { return }
		pendingBrowserTabCloseQueue = tabIDs.filter(tabs.openTabIDs.contains)
		processNextBrowserTabClose()
	}

	private func processNextBrowserTabClose() {
		guard pendingBrowserTabClose == nil else { return }
		while !pendingBrowserTabCloseQueue.isEmpty {
			let tabID = pendingBrowserTabCloseQueue.removeFirst()
			guard tabSavingBeforeClose != tabID, validTabIDs.contains(tabID) else { continue }
			let persistedContent = tabPersistedContent(tabID)
			let draft = tabDraftContent(tabID)
			switch browserTabCloseDisposition(
				persistedContent: persistedContent,
				draftContent: draft
			) {
			case .close:
				closeBrowserTabImmediately(tabID)
			case .confirmDiscard:
				activateBrowserTab(tabID)
				browserTabCloseSaveError = nil
				pendingBrowserTabClose = PendingBrowserTabClose(
					tabID: tabID,
					title: tabTitle(tabID)
				)
				return
			}
		}
	}

	private func closeBrowserTabImmediately(_ tabID: WorkspaceTabID) {
		if case .entry(let entryID) = tabID, model.entryDraftIDs.contains(entryID) {
			model.discardEntryDraft(entryID)
		}
		if case .template(let templateID) = tabID,
			model.templateDraftIDs.contains(templateID),
			let template = model.templates.first(where: { $0.id == templateID })
		{
			Task { await model.deleteTemplate(template) }
		}
		discardDraft(for: tabID)
		tabs.close(tabID)
	}

	private func discardDraft(for tabID: WorkspaceTabID) {
		switch tabID {
		case .entry(let entryID): draftsByEntryID.removeValue(forKey: entryID)
		case .template(let templateID): templateDraftsByID.removeValue(forKey: templateID)
		}
	}

	private func saveActiveTab() {
		guard canSaveActiveTab, let activeTabID = tabs.activeTabID else { return }
		Task {
			_ = await saveTab(activeTabID, submittedContent: tabDraftContent(activeTabID))
		}
	}

	private func saveAllOpenTabs() {
		let submissions = tabs.openTabIDs.map { tabID in
			(tabID, tabDraftContent(tabID))
		}
		Task {
			for (tabID, submittedContent) in submissions {
				_ = await saveTab(tabID, submittedContent: submittedContent)
			}
		}
	}

	private func saveBrowserTabBeforeClosing(_ request: PendingBrowserTabClose) {
		guard tabSavingBeforeClose == nil, validTabIDs.contains(request.tabID) else { return }
		let submittedContent = tabDraftContent(request.tabID)
		pendingBrowserTabClose = nil
		browserTabCloseSaveError = nil
		tabSavingBeforeClose = request.tabID
		Task {
			let outcome = await saveTab(request.tabID, submittedContent: submittedContent)
			tabSavingBeforeClose = nil
			switch outcome {
			case .saved:
				closeBrowserTabImmediately(request.tabID)
				processNextBrowserTabClose()
			case .changedWhileSaving:
				pendingBrowserTabCloseQueue.insert(request.tabID, at: 0)
				processNextBrowserTabClose()
			case .failed:
				pendingBrowserTabCloseQueue = []
				guard tabs.openTabIDs.contains(request.tabID) else { return }
				browserTabCloseSaveError = "The document couldn't be saved. Your changes are still open."
				pendingBrowserTabClose = request
			}
		}
	}

	private func saveTab(
		_ tabID: WorkspaceTabID,
		submittedContent: String
	) async -> EntryDraftSaveOutcome {
		switch tabID {
		case .entry(let entryID):
			guard let entry = entries.first(where: { $0.id == entryID }) else { return .failed }
			return await saveEntryDraft(entry, entryID: entryID, submittedContent: submittedContent)
		case .template(let templateID):
			guard let template = model.templates.first(where: { $0.id == templateID }) else {
				return .failed
			}
			let didSave = await model.updateTemplate(template, content: submittedContent)
			let currentDraft = templateDraftsByID[templateID] ?? submittedContent
			guard currentDraft == submittedContent else { return .changedWhileSaving }
			guard didSave else { return .failed }
			templateDraftsByID.removeValue(forKey: templateID)
			return .saved
		}
	}

	private func saveEntryDraft(
		_ entry: ThingsDiaryEntry,
		entryID: String,
		submittedContent: String
	) async -> EntryDraftSaveOutcome {
		let didSave = await model.updateEntry(entry, content: submittedContent)
		let currentDraft = draftsByEntryID[entryID] ?? submittedContent
		guard currentDraft == submittedContent else {
			return .changedWhileSaving
		}
		guard
			didSave,
			case .entries(_, let currentEntries) = model.screen,
			let persistedEntry = currentEntries.first(where: { $0.id == entryID }),
			let reconciledDraft = reconciledEntryDraftAfterSave(
				currentDraft: currentDraft,
				submittedContent: submittedContent,
				persistedContent: persistedEntry.content
			)
		else { return .failed }
		draftsByEntryID[entryID] = reconciledDraft
		return .saved
	}

	private var entryListHeader: some View {
		SearchBox(
			text: $query,
			isFocused: $searchIsFocused,
			resetID: searchResetID,
			prompt: "Search \(selectionTitle.lowercased())",
			accessibilityLabel: "Search \(selectionTitle)"
		)
		.padding(.horizontal, listPaneHorizontalInset)
		.padding(.top, 12)
		.padding(.bottom, 6)
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
				if activeSelection == .entries || isTopicSelected {
					Button("New Entry", systemImage: "square.and.pencil") {
						beginCreatingEntry()
					}
					.buttonStyle(.borderedProminent)
				} else if activeSelection == .bookmarks {
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
						.padding(.horizontal, listPaneHorizontalInset)
						.frame(maxWidth: .infinity, alignment: .leading)
						.background(.background)
						.opacity(draggedEntryID == entry.id ? 0.45 : 1)
						.contentShape(.interaction, Rectangle())
						.onTapGesture {
							previewEntry(entry)
						}
						.highPriorityGesture(entryDragGesture(for: entry))
						.accessibilityElement(children: .combine)
						.accessibilityIdentifier("entry.\(entry.id)")
						.accessibilityAddTraits(.isButton)
						.contextMenu {
							entryActions(for: entry)
						}
						.overlay(alignment: .bottom) {
							Divider()
								.padding(.horizontal, listPaneHorizontalInset)
								.allowsHitTesting(false)
						}
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
		entry.deletedAt == nil
			&& !entry.archived
			&& (model.entryDraftIDs.contains(entry.id) || selectedDraftContent != entry.content)
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
		let dropTint =
			if dropDestination == .trash {
				Color.red
			} else if dropDestination == .bookmarks {
				topicColorValue("#FCD34D")
			} else {
				color ?? Color.accentColor
			}
		let rowCount = count(for: destination)

		return Button {
			selection = destination
		} label: {
			HStack(spacing: 8) {
				if let color {
					Circle()
						.fill(color)
						.frame(width: 8, height: 8)
						.frame(width: 16)
				} else {
					Image(
						systemName: isDropTargeted && dropDestination == .bookmarks
							? "bookmark.fill" : systemImage
					)
					.frame(width: 16)
					.foregroundStyle(
						isDropTargeted && dropDestination == .bookmarks
							? dropTint : Color.accentColor
					)
				}
				Text(title)
					.lineLimit(1)
					.truncationMode(.tail)
					.frame(maxWidth: .infinity, alignment: .leading)
					.layoutPriority(1)
				if isDropTargeted {
					Image(systemName: dropDestination == .trash ? "trash.fill" : "arrow.down.circle.fill")
						.foregroundStyle(dropTint)
						.fixedSize()
				} else if showsCount && rowCount > 0 {
					Text(rowCount, format: .number)
						.font(.caption.monospacedDigit())
						.foregroundStyle(.secondary)
						.fixedSize()
				}
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
		.simultaneousGesture(TapGesture(count: 2).onEnded { doubleClick?() })
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
		EntryActionsMenuContent(
			entry: entry,
			topics: model.topics,
			isEphemeral: model.entryDraftIDs.contains(entry.id)
		) { action, topicID in
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
		if action != .duplicate {
			tabs.promote(.entry(entry.id))
		}
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
			case .saveAsTemplate:
				let content = draftsByEntryID[entry.id] ?? entry.content
				if let template = await model.createTemplate(content: content) {
					selection = .templates
					openTemplate(template)
				}
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
				closeBrowserTab(.entry(entry.id))
			}
		}
	}

	private func shouldClearSelection(
		after action: EntryAction,
		entry: ThingsDiaryEntry,
		topicID: String?
	) -> Bool {
		guard tabs.activeTabID == .entry(entry.id) else { return false }
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
		case .duplicate, .saveAsTemplate:
			return false
		}
	}

	@ViewBuilder
	private func entryListRow(_ entry: ThingsDiaryEntry) -> some View {
		let presentation = entryListPresentation(
			content: draftsByEntryID[entry.id] ?? entry.content
		)
		let topic = model.topics.first { $0.id == entry.topicID }
		VStack(alignment: .leading, spacing: 6) {
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
					.truncationMode(.tail)
					.layoutPriority(1)
				Spacer(minLength: 8)
				if entry.bookmarked {
					Image(systemName: "bookmark.fill")
						.foregroundStyle(.tint)
						.fixedSize()
						.accessibilityLabel("Bookmarked")
				}
				Text(entryListTimestamp(entry.createdAt))
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize()
					.accessibilityLabel(
						entry.createdAt.formatted(date: .complete, time: .shortened)
					)
			}
			.frame(minHeight: 20)
			HStack(alignment: .top, spacing: 6) {
				if entry.archived {
					Label("Archived", systemImage: "archivebox.fill")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				} else if entry.deletedAt != nil {
					Label("In Trash", systemImage: "trash.fill")
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize()
				}
				if !entry.previewHidden,
					topic?.entryPreviewable != false,
					let preview = presentation.preview
				{
					Text(preview)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.lineLimit(3)
						.truncationMode(.tail)
						.padding(.vertical, 1)
				}
				Spacer(minLength: 0)
			}
			.frame(maxWidth: .infinity, alignment: .topLeading)
		}
		.contentShape(.rect)
		.padding(.top, 6)
		.padding(.bottom, 12)
	}

	private var emptyStateTitle: String {
		if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			return "No Results"
		}
		return switch activeSelection {
		case .entries: "No Entries Yet"
		case .bookmarks: "No Bookmarks Yet"
		case .topic: "No Entries in This Topic"
		case .templates: "No Templates Yet"
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
		case .topic: "Create a new entry here or move an existing entry into this topic."
		case .templates: "Create a reusable starting point for new entries."
		case .archive: "Archive entries you want to keep without showing in your main list."
		case .trash: "Deleted entries appear here until permanently removed."
		}
	}

	private var emptyStateSystemImage: String {
		switch activeSelection {
		case .bookmarks: "bookmark"
		case .topic: "tag"
		case .templates: "doc.on.doc"
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

	private func beginEditingDiary() {
		diaryTitle = diary.title
		diaryDescription = diary.description
		diaryEditError = nil
		diarySaveInProgress = false
		showingDiaryEditor = true
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

	private var topicDeletionMessage: String {
		switch topicPendingDeletionEntryCount {
		case 0:
			return "This topic has no entries. Only the topic will be deleted."
		case 1:
			return "This topic contains 1 entry. Delete it too, or keep it without a topic."
		default:
			return
				"This topic contains \(topicPendingDeletionEntryCount) entries. Delete them too, or keep them without a topic."
		}
	}

	private var topicPendingDeletionEntryCount: Int {
		guard let topic = topicPendingDeletion else { return 0 }
		return entries.count { $0.topicID == topic.id && $0.deletedAt == nil }
	}

	private func deletePendingTopic(deleteEntries: Bool) {
		guard let topic = topicPendingDeletion else { return }
		topicPendingDeletion = nil
		Task {
			if await model.deleteTopic(topic, deleteEntries: deleteEntries),
				activeSelection == .topic(topic.id)
			{
				selection = .entries
			}
		}
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
				.accessibilityIdentifier("topic.default-template")
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

	private var diaryEditorSheet: some View {
		NavigationStack {
			Form {
				TextField("Title", text: $diaryTitle)
					.accessibilityIdentifier("diary.edit.title")
				TextField("Description", text: $diaryDescription, axis: .vertical)
					.accessibilityIdentifier("diary.edit.description")
					.lineLimit(3...6)
				if let diaryEditError {
					Text(diaryEditError)
						.foregroundStyle(.red)
						.accessibilityIdentifier("diary.edit.error")
				}
			}
			.formStyle(.grouped)
			.navigationTitle("Edit Diary")
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { showingDiaryEditor = false }
						.disabled(diarySaveInProgress)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						diaryEditError = nil
						diarySaveInProgress = true
						Task {
							let saved = await model.updateDiary(
								diary,
								title: diaryTitle,
								description: diaryDescription
							)
							diarySaveInProgress = false
							if saved {
								showingDiaryEditor = false
							} else {
								diaryEditError = "Could not update the diary. Try again."
							}
						}
					}
					.disabled(
						diarySaveInProgress
							|| diaryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					)
				}
			}
		}
		.frame(minWidth: 520, minHeight: 320)
	}

	private var selectionTitle: String {
		switch activeSelection {
		case .entries: "Entries"
		case .bookmarks: "Bookmarks"
		case .topic(let topicID): model.topics.first(where: { $0.id == topicID })?.title ?? "Topic"
		case .templates: "Templates"
		case .archive: "Archive"
		case .trash: "Trash"
		}
	}

}

private struct EntryActionsMenuContent: View {
	let entry: ThingsDiaryEntry
	let topics: [ThingsDiaryTopic]
	let isEphemeral: Bool
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
				entry.bookmarked ? "Remove Bookmark" : "Add Bookmark",
				systemImage: entry.bookmarked ? "bookmark.slash" : "bookmark"
			) {
				perform(.toggleBookmark, nil)
			}
		}

		if actions.contains(.duplicate) {
			Button("Duplicate", systemImage: "plus.square.on.square") {
				perform(.duplicate, nil)
			}
			.disabled(isEphemeral)
		}

		if actions.contains(.saveAsTemplate) {
			Button("Save as Template", systemImage: "square.and.arrow.down.on.square") {
				perform(.saveAsTemplate, nil)
			}
		}

		if actions.contains(.moveToTopic),
			shouldShowTopicAssignmentMenu(
				topicCount: topics.count,
				currentTopicID: entry.topicID
			)
		{
			TopicAssignmentPicker(entry: entry, topics: topics) { topicID in
				perform(.moveToTopic, topicID)
			}
		}

		if actions.contains(.moveToTrash) || actions.contains(.deletePermanently) {
			Divider()
		}

		if actions.contains(.toggleArchive) {
			Button(
				entry.archived ? "Restore from Archive" : "Archive",
				systemImage: entry.archived ? "tray.and.arrow.up" : "archivebox"
			) {
				perform(.toggleArchive, nil)
			}
			.disabled(isEphemeral)
		}

		if actions.contains(.moveToTrash) {
			Button("Move to Trash", systemImage: "trash", role: .destructive) {
				perform(.moveToTrash, nil)
			}
			.disabled(isEphemeral)
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

private struct TopicAssignmentPicker: View {
	let entry: ThingsDiaryEntry
	let topics: [ThingsDiaryTopic]
	let move: (String?) -> Void

	private var selection: Binding<String?> {
		Binding(
			get: { entry.topicID },
			set: { selectedTopicID in
				guard
					shouldChangeTopicAssignment(
						currentTopicID: entry.topicID,
						selectedTopicID: selectedTopicID
					)
				else { return }
				move(selectedTopicID)
			}
		)
	}

	private var currentTopicIsUnavailable: Bool {
		guard let currentTopicID = entry.topicID else { return false }
		return !topics.contains { $0.id == currentTopicID }
	}

	var body: some View {
		Picker(selection: selection) {
			if currentTopicIsUnavailable, let currentTopicID = entry.topicID {
				Text("Unavailable Topic")
					.tag(Optional(currentTopicID))
					.disabled(true)
				Divider()
			}

			Text("No Topic")
				.tag(nil as String?)

			if !topics.isEmpty {
				Divider()
			}

			ForEach(topics) { topic in
				Text(topic.title)
					.tag(Optional(topic.id))
			}
		} label: {
			Label("Move to Topic", systemImage: "tag")
		}
		.pickerStyle(.menu)
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
				.accessibilityIdentifier("auth.error")
		} actions: {
			Button("Back to Sign In", action: retry)
		}
	}
}

#Preview {
	ContentView(model: ThingsDiaryAppModel())
}
