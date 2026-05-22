import ZanozaKit
import SwiftUI

@main
struct ZanozaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, AppLocalization.locale)
        }
    }
}
