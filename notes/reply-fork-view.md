Fork view (tap a shopper)

Code: `BehaviorAisle/Model/AppModel.swift:364` (`toggleFreeze`), `BehaviorAisle/Viz/GhostLayer.swift`.

Tapping a shopper freezes that shopper in place and spawns one translucent ghost per entry in its current top-3 next-item predictions (`s.predictions`, from BehaviorGPT or the heuristic predictor, whichever mode is active). Each ghost walks the store path from the shopper's position to the stand point of its predicted product (or the checkout stand when the prediction is "checkout"), at 1.4x walk speed. On arrival it pulses.

The ghosts are low-poly on purpose: a cylinder body, sphere head and floor ring built from primitives in `GhostLayer.ghost`. No HumanHD model is loaded. They are tinted with the persona color, and opacity is 0.2 + 0.5 x probability, so likelier branches look more solid. The floating label is the probability, for example "62%".

The purpose is to show the model's branching forecast in space: "from here, this shopper goes to A (62%), B (21%) or checkout (9%)". The real shopper then takes one branch when unfrozen.

Tap the same shopper again to unfreeze it; ghosts clear and the shopper executes its chosen next step. Tapping a different shopper moves the fork to that one. If the predictions refresh while frozen, ghosts respawn (`AppModel.swift:322`).
