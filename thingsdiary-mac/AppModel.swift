import Foundation
import Observation
import ThingsDiaryClient

protocol ThingsDiaryAppClient: Sendable {
    func login(login: String, password: String, secretKey: String) async throws
    func diaries() async throws -> [ThingsDiaryDiary]
}

struct LiveThingsDiaryAppClient: ThingsDiaryAppClient {
    private let client: ThingsDiaryClient

    init(client: ThingsDiaryClient = ThingsDiaryClient()) {
        self.client = client
    }

    func login(login: String, password: String, secretKey: String) async throws {
        _ = try await client.login(
            login: login,
            password: password,
            secretKey: secretKey
        )
    }

    func diaries() async throws -> [ThingsDiaryDiary] {
        try await client.diaries().items
    }
}

enum ThingsDiaryAppScreen: Equatable {
    case login
    case loading
    case diaries([ThingsDiaryDiary])
    case error(String)
}

@MainActor
@Observable
final class ThingsDiaryAppModel {
    var login = ""
    var password = ""
    var secretKey = ""
    private(set) var screen: ThingsDiaryAppScreen = .login

    private let client: any ThingsDiaryAppClient

    var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (try? ThingsDiarySecretKey.parse(secretKey)) != nil
    }

    init(client: any ThingsDiaryAppClient = LiveThingsDiaryAppClient()) {
        self.client = client
    }

    func submit() async {
        guard canSubmit else {
            password = ""
            secretKey = ""
            screen = .error("Enter login, password, and a valid TDKV1 secret key.")
            return
        }

        let login = login
        let password = password
        let secretKey = secretKey
        screen = .loading

        defer {
            self.password = ""
            self.secretKey = ""
        }

        do {
            try await client.login(
                login: login,
                password: password,
                secretKey: secretKey
            )
            screen = .diaries(try await client.diaries())
        } catch {
            screen = .error("Could not sign in or load diaries. Check your credentials and try again.")
        }
    }

    func retry() {
        screen = .login
    }
}
