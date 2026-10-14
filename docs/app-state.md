# App state

## Public test boundary

Tests use `@MainActor ThingsDiaryAppModel`.

The model accepts a `ThingsDiaryAppClient` with two methods:

```swift
func login(login: String, password: String, secretKey: String) async throws
func diaries() async throws -> [ThingsDiaryDiary]
```

The production adapter calls the local Swift package. The test adapter does not use the network. Tests do not replace internal tasks, `URLSession`, cryptographic functions, or SwiftUI views.

## States

- `login` shows fields for the login, password, and `TDKV1` secret key.
- `loading` covers asynchronous authentication and diary loading.
- `diaries` contains the decrypted diary list.
- `error` contains an error message and a retry action.

`submit()` moves the model from `login` or `error` to `loading`. After authentication succeeds, the model loads the first diary page and moves to `diaries`. On failure, it clears the password and secret key before moving to `error`.

## Storage

The token, credentials, password, and secret key live only in process memory. This slice does not use SwiftData, Core Data, UserDefaults, or Keychain. Exiting the process discards the state.

## UI

One `ContentView` shows the form, progress indicator, error, or diary list. The UI calls only `ThingsDiaryAppModel` methods and does not access the network or cryptography module directly.
