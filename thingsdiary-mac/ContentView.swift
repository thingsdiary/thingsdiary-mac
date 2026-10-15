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
                        Text("Create a diary to start writing notes.")
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
    @State private var selection: DiaryNavigationSelection? = .notes
    @State private var sort: EntrySort = .newest
    @State private var newEntryContent = ""
    @State private var selectedEntryID: String?
    @State private var draftContent = ""
    @State private var showingTopicsAndTemplates = false
    @State private var showingTopicCreator = false
    @State private var editingTopic: ThingsDiaryTopic?
    @State private var topicTitle = ""
    @State private var topicDescription = ""
    @State private var topicColor = ""
    @State private var editingTemplate: ThingsDiaryTemplate?
    @State private var templateContent = ""

    private var displayedEntries: [ThingsDiaryEntry] {
        visibleEntries(entries, selection: activeSelection, query: query, sort: sort)
    }

    private var activeSelection: DiaryNavigationSelection { selection ?? .notes }

    private var selectedEntry: ThingsDiaryEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    private func count(for selection: DiaryNavigationSelection) -> Int {
        visibleEntries(entries, selection: selection, query: "", sort: .newest).count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Notes", systemImage: "note.text")
                        .tag(Optional(DiaryNavigationSelection.notes))
                        .badge(count(for: .notes))
                    Label("Bookmarks", systemImage: "bookmark")
                        .tag(Optional(DiaryNavigationSelection.bookmarks))
                        .badge(count(for: .bookmarks))
                }

                Section {
                    ForEach(model.topics) { topic in
                        Label(topic.title, systemImage: "tag")
                            .tag(Optional(DiaryNavigationSelection.topic(topic.id)))
                            .badge(count(for: .topic(topic.id)))
                    }
                } header: {
                    HStack {
                        Text("Topics")
                        Spacer()
                        Button {
                            topicTitle = ""
                            topicDescription = ""
                            showingTopicCreator = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New Topic")
                    }
                }

                Section {
                    Label("Archive", systemImage: "archivebox")
                        .tag(Optional(DiaryNavigationSelection.archive))
                        .badge(count(for: .archive))
                    Label("Trash", systemImage: "trash")
                        .tag(Optional(DiaryNavigationSelection.trash))
                        .badge(count(for: .trash))
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
                    Text(selectionTitle).font(.headline)
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
                        "No \(selectionTitle)",
                        systemImage: "note.text",
                        description: Text("No entries match this section and search.")
                    )
                } else {
                    List(displayedEntries) { entry in
                        Button {
                            selectedEntryID = entry.id
                            draftContent = entry.content
                        } label: {
                            HStack(spacing: 6) {
                                Text(entry.content)
                                    .lineLimit(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if entry.bookmarked {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel("Bookmarked")
                                }
                                if entry.archived {
                                    Image(systemName: "archivebox.fill")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel("Archived")
                                }
                            }
                            .contentShape(.rect)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            entryActions(for: entry)
                        }
                    }
                }

                HStack {
                    Menu("Use Template") {
                        ForEach(model.templates) { template in
                            Button(template.content.isEmpty ? "Empty Template" : String(template.content.prefix(40))) {
                                newEntryContent = template.content
                            }
                        }
                    }
                    TextField("New note", text: $newEntryContent, axis: .vertical)
                        .lineLimit(1 ... 4)
                    Button("Add") {
                        let content = newEntryContent
                        newEntryContent = ""
                        Task { await model.createEntry(content: content) }
                    }
                    .disabled(newEntryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .searchable(text: $query)
            .toolbar {
                if activeSelection == .trash && !displayedEntries.isEmpty {
                    Button("Empty Trash", role: .destructive) {
                        Task { await model.emptyTrash() }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
        } detail: {
            if let selectedEntry {
                TextEditor(text: $draftContent)
                    .disabled(selectedEntry.deletedAt != nil || selectedEntry.archived)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Menu {
                                entryActions(for: selectedEntry)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .help("Note Actions")

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
                    Text("\(count(for: .notes)) notes · \(count(for: .bookmarks)) bookmarks · \(count(for: .archive)) archived · \(count(for: .trash)) in trash")
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
        .sheet(isPresented: $showingTopicCreator) {
            topicCreatorSheet
        }
    }

    private func canSave(_ entry: ThingsDiaryEntry) -> Bool {
        !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftContent != entry.content
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

    private var topicCreatorSheet: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $topicTitle)
                TextField("Description", text: $topicDescription, axis: .vertical)
                    .lineLimit(2 ... 5)
            }
            .formStyle(.grouped)
            .navigationTitle("New Topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingTopicCreator = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = topicTitle
                        let description = topicDescription
                        let existingTopicIDs = Set(model.topics.map(\.id))
                        Task {
                            await model.createTopic(
                                title: title,
                                description: description,
                                color: ""
                            )
                            if let createdTopic = model.topics.first(where: {
                                !existingTopicIDs.contains($0.id)
                            }) {
                                selection = .topic(createdTopic.id)
                                showingTopicCreator = false
                            }
                        }
                    }
                    .disabled(topicTitle.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    private var selectionTitle: String {
        switch activeSelection {
        case .notes: "Notes"
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
                        Button(topic.title) {
                            editingTopic = topic
                            topicTitle = topic.title
                            topicDescription = topic.description
                            topicColor = topic.color
                        }
                    }
                    TextField("Title", text: $topicTitle)
                    TextField("Description", text: $topicDescription)
                    TextField("Color", text: $topicColor)
                    Button(editingTopic == nil ? "Create Topic" : "Save Topic") {
                        let topic = editingTopic
                        let title = topicTitle, description = topicDescription, color = topicColor
                        Task {
                            if let topic {
                                await model.updateTopic(topic, title: title, description: description, color: color)
                            } else {
                                await model.createTopic(title: title, description: description, color: color)
                            }
                            editingTopic = nil
                            topicTitle = ""
                            topicDescription = ""
                            topicColor = ""
                        }
                    }
                    if editingTopic != nil {
                        Button("New Topic") { editingTopic = nil; topicTitle = ""; topicDescription = ""; topicColor = "" }
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
