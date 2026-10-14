import SwiftUI

@main
struct thingsdiary_macApp: App {
    @State private var model = ThingsDiaryAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
