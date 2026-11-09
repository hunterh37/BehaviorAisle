# App idea, demo concepts, name

## Idea
A 1:1 grocery store on Vision Pro, filled with simulated shoppers whose next pick comes from BehaviorGPT (Unbox AI). The owner changes a layout or a price, the shoppers re-decide, and the app reports carts per 100 shoppers with a confidence interval. Validation: 79,785 Instacart baskets, Hit@3 25.2% vs 9.3% random.

Strengths
- One sentence explains it: "test a store change before moving a shelf."
- Real numbers with CIs make it more than a visual toy.
- The failure ladder (live, replay, heuristic) keeps a stage demo safe.

Weak points a judge or buyer will find
- Layout effects (eye level, sale) are app-side weights; BehaviorGPT has no spatial input. So the store's 3D layout does not drive the model. This is the largest credibility gap. Options: say it up front, or feed shelf position as a token/event into the history so BehaviorGPT sees it.
- Buyer is a category manager or retail ops team, who works on a laptop. Vision Pro is the demo medium. A web/iPad viewer of the same sim widens the market.
- Hit@3 25% is next-item accuracy. Buyers care about lift prediction accuracy. One back-test against a known real promo would carry more weight than any other number.
- Five demos exist (Console, Intent, XProfile, Flow1, Plan). Too many threads for a 3-minute slot.

## Demo concepts, ranked
1. Before/after split. One change (sale sign on towels), run 50 shoppers twice, show +18.2 ± 2.2 carts/100 on the floor as trails and a number. Strongest; matches the pitch line.
2. Intent overhead. Follow one shopper with top-3 next items floating above them, then flip a sale and watch the ranking change. Good 20-second hook before demo 1.
3. BehaviorGPT console. Request/response cards. Keep for technical judges only; it reads as a debug screen.
4. X profile import. Shopper built from a social profile. Fun but raises privacy questions and conflicts with "no personal data." Cut from the main demo.

Suggested 3-minute order: 2 (hook) -> 1 (proof) -> numbers slide -> 3 only if asked.

## Names
Criteria: short, says "test before you change the store," no "AI" or "GPT" in the name.

| Name | Note |
|---|---|
| **Dry Aisle** | A dry run of an aisle. Short, retail word, recommendation. |
| Shelfcast | Forecast for shelves. Clear for retail buyers. |
| Pre-Shelf | Test before shelving. Plain. |
| Aisle Zero | The aisle before the real one. |
| Twin Aisle | Digital twin framing; enterprise-friendly. |
| Footfall | Retail term for traffic; likely taken. |
| Planogram Lab | Uses the industry word buyers search for; long. |
| Shopsim | Literal; weak trademark. |

Recommendation: **Dry Aisle** for the app, tagline "Test the store before you move a shelf." Shelfcast as the backup if the name is taken. Bundle stays org.dicyaninlabs.behavioraisle (bundle IDs need not match the display name).

Trademark and domain checks have not been run.
