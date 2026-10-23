import FallowTouch
import SwiftUI

@main
struct FallowApp: App {
    var body: some Scene {
        WindowGroup {
            WriterScreen()
                .ignoresSafeArea()
                .statusBarHidden()
        }
    }
}
