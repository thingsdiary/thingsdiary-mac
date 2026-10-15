import SwiftUI
import ThingsDiaryClient

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
            case let .registrationComplete(result):
                RegistrationCompleteView(model: model, result: result)
            case let .diaries(diaries):
                DiariesView(model: model, diaries: diaries)
            case let .entries(diary, entries):
                EntriesView(model: model, diary: diary, entries: entries)
            case let .error(message):
                ErrorView(message: message, retry: model.retry)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
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
            Text("ThingsDiary")
                .font(.largeTitle.bold())

            Text("Sign in to load your encrypted diaries.")
                .foregroundStyle(.secondary)

            TextField("Login", text: $model.login)
                .textContentType(.username)

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

            TextField("Login", text: $model.login)
                .textContentType(.username)

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
    @State private var title = ""
    @State private var diaryDescription = ""

    var body: some View {
        NavigationStack {
            Group {
                if diaries.isEmpty {
                    ContentUnavailableView {
                        Label("No Diaries", systemImage: "book.closed")
                    } description: {
                        Text("Create a diary to start writing entries.")
                    } actions: {
                        Button("Create Diary", action: model.showDiaryCreation)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(diaries) { diary in
                        Button {
                            Task {
                                await model.selectDiary(diary)
                            }
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
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Diaries")
            .toolbar {
                Button("Create Diary", systemImage: "plus", action: model.showDiaryCreation)
            }
            .sheet(isPresented: Binding(
                get: { model.isCreatingDiary },
                set: { isPresented in
                    if !isPresented {
                        model.cancelDiaryCreation()
                    }
                }
            )) {
                NavigationStack {
                    Form {
                        TextField("Title", text: $title)
                        TextField("Description", text: $diaryDescription, axis: .vertical)
                            .lineLimit(2 ... 5)

                        if let error = model.diaryCreationError {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Create Diary")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                model.cancelDiaryCreation()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                let title = title
                                let description = diaryDescription
                                Task {
                                    await model.createDiary(
                                        title: title,
                                        description: description
                                    )
                                    if !model.isCreatingDiary {
                                        self.title = ""
                                        diaryDescription = ""
                                    }
                                }
                            }
                            .disabled(title.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                        }
                    }
                }
                .frame(minWidth: 420, minHeight: 260)
            }
        }
    }
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
    @State private var showingTopicCreator = false
    @State private var editingTopic: ThingsDiaryTopic?
    @State private var topicTitle = ""
    @State private var topicDescription = ""
    @State private var topicColor = ""
    @State private var topicEntryPreviewable = true
    @State private var topicDefaultTemplateID: String?
    @State private var pendingTrashEntry: ThingsDiaryEntry?
    @State private var pendingPermanentDeletion: ThingsDiaryEntry?
    @State private var confirmingEmptyTrash = false
    @State private var editingTemplate: ThingsDiaryTemplate?
    @State private var templateContent = ""

    private var displayedEntries: [ThingsDiaryEntry] {
        visibleEntries(entries, selection: activeSelection, query: query, sort: sort)
    }

    private var activeSelection: DiaryNavigationSelection { selection ?? .entries }

    private var selectedEntry: ThingsDiaryEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    private func count(for selection: DiaryNavigationSelection) -> Int {
        visibleEntries(entries, selection: selection, query: "", sort: .newest).count
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section {
                    Button {
                        newEntryContent = ""
                        showingEntryCreator = true
                    } label: {
                        Label("New Entry", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("entry.create")
                    .buttonStyle(.plain)

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
                        identifier: "sidebar.bookmarks"
                    )
                }

                Section("Topics") {
                    ForEach(model.topics) { topic in
                        sidebarRow(
                            topic.title,
                            systemImage: "tag",
                            destination: .topic(topic.id),
                            identifier: "sidebar.topic.\(topic.id)",
                            color: topicColorValue(topic.color),
                            doubleClick: { beginEditing(topic) }
                        )
                    }

                    Button {
                        topicTitle = ""
                        topicDescription = ""
                        topicColor = topicColors[0]
                        topicEntryPreviewable = true
                        topicDefaultTemplateID = nil
                        editingTopic = nil
                        showingTopicCreator = true
                    } label: {
                        Label("New Topic", systemImage: "plus")
                    }
                    .accessibilityIdentifier("topic.create")
                    .buttonStyle(.plain)
                }

                Section {
                    sidebarRow(
                        "Archive",
                        systemImage: "archivebox",
                        destination: .archive,
                        identifier: "sidebar.archive"
                    )
                    sidebarRow(
                        "Trash",
                        systemImage: "trash",
                        destination: .trash,
                        identifier: "sidebar.trash"
                    )
                }
            }
            .navigationTitle(diary.title)
            .toolbar {
                Button("Diaries", action: model.showDiaries)
                Button("Topics & Templates") { showingTopicsAndTemplates = true }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            VStack(spacing: 0) {
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

                if displayedEntries.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: emptyStateSystemImage,
                        description: Text(emptyStateDescription)
                    )
                } else {
                    List(displayedEntries) { entry in
                        Button {
                            selectedEntryID = entry.id
                            draftContent = entry.content
                        } label: {
                            entryListRow(entry)
                        }
                        .accessibilityIdentifier("entry.\(entry.id)")
                        .buttonStyle(.plain)
                        .contextMenu {
                            entryActions(for: entry)
                        }
                    }
                }
            }
            .searchable(text: $query)
            .toolbar {
                if activeSelection == .trash && !displayedEntries.isEmpty {
                    Button("Empty Trash", role: .destructive) {
                        confirmingEmptyTrash = true
                    }
                    .accessibilityIdentifier("trash.empty")
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
        } detail: {
            if let selectedEntry {
                TextEditor(text: $draftContent)
                    .accessibilityIdentifier("entry.editor")
                    .disabled(selectedEntry.deletedAt != nil || selectedEntry.archived)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
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
                    Text("\(count(for: .entries)) entries · \(count(for: .bookmarks)) bookmarks · \(count(for: .archive)) archived · \(count(for: .trash)) in trash")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 520)
        .onChange(of: selection) {
            selectedEntryID = nil
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
        .alert("Move Entry to Trash?", isPresented: Binding(
            get: { pendingTrashEntry != nil },
            set: { if !$0 { pendingTrashEntry = nil } }
        ), presenting: pendingTrashEntry) { entry in
            Button("Move to Trash", role: .destructive) {
                pendingTrashEntry = nil
                execute(.moveToTrash, on: entry, topicID: nil)
            }
            Button("Cancel", role: .cancel) { pendingTrashEntry = nil }
        } message: { entry in
            Text("“\(entryListPresentation(content: entry.content).title)” can be restored later from Trash.")
        }
        .alert("Delete Entry Permanently?", isPresented: Binding(
            get: { pendingPermanentDeletion != nil },
            set: { if !$0 { pendingPermanentDeletion = nil } }
        ), presenting: pendingPermanentDeletion) { entry in
            Button("Delete Permanently", role: .destructive) {
                pendingPermanentDeletion = nil
                execute(.deletePermanently, on: entry, topicID: nil)
            }
            Button("Cancel", role: .cancel) { pendingPermanentDeletion = nil }
        } message: { entry in
            Text("“\(entryListPresentation(content: entry.content).title)” will be deleted permanently. This cannot be undone.")
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

    private func canSave(_ entry: ThingsDiaryEntry) -> Bool {
        !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftContent != entry.content
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        destination: DiaryNavigationSelection,
        identifier: String,
        color: Color? = nil,
        doubleClick: (() -> Void)? = nil
    ) -> some View {
        Button {
            selection = destination
        } label: {
            HStack {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                } else {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .foregroundStyle(.tint)
                }
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { doubleClick?() })
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .badge(count(for: destination))
        .listRowBackground(
            activeSelection == destination
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
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
        if action == .moveToTrash,
           !entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingTrashEntry = entry
            return
        }
        if action == .deletePermanently {
            pendingPermanentDeletion = entry
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
            case .toggleBookmark:
                await model.toggleBookmark(entry)
            case .toggleArchive:
                await model.toggleArchive(entry)
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
        case .toggleBookmark:
            return activeSelection == .bookmarks
        case .toggleArchive, .moveToTrash, .restore, .deletePermanently:
            return true
        case .moveToTopic:
            guard case let .topic(selectedTopicID) = activeSelection else {
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
               let preview = presentation.preview {
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
        switch activeSelection {
        case .archive: "Archive is empty"
        case .trash: "Trash is empty"
        default: "No \(selectionTitle)"
        }
    }

    private var emptyStateDescription: String {
        switch activeSelection {
        case .archive: "Archived entries appear here."
        case .trash: "Deleted entries appear here until permanently removed."
        default: query.isEmpty ? "Create an entry to get started." : "No entries match your search."
        }
    }

    private var emptyStateSystemImage: String {
        switch activeSelection {
        case .archive: "archivebox"
        case .trash: "trash"
        default: "note.text"
        }
    }

    private let topicColors = [
        "#94A3B8", "#93C5FD", "#86EFAC", "#A3E635", "#2DD4BF",
        "#FCD34D", "#F4A261", "#E76F51", "#E9C46A", "#B5838D", "#C4B5FD",
    ]

    private func topicColorValue(_ hex: String) -> Color {
        Color(topicHex: hex) ?? .secondary
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
                Text("\(topicTitle.count)/\(maximumTopicTitleLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Description", text: $topicDescription, axis: .vertical)
                    .accessibilityIdentifier("topic.description")
                    .lineLimit(2 ... 5)
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
        case let .topic(topicID): model.topics.first(where: { $0.id == topicID })?.title ?? "Topic"
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
                        Button("New Template") { editingTemplate = nil; templateContent = "" }
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

private extension Color {
    init?(topicHex: String) {
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
