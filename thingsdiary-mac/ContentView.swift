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
        NavigationStack {
            Group {
                if diaries.isEmpty {
                    ContentUnavailableView(
                        "No Diaries",
                        systemImage: "book.closed",
                        description: Text("Your account has no diaries yet.")
                    )
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
        }
    }
}

private struct EntriesView: View {
    @Bindable var model: ThingsDiaryAppModel
    let diary: ThingsDiaryDiary
    let entries: [ThingsDiaryEntry]
    @State private var query = ""
    @State private var section: EntrySection = .notes
    @State private var sort: EntrySort = .newest
    @State private var newEntryContent = ""
    @State private var selectedEntry: ThingsDiaryEntry?
    @State private var draftContent = ""

    private var displayedEntries: [ThingsDiaryEntry] {
        visibleEntries(entries, section: section, query: query, sort: sort)
    }

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("Section", selection: $section) {
                            ForEach(EntrySection.allCases) { section in
                                Text(section.rawValue).tag(section)
                            }
                        }
                        .pickerStyle(.segmented)

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

                    if displayedEntries.isEmpty {
                        ContentUnavailableView(
                            "No \(section.rawValue)",
                            systemImage: "note.text",
                            description: Text("No entries match this section and search.")
                        )
                    } else {
                        List(displayedEntries) { entry in
                            Button {
                                selectedEntry = entry
                                draftContent = entry.content
                            } label: {
                                HStack(spacing: 6) {
                                    Text(entry.content)
                                        .lineLimit(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if entry.bookmarked {
                                        Image(systemName: "bookmark.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Bookmarked")
                                    }

                                    if entry.archived {
                                        Image(systemName: "archivebox.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel("Archived")
                                    }
                                }
                                .contentShape(.rect)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if entry.deletedAt != nil {
                                    Button("Restore", systemImage: "arrow.uturn.backward") {
                                        Task {
                                            await model.restoreEntry(entry)
                                        }
                                    }
                                } else {
                                    Button(
                                        entry.bookmarked ? "Remove Bookmark" : "Bookmark",
                                        systemImage: entry.bookmarked ? "bookmark.slash" : "bookmark"
                                    ) {
                                        Task {
                                            await model.toggleBookmark(entry)
                                        }
                                    }

                                    Button(
                                        entry.archived ? "Restore from Archive" : "Archive",
                                        systemImage: entry.archived ? "tray.and.arrow.up" : "archivebox"
                                    ) {
                                        Task {
                                            await model.toggleArchive(entry)
                                        }
                                    }

                                    Button("Duplicate", systemImage: "plus.square.on.square") {
                                        Task {
                                            await model.duplicateEntry(entry)
                                        }
                                    }

                                    Divider()

                                    Button("Move to Trash", systemImage: "trash", role: .destructive) {
                                        Task {
                                            await model.moveToTrash(entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    TextField("New note", text: $newEntryContent, axis: .vertical)
                        .lineLimit(1 ... 4)

                    Button("Add") {
                        let content = newEntryContent
                        newEntryContent = ""
                        Task {
                            await model.createEntry(content: content)
                        }
                    }
                    .disabled(newEntryContent.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                }
                .padding()
            }
            .navigationTitle(diary.title)
            .searchable(text: $query)
            .toolbar {
                Button("Diaries", action: model.showDiaries)
            }
            .sheet(item: $selectedEntry) { entry in
                NavigationStack {
                    TextEditor(text: $draftContent)
                        .padding()
                        .navigationTitle("Edit Note")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    selectedEntry = nil
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let content = draftContent
                                    Task {
                                        await model.updateEntry(entry, content: content)
                                        selectedEntry = nil
                                    }
                                }
                            }
                        }
                }
                .frame(minWidth: 420, minHeight: 300)
            }
        }
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could Not Load Diaries", systemImage: "exclamationmark.triangle")
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
