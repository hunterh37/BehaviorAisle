#if DEBUG
import DicyaninStageDirector
import SwiftUI

/// Routes for the BehaviorGPT console window. Live calls need network and the bundled key.
/// Params: mode=live|replay, raw=1 (JSON view), calls=N (live replies to wait for).
enum APIRoutes {
    @MainActor static func register(_ b: RouteBook, model: AppModel) {
        b.group("api") { b in
            b.route("console", "BehaviorGPT console: request, response, shopper update", duration: 55, tags: ["hero"]) { t in
                model.mode = t.param("mode") == "replay" ? .replay : .live
                APITrace.shared.showRaw = t.param("raw") == "1"
                await t.openImmersive(StoreSpace.id)
                while model.store == nil || model.loadProgress != nil { await t.wait(0.3) }
                let want = Int(t.param("calls", default: 6))
                var waited = 0.0
                while waited < 45 {
                    let tr = APITrace.shared
                    let done = model.mode == .live ? tr.live : tr.total
                    if done >= want, tr.featured?.stage == .applied { break }
                    await t.wait(0.5); waited += 0.5
                }
                await t.ready(); await t.wait(3); t.done()
            }
        }
    }
}
#endif
