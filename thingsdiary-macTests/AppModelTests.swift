import Foundation
import Testing
import ThingsDiaryClient
@testable import thingsdiary_mac

@MainActor
@Test("Successful login loads decrypted diaries and clears secrets")
func successfulLoginLoadsDiaries() async throws {
    let diary = ThingsDiaryDiary(
        id: "diary-1",
        title: "Personal",
        description: "Daily notes",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2),
        version: 3
    )
    let client = StubAppClient(result: .success([diary]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    #expect(model.screen == .diaries([diary]))
    #expect(model.password.isEmpty)
    #expect(model.secretKey.isEmpty)
    #expect(await client.receivedLogin == "person@example.test")
    #expect(await client.receivedPassword == "password")
    #expect(await client.receivedSecretKey == "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6")
}

@MainActor
@Test("Failed login shows an error, clears secrets, and allows retry")
func failedLoginAllowsRetry() async {
    let client = StubAppClient(result: .failure(TestFailure.rejected))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "wrong"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    guard case .error = model.screen else {
        Issue.record("Expected error state")
        return
    }
    #expect(model.password.isEmpty)
    #expect(model.secretKey.isEmpty)

    model.retry()
    #expect(model.screen == .login)
}

@MainActor
@Test("Login requires all credentials before calling the client")
func loginRequiresAllCredentials() async {
    let client = StubAppClient(result: .success([]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "   "
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W6"

    await model.submit()

    #expect(model.screen == .error("Enter login, password, and a valid TDKV1 secret key."))
    #expect(await client.receivedLogin == nil)
}

@MainActor
@Test("Login rejects an invalid TDKV1 key before calling the client")
func loginRejectsInvalidSecretKey() async {
    let client = StubAppClient(result: .success([]))
    let model = ThingsDiaryAppModel(client: client)
    model.login = "person@example.test"
    model.password = "password"
    model.secretKey = "TDKV1-000G-40R4-0M30-E209-185G-R38E-1W0"

    await model.submit()

    #expect(model.screen == .error("Enter login, password, and a valid TDKV1 secret key."))
    #expect(await client.receivedLogin == nil)
}

private enum TestFailure: Error {
    case rejected
}

private actor StubAppClient: ThingsDiaryAppClient {
    let result: Result<[ThingsDiaryDiary], Error>
    private(set) var receivedLogin: String?
    private(set) var receivedPassword: String?
    private(set) var receivedSecretKey: String?

    init(result: Result<[ThingsDiaryDiary], Error>) {
        self.result = result
    }

    func login(login: String, password: String, secretKey: String) async throws {
        receivedLogin = login
        receivedPassword = password
        receivedSecretKey = secretKey
        if case let .failure(error) = result {
            throw error
        }
    }

    func diaries() async throws -> [ThingsDiaryDiary] {
        try result.get()
    }
}

