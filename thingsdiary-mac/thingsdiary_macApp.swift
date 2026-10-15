import SwiftUI

@main
struct thingsdiary_macApp: App {
    @State private var model: ThingsDiaryAppModel

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-workspace") {
            _model = State(initialValue: ThingsDiaryAppModel.uiTestingWorkspace())
            return
        }
        #endif

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let store = try? DiaryStore(fileURL: applicationSupport
            .appending(path: "ThingsDiary", directoryHint: .isDirectory)
            .appending(path: "state.json"))
        _model = State(initialValue: ThingsDiaryAppModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
