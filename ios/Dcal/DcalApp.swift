// The iOS app target - a shell around DcalUI, which holds everything real.
// This file only compiles inside the Xcode project (see ../project.yml).

import DcalUI
import SwiftUI

@main
struct DcalApp: App {
    var body: some Scene {
        WindowGroup {
            DcalRootView()
        }
    }
}
