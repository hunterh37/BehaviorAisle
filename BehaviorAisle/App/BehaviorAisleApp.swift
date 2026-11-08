import SwiftUI
import RealKit
import RealLibrary
import HumanKit
#if DEBUG
import DicyaninStageDirector
#endif

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
                #if DEBUG
                .director { DemoRoutes.register($0, model: model) }
                #endif
        }
        .defaultSize(width: 680, height: 860)

        ImmersiveSpace(id: StoreSpace.id) {
            StoreSpace()
                .environment(model)
        }
        .immersionStyle(selection: $style, in: .full)
    }
}
