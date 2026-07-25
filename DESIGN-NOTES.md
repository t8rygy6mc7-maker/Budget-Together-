# Design notes — visual budget cues and chart readability

Working notes from the design pass on 25 July 2026. Covers the colour system, the
pace-state maths, chart decisions, and the accessibility fixes that fall out of
the current `Palette`.

## 1. Colour: identity and status must not share a namespace

### The problem

Four hexes currently do double duty:

| Hex | Used by |
| --- | --- |
| `#E86A4A` | `Bucket.housing` **and** `Palette.over` |
| `#3FB984` | `Bucket.food` **and** `Palette.green` |
| `#C69BFF` | `Bucket.subs` **and** `Person.friend` / `Palette.purple` |
| `#5EEAD4` | `Bucket.savings` **and** `Person.you` / `Palette.teal` |

So a coral bar is ambiguous — alarm, or just Housing? And a teal number is
ambiguous three ways: brand accent, "good", or Savings.

### Why adding a third status colour doesn't work

The eight bucket colours occupy the whole hue wheel:

| Bucket | Hue |
| --- | --- |
| housing | 41° |
| shopping | 90° |
| food | 160° |
| savings | 181° |
| transport | 283° |
| subs | 309° |
| health | 351° |
| fun | 360° |

Largest gaps: 102° (savings→transport, midpoint 232°), 70° (shopping→food),
49° (housing→shopping). Nothing in the blue-violet gap reads as a warning, so
there is exactly one usable slot: amber, in the housing→shopping gap.

### The rule

**Fill encodes identity. Status lives in a dedicated slot.** A bar is
Housing-coral because it is Housing, always. Status is carried by a marker, a
tail, an icon, and words — never by recolouring the fill.

That reduces status to two colours plus an absence:

| State | Colour | Encoding |
| --- | --- | --- |
| On pace | *none* | no marker text, no icon. Absence of alarm is the signal. |
| Drifting | `#F5A623` | icon + "N% ahead of pace" |
| Over | `#F2555A` | overage tail **past the cap marker** + icon + "Over by $N" |

Contrast, measured against `Palette.card` (`#1D2130`) and `Palette.screen`
(`#141620`):

| Role | Hex | vs card | vs screen |
| --- | --- | --- | --- |
| drift | `#F5A623` | 7.89 | 8.89 |
| over | `#F2555A` | 4.74 | 5.34 |

Both clear WCAG AA (4.5:1). `#F2555A` sits only ΔE76 17.4 from housing coral,
which is acceptable *only* because the overage tail can never appear anywhere a
bucket fill appears — it exists exclusively to the right of the cap marker.
Position disambiguates what hue cannot.

Suggested shape in `Theme.swift`: a separate `enum Status` namespace, with a
test asserting that no hex appears in both `Status` and `Bucket.all`.

## 2. Pace-state maths

```
daysInMonth  = days in the current month
dayOfMonth   = today's day number
expected     = cap * Double(dayOfMonth) / Double(daysInMonth)
paceRatio    = spent / expected            // guard expected > 0
projected    = spent / Double(dayOfMonth) * Double(daysInMonth)
```

```
if spent > cap                  -> .over(by: spent - cap)
else if !isMeaningful           -> .neutral
else if paceRatio > 1.25        -> .drifting(pct: Int((paceRatio - 1) * 100))
else                            -> .onPace

isMeaningful = dayOfMonth >= 5 && spent >= cap * 0.08
```

Two guards matter more than they look:

**Early-month suppression.** On day 1 a single $50 grocery run against a $500
cap is 3,100% ahead of pace. Without `isMeaningful`, every month opens with the
UI screaming. Suppressing until day 5 *and* 8% of cap keeps it quiet until
there's signal.

**A 25% tolerance band.** This was 15% until it was simulated over a month of
synthetic spending, which showed 1.15 producing isolated single-day drift
spikes — flag on day 5, clear on day 6, flag again on day 9 — four state flips
in a normal month. That is precisely the pattern that trains people to ignore a
cue. Measured flips over days 5–31:

| Threshold | Normal month | Blowout month |
| --- | --- | --- |
| 1.15 | 4 flips, warns day 5 | 1 flip, warns day 5 |
| 1.20–1.30 | 1 flip | 1 flip, warns day 5 |
| 1.40 | 1 flip | 3 flips |

A 2-day hysteresis and a 1.25-enter / 1.10-exit dead band both fixed it too,
but both require remembering yesterday's state — which makes pace impure and
therefore unreliable across relaunch and across sync from the partner's device.
A plain 1.25 threshold gets the same result statelessly. Prefer it.

### The tension a higher threshold creates

At 1.25 the simulated "normal" month gets no badge until day 30 — and it does
finish 9% over cap. So a threshold quiet enough to be trusted is also too quiet
to warn in a marginal month.

The resolution probably isn't the threshold. It's a division of labour: **the
pace tick carries the fine-grained signal continuously and silently, and the
badge is reserved for genuine trouble.** A month that ends 9% over doesn't
warrant an alarm — the tick sitting slightly behind the fill was visible all
along for anyone who looked. Worth confirming against real spending data before
committing.

### Fixed vs variable buckets — the one that breaks the pace line

Pace is meaningless for a bucket paid as one charge. Rent lands on day 1, so
Housing reads "3,000% ahead of pace" every month until roughly day 28. Same for
Subscriptions and Savings transfers.

This needs a `cadence` on `Bucket`:

- `.fixed` — housing, subs, savings. Evaluate **over/under only**, never pace.
- `.variable` — food, transport, fun, shopping, health. Pace applies.

**Consequence for the month-level pace chart:** computing it on total spend is
wrong for the same reason. With $1,300 of a $3,110 cap landing on day 1, the
cumulative line sits above the straight pace line for most of the month and
reads as alarming when nothing is wrong. The chart should either plot variable
spend against a variable-only cap, or draw fixed commitments as a baseline
offset the pace line starts from. Worth deciding before building it.

## 3. Chart decisions

**Add: cumulative spend vs pace line.** Makes "on pace" literal — a line you
are above or below, with a dotted projection to month end. Subject to the fixed
vs variable caveat above.

**Retire: the 8-slice donut.** No labels, no leader lines, so every read
requires cross-referencing the legend below it; slices under 5% are invisible
slivers. Replace with a single sorted horizontal stacked bar, labels attached
inline, everything under 5% folded into "Other, N more". Answers the same
question in one glance instead of two.

**Fix: the bubble cloud's scale is decorative, not informative.**
`size = base * (0.74 + 0.26 * (total / largest))` means a bucket at 5% of the
largest still renders at 76% of its slot diameter. Combined with five
hand-placed slots of differing `base`, a smaller amount in slot 1 can render
larger than a bigger amount in slot 2. Also buckets 6–8 vanish silently.
Either scale by √area across a full 0→1 range, or keep bubbles as a top-3 hero
with an honest ranked list beneath. Home is the wrong place for it either way —
move it to Stats, where decoration is fine.

**Split the two questions the category bars are currently answering.** On Stats
they're normalised to share of total spend; on Budget they should be against
cap with a pace tick. A category at 40% of spend but comfortably under budget
currently looks alarming.

## 4. Accessibility fixes in the current palette

Measured, not estimated:

| Token | Hex | Surface | Ratio | Verdict |
| --- | --- | --- | --- | --- |
| `Palette.muted` | `#565C72` | navBar | 2.59 | **fail** |
| `Palette.muted` | `#565C72` | card | 2.41 | **fail** |
| `Palette.sub` | `#7C8199` | card | 4.16 | fail for small text |
| `Palette.sub` | `#7C8199` | screen | 4.68 | pass |
| `Palette.label9` | `#9AA0B6` | screen | 6.93 | pass |
| `Palette.chipText` | `#B7BDD0` | chip | 7.82 | pass |

`Palette.muted` renders the unselected tab labels at 9.5px in `BottomBar`, the
`/` separator, and the `$` prefix in `BudgetRow`. At 2.4:1 that is not legible
in daylight. Lifting it to `#777F9D` reaches 4.55 on screen and 4.04 on card.

`Palette.sub` is the most-used secondary colour in the app and sits just under
AA on card surfaces. Either lift it or reserve it for screen backgrounds and
use `label9` on cards.

Beyond contrast: the donut, the bubbles, and the person split bar are all
colour-only encodings. Every one needs a redundant channel — a value label, an
icon, or a pattern.

## 5. IA and flow gaps

- **No month navigation.** Everything is hardcoded to the current month.
  `MonthDigest.previousSpent` means the data path is half built.
- **Home and Stats answer the same question.** Both are "where did the money
  go". If Home becomes "are we OK, and what can I spend today" and Stats stays
  retrospective, the four tabs earn their space. Folding Budget into Stats
  gets to three tabs.
- **Seeded caps are almost certainly wrong.** New households get
  `AppModel.defaultCaps` ($1,300 housing, $500 food). Every pace cue is
  meaningless until those are real, so onboarding should ask for a monthly
  total and split it.
- **`LogView` has no filter, search, or edit** — only delete. Per-person
  filtering is the obvious ask in a shared app.
- **The "together" half is thin.** An 8px dot per entry and one split bar. No
  shared-vs-personal distinction, no settle-up, no signal when a partner logs
  something. That's the differentiator, and it's unbuilt.

## Suggested order of work

1. Fix `Palette.muted` and `Palette.sub` contrast — smallest diff, real bug.
2. Split `Status` from `Bucket` in `Theme.swift`, add the no-shared-hex test.
3. Add `cadence` to `Bucket` and the `PaceState` computation to `AppModel`.
4. Rebuild the Budget row with cap marker, overage tail, and status line.
5. Rebuild Home to lead with pace and safe-to-spend; move bubbles to Stats.
6. Replace the donut with the sorted stacked bar.
7. Then the pace line chart, once the fixed vs variable question is settled.
