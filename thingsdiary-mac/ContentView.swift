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
    @State private var newEntryContent = ""
    @State private var selectedEntry: ThingsDiaryEntry?
    @State private var draftContent = ""

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("This diary has no notes yet.")
                    )
                } else {
                    List(entries) { entry in
                        Button {
                            selectedEntry = entry
                            draftContent = entry.content
                        } label: {
                            Text(entry.content)
                                .lineLimit(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
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
