import SwiftUI
import ThingsDiaryClient

struct ContentView: View {
    @Bindable var model: ThingsDiaryAppModel

    var body: some View {
        Group {
            switch model.screen {
            case .login:
                LoginView(model: model)
            case .loading:
                ProgressView("Signing in and loading diaries…")
            case let .diaries(diaries):
                DiariesView(diaries: diaries)
            case let .error(message):
                ErrorView(message: message, retry: model.retry)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
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

            Button("Sign In") {
                Task {
                    await model.submit()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 360)
        .padding(40)
    }
}

private struct DiariesView: View {
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
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Diaries")
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
