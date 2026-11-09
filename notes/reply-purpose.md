# What Shelfcast is, and whether it is useful

## Purpose

A hackathon demo (Sundai Hack 148, theme "predict the next action"). A Vision Pro grocery store where 5 simulated
shoppers walk aisles. The user moves a product or adds a sale sign, and the shoppers change what they pick. The
pitch: test a shelf layout or promotion on predicted shoppers before moving a real shelf.

## What BehaviorGPT does

BehaviorGPT is Unbox AI's sequence model trained on retail and payment event logs. It acts like an LLM over
actions instead of words: given a history (`view milk`, `add_to_cart bread`) it returns ranked next actions with
probabilities. In this app each shopper loop is:

1. App sends `{persona, history, cart, catalog}` to `proxy/worker.js`, which calls Unbox (`proxy/core.mjs`).
2. Response: top items with `p`. The shopper samples one of the top 3, walks to that shelf, appends the event.
3. Repeat until it predicts `checkout`.

When the proxy is down or unset, `HeuristicPredictor.swift` runs instead: a hand-written softmax over category
affinity, price, promo, eye level, complements and walking distance.

## Assessment

As a hackathon demo: reasonable. It turns an abstract "next action" model into something visible, and the
what-if interaction is a clear story for judges.

As a product or as evidence: weak, for these reasons.

- BehaviorGPT has no notion of space. It sees item ids and history. It has no input for shelf height, endcap,
  aisle or distance, so "move cereal to eye level" cannot change its output except through catalog fields the
  proxy passes. Layout effects in the demo come from the heuristic's eye-level and distance terms.
- The experiments are circular. `Experiment.accuracy()` (Experiment.swift:137) generates ground-truth trips
  with `HeuristicPredictor` plus noise, then scores the same heuristic against them. Full model hit@3 0.26 vs
  random 0.10 shows the heuristic predicts its own noisy outputs. It says nothing about real shoppers or
  BehaviorGPT.
- The what-if CIs (towels +X carts per 100) measure the heuristic's promo coefficient, which was chosen by hand.
- Synthetic personas have no real history, so BehaviorGPT receives cold-start inputs, where it is weakest.
- Real retail layout testing already exists (planogram tools, A/B store tests, agent-based sims such as
  AnyLogic). The 3D headset view adds presentation, not predictive power. Merchandisers do not work in Vision Pro.

## Verdict

Useful as a demo and a visual explainer. Not useful as a decision tool in its current form, since the
spatial predictions are hand-tuned rules and the validation tests the rules against themselves.

## What would make it useful

- Validate against a real dataset (Instacart Market Basket, Dunnhumby "The Complete Journey") with held-out
  next-item accuracy for BehaviorGPT vs the heuristic.
- Feed spatial features to the model (or fit the heuristic's coefficients on real data) so layout changes
  carry learned effects.
- Drop the headset requirement for the analysis path: a 2D web dashboard reaches the actual buyers.
