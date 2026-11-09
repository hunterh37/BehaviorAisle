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
        // Batch static singles into merged meshes (fewer draw calls, same look); governor trims LOD only under load.
        RealityHD.setup(RealPerformance(.balanced).with { $0.forceBatching = true; $0.adaptive = true })
        Human.setup(.balanced)
        // Bundled prebake (tools/prebake.json) skips asset generation and texture synthesis; the runtime cache
        // keeps whatever is still generated so the next launch skips it too.
        RealityHD.usePrebaked()
        RealPrebake.writeThrough = true
        // Store shell and product models start loading while the control window is up.
        Task { @MainActor in StoreBuilder.prewarm(catalog: Catalog.laidOut(), density: StoreDensity.load()) }
    }

    var body: some Scene {
        WindowGroup(id: "control") {
            ControlView()
                .environment(model)
                #if DEBUG
                .director { DemoRoutes.register($0, model: model); APIRoutes.register($0, model: model) }
                #endif
        }
        .defaultSize(width: 680, height: 860)

        Window("BehaviorGPT", id: APIConsoleView.windowId) {
            APIConsoleView()
                .environment(model)
        }
        .defaultSize(width: 1040, height: 1080)

        ImmersiveSpace(id: StoreSpace.id) {
            StoreSpace()
                .environment(model)
        }
        .immersionStyle(selection: $style, in: .full)
    }
}
