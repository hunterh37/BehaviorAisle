import SwiftUI
import RealKit
import RealLibrary
import HumanKit

@main
struct BehaviorAisleApp: App {
    @State private var model = AppModel()
    @State private var style: ImmersionStyle = .full

    init() {
        RealityHD.setup(.balanced)
        Human.setup(.balanced)
    }

    var body: some Scene {
        WindowGroup(id: "control") {
            ControlView()
                .environment(model)
        }
        .defaultSize(width: 520, height: 760)

        ImmersiveSpace(id: StoreSpace.id) {
            StoreSpace()
                .environment(model)
        }
        .immersionStyle(selection: $style, in: .full)
    }
}
