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

Measured, not estimated. The whole neutral type ladder in the dark scheme,
darkest rung first:

| Token | Hex | card | screen | navBar | Verdict |
| --- | --- | --- | --- | --- | --- |
| `Palette.muted` | `#82889F` | 4.55 | 5.12 | 4.88 | pass |
| `Palette.sub` | `#8F94AC` | 5.33 | 6.01 | 5.71 | pass |
| `Palette.label9` | `#9AA0B6` | 6.15 | 6.93 | 6.59 | pass |
| `Palette.chipText` | `#B7BDD0` | 8.54 | 9.61 | 9.15 | pass |
| `Palette.text` | `#EDEFF7` | 13.94 | 15.70 | 14.93 | pass |

`muted` and `sub` are the two that moved; `#565C72` and `#7C8199` are what they
used to be, at 2.41 and 4.16 on `card`. §4c has the derivation.

Note the ordering: `card` is the strictest surface for every rung, not `screen`.
Dark-scheme intuition runs the wrong way here — `card` is the *lighter* surface,
so it is the one that squeezes light text. Anything measured only against
`screen` is measured against the easy case.

`Palette.muted` renders the unselected tab labels in `BottomBar`, the `/`
separator, and the `$` prefix in `BudgetRow`. Those are the smallest type in the
app — a 9.5pt base for the tab labels — and since every size now scales through
`.appFont()` (see `Comfort.swift`), 9.5pt is the *floor* rather than the fixed
size. A token that only just works at the default size has to work there.

`Palette.sub` is the most-used secondary colour in the app; it now clears AA on
`card` outright, so the "reserve it for screen backgrounds and use `label9` on
cards" workaround is no longer needed.

Beyond contrast: the donut, the bubbles, and the person split bar are all
colour-only encodings. Every one needs a redundant channel — a value label, an
icon, or a pattern.

## 4c. Lifting the two failing dark neutrals

`muted` and `sub` were the last tokens failing AA in either scheme — their light
counterparts were fixed during the light-scheme pass (§4b), so this was an
asymmetry rather than a plain bug. Both dark halves were lifted; the light
halves are untouched.

### The rule

Same principle as §4b, but held in **LCh rather than HSL**: keep `C*` and hue
fixed, move `L*` only. Held in HSL it isn't actually true — above HSL-L 50 a
constant `S` sheds chroma as `L` rises, so a token quietly greys out as it
lifts. In LCh the cool blue-grey cast survives the lift:

| Token | Before | After | ΔC* | Δhue |
| --- | --- | --- | --- | --- |
| `muted` | `#565C72` | `#82889F` | 13.6 → 13.3 | 282.7° → 282.3° |
| `sub` | `#7C8199` | `#8F94AC` | 13.9 → 13.6 | 284.3° → 284.1° |

Both deltas are hex-quantisation noise, not drift.

### Why `#777F9D` was not the answer

The value this note previously suggested for `muted` reaches 4.55 on `screen`
and 4.04 on `card` — it clears the easy surface and fails the one that governs.
Landing on `card` instead puts the floor at `#82889F`, L\* 56.9.

### The consequence nobody gets to avoid

4.5:1 on `card` requires L\* ≥ 56.6. `label9` sits at L\* 66.1 and already
passes, so it is the ceiling. That leaves **9.2 L\* of room for two rungs** —
`muted` on the floor, `sub` somewhere below `label9`:

| Rung | L\* before | L\* after |
| --- | --- | --- |
| `muted` | 39.3 | 56.9 |
| `sub` | 54.3 | 61.7 |
| `label9` | 66.1 | 66.1 |
| `chipText` | 76.7 | 76.7 |
| `text` | 94.5 | 94.5 |

| Gap | Before | After |
| --- | --- | --- |
| `muted` → `sub` | 15.0 | 4.7 |
| `sub` → `label9` | 11.7 | 4.4 |
| `label9` → `chipText` | 10.6 | 10.6 |
| `chipText` → `text` | 17.8 | 17.8 |

Placing `sub` at the midpoint is what maximises the smaller of the two gaps, so
4.4 is the best available, not a rounding choice. The ordering survives and the
bottom three rungs are still distinguishable side by side — but they are
distinguishable, not obviously stepped, where they used to span 26.7 L\*.

That is the honest cost of holding `label9`, `chipText` and `text` fixed while
raising the floor 17.6 points. **If the hierarchy needs to breathe again, the
move is to lift the upper rungs too and redistribute across the whole legal band
(L\* 56.6–100, ~43 points for five rungs), or to accept that the ladder has one
rung too many.** Compressing further is not available.

### Found while measuring: `sub` and `label9` are swapped in light

Not introduced here, and not fixed here — the light values are frozen — but it
turned up while checking the ladder held in both schemes, and it should be
written down before someone "fixes" one scheme to match the other.

In light, darker means more prominent, so a mirrored ladder should run
`muted` → `sub` → `label9` → `chipText` with L\* *decreasing*. It doesn't:

| Token | Light hex | L\* | vs screen |
| --- | --- | --- | --- |
| `muted` | `#686F84` | 46.9 | 4.59 |
| `label9` | `#646B82` | 45.4 | 4.86 |
| `sub` | `#5A6076` | 41.0 | 5.72 |
| `chipText` | `#474D61` | 32.9 | 7.70 |

`sub` and `label9` trade places. In dark, `label9` is the more prominent of the
two; in light, `sub` is. Both schemes clear AA, so nothing is broken — but the
same two tokens rank differently depending on the scheme, which means any view
that leans on their relative weight reads differently in light than in dark.

Deciding which order is correct is a design call, not a contrast one, and it
wants doing in one place for both schemes rather than as a patch to whichever
scheme is being looked at.

### Residual: `chip`

`muted` measures 4.17 on `chip` (`#232838`), which is lighter than `card` and
therefore stricter still. Every remaining `muted`-on-`chip` use is an inactive
control — the disabled save buttons, the month-stepper arrow at 0.4 alpha, the
locked badge icons in `WinsSheet` — and WCAG 1.4.3 exempts inactive components,
so this is deliberate rather than outstanding. It stops being exempt the moment
`muted` is used for live text on a chip. Related to the accent-on-`chip` gap at
the end of §4b, and with the same fix: lighten `chip`.

## 4b. Deriving the light scheme

The dark palette is the "Midnight" comp and stays fixed. Light is derived from
it by rule, not redrawn, so the two schemes can't drift apart.

### The rule

1. **Hue and saturation are held constant.** Per §1, fill encodes identity. A
   bucket that changes hue between schemes stops being the same bucket.
2. **Lightness is inverted into a light-surface band.** Each family's dark
   lightness range is mapped onto a light band with the order reversed —
   brightest-in-dark becomes darkest-in-light. This preserves *relative*
   prominence and, more importantly, the spacing between neighbours.
3. **Then darkened until it clears 4.5:1** against both `card` (`#FFFFFF`) and
   `screen` (`#F4F5F9`), whichever is stricter.

Step 2 is the one that matters. Two earlier attempts failed:

| Attempt | What broke |
| --- | --- |
| Straight inversion of the hex | `#5EEAD4` teal lands at 1.3:1 on white. Unusable as text or icon. |
| Mirror each token's *dark contrast ratio* | Pale hues become near-black. Savings went to `#09453C` (L 15%) and Shopping to `#584611`, which reads as mud, not yellow. |

### Why spacing, not contrast, is the thing to preserve

Health (`#F6A5C8`, H 334°) and Fun (`#D45C87`, H 338°) are 4° apart. In dark
they are separable only by lightness — 80.6 vs 59.6, a 21-point gap. Any
derivation that targets contrast per-token collapses that gap and makes two
buckets indistinguishable. Band-mapping keeps it:

| Pair | Dark ΔH / ΔL | Light ΔH / ΔL |
| --- | --- | --- |
| fun / health | 4.4° / 21.0 | 4.1° / 15.5 |
| food / savings | 16.6° / 15.7 | 16.9° / 13.7 |
| stress / regret | 15.1° / 0.6 | 15.5° / 0.6 |

### Derived values

Measured against `card` `#FFFFFF` and `screen` `#F4F5F9`:

| Token(s) | Dark | Light | card | screen |
| --- | --- | --- | --- | --- |
| `teal`, savings, member teal | `#5EEAD4` | `#107F6E` | 4.90 | 4.50 |
| `green`, food, salary | `#3FB984` | `#2B7E5A` | 4.96 | 4.55 |
| `purple`, subs, moodSocial | `#C69BFF` | `#390085` | 13.88 | 12.74 |
| `over`, housing | `#E86A4A` | `#BC3918` | 5.62 | 5.16 |
| `overText`, health, gifts | `#F6A5C8` | `#790C3B` | 10.89 | 9.99 |
| transport, refunds | `#5B8DEF` | `#1147B0` | 8.23 | 7.55 |
| fun | `#D45C87` | `#A82C59` | 6.63 | 6.08 |
| shopping, other-in | `#E0C05B` | `#886D1A` | 4.94 | 4.54 |
| `moodJoy`, member amber | `#F5C15E` | `#98670A` | 4.91 | 4.50 |
| `moodStress` | `#F2555A` | `#D51017` | 5.36 | 4.92 |
| `moodBoredom` | `#8892B0` | `#626E93` | 5.03 | 4.62 |
| `moodRoutine`, member blue | `#7FB2FF` | `#0048B6` | 8.07 | 7.41 |
| `moodRegret` | `#E0846A` | `#BB4827` | 5.16 | 4.74 |

Surfaces mirror the dark scheme's *relationships* rather than its values —
`card` lifts off `screen` in both, `field` recedes into it in both, only the
direction of the lift flips:

| Token | Dark | Light | Separation dark → light |
| --- | --- | --- | --- |
| `screen` | `#141620` | `#F4F5F9` | — |
| `card` | `#1D2130` | `#FFFFFF` | 1.13 → 1.09 |
| `field` | `#141620` | `#EFF1F7` | 1.13 → 1.13 |
| `chip` | `#232838` | `#EAEDF5` | 1.09 → 1.17 |
| `cardBorder` | `#2A3042` | `#D6DBE9` | 1.22 → 1.38 |
| `cardBorderSoft` | `#23283A` | `#E5E9F3` | 1.09 → 1.22 |

Borders are deliberately *firmer* in light. A light UI has less luminance
headroom above the card, so a border matched to the dark scheme's 1.09 would
disappear.

### The two things that don't derive

**Coloured glows.** The add button, the pairing hero, and the Home bubbles all
carry a bloom of their own colour. That reads as light on a dark screen and as
a smudge on a white one. `Palette.addGlow` and `Bucket.glow` carry both schemes
with the alpha baked in — a plain neutral drop shadow at 0.18 in light, the
original teal bloom at 0.55 in dark. Alpha has to live inside the colour
because `.opacity()` at the call site cannot vary by scheme.

**Avatar ink.** In dark, a member is a pale chip with dark ink. In light the
fill inverts to deep, so ink flips to white — verified ≥4.5:1 on every one of
the eight member colours.

### Known gap

Accent colours sit at 4.08–4.67 against `chip` (`#EAEDF5`), just under AA. In
practice accents are never drawn on chip — `chipText` is — but if that changes,
lighten `chip` or darken the accents.

## 5. IA and flow

Rewritten 27 July 2026, after the usability pass (`4c6bada`…`0671715`). Most of
what this section listed as missing is now built, and one item was resolved by
deciding the opposite of what it recommended. What follows is what shipped, the
mechanics that shipped without ever being written down, and what's still open.

### Settled

**Month navigation.** `MonthStepper` (`RootView.swift:134`) sits in the header of
all four tabs and drives a single selection for the whole app —
`AppModel.selectedMonth`, stepped by `stepMonth(_:)` and reset by
`goToCurrentMonth()`. Forward stops at the current month, since there's nothing
to show past it; tapping the label jumps back. `isCurrentMonth` turned out to be
the load-bearing part: pace, safe-daily, days-left, rollover and the weekly
framing all suppress themselves on a closed month rather than reporting a figure
that can't mean anything. `MonthDigest.previousSpent` is now wired through to
`monthOverMonth`.

**Onboarding asks for nothing, and seeds no caps.** This resolved the opposite
way from the recommendation it replaces. `createHousehold` takes an *optional*
`monthlyTotal`, and with nothing supplied the household starts with **no limits
at all** (`AppModel.swift:156`); the field is folded behind "Set a monthly figure
now (optional)" on `PairingView`. Asking for a number on the first screen makes
people commit before they've seen anything, and the ones who don't know their
monthly total — the ones with most to gain — are exactly the ones it turns away.

That makes *no plan* a normal starting state rather than a broken one, which has
consequences everywhere: `hasPlan` guards every cap-derived figure, anti-budget
mode is unavailable without one, and Home omits the "Left to spend / A day from
here" row rather than announcing `$0` to someone who simply hasn't set anything
yet.

The number is earned later instead. `suggestedPlan()` derives a per-category
limit from real spending — each category's own monthly average plus 10% headroom,
rounded to a figure someone would say out loud ($10/$25/$50 steps by magnitude) —
and `canSuggestPlan` withholds the offer until there are 10+ expenses and no plan
yet. `SuggestedPlanCard` presents it on Budget. Hidden categories are filtered
out, so no limit can land on the plan without a row anywhere to change it.

There's a third way in as well: **"Have a look around first"**
(`startLookingAround()`) fills the app with a worked example, and
`discardSampleAndStartOver()` throws it away, so a first real entry never lands
in a demo household next to Sam's rent.

**`LogView` has filters and edit.** Kind (`All` / `Spending` / `Income`) and
per-person chips, both view-local; tapping any row opens `AddSheet` in edit mode.
Delete is no longer the only verb.

**Search is still missing**, and that part of the original bullet stands. The
filters answer *who* and *which direction*; they don't answer "what did we pay
that plumber". That question gets more common the more history there is — which
is precisely when scrolling stops being an answer.

*Update, 4 August 2026 — search landed.* A field above the filters matches place,
note, category label, person, mood, and the amount as typed: "26" finds a $26.00
lunch, because bare digits are what somebody actually types. Category and person
are searchable even though neither is in the entry's own text, since "which
category" and "who" are exactly how people describe a purchase they're trying to
find again. The matching lives in `AppModel.search(_:monthOnly:)` rather than in
the view, because the full ledger is `AppModel.allEntries` and is deliberately
unpublished — the Log screen only ever holds the selected month.

Scope turned out to be the actual design decision. Searching only the month on
screen answers the plumber question by luck of which month happens to be
showing; silently widening to every month would file March's dinners under a
July heading with nothing to explain why. So it stays inside the selected month,
and when nothing matches there the empty state says how many matches sit
elsewhere and offers to widen — an offer taken by the user, not for them. Once
widened, day headings switch from "Yesterday" to the full date, because across
months a weekday names nothing.

**The "together" half.** Entries carry a free-text `note` in the spender's own
words, and anyone can react to one: `ReactionKind` is four options (`heart`,
`thumbsUp`, `flame`, `smile`), one per person per entry, tap-again to clear.
Reactions are their own `CDReaction` rows rather than a field on the entry, so
two people reacting from two phones merge instead of overwriting each other.
`EntryRow.showsSocial` keeps notes and reactions off Home, where the list is a
glance, and on in the log, where it's the shared space. `LogView` also opens with
an ambient presence line — overlapping avatars plus "Alex added something today"
— which reports that somebody is keeping up their end without naming a figure.
That distinction is the whole design: company, not surveillance.

*Added 4 August 2026 — savings goals.* `Goal` is deliberately the mirror image of
`Loan`: both are a balance moving toward a number, which is why the "Saving for"
card sits directly above "Owed" on Budget, and why a goal is typed in by hand the
way a loan is. There is no bank connection, so the app holds the figure it was
given and never claims to know a balance it wasn't told.

The tempting alternative was to derive progress from entries filed under Savings,
and it doesn't survive contact with a second goal: nothing in a transfer says
which goal it belonged to. Attributing it would be a guess, and a progress bar
built on a guess is worse than one that asks — so contributions are recorded
explicitly, via a top-up sheet of their own. That separation is the point. Adding
to a goal is the frequent action and rewriting its target is the rare one, and
they shouldn't share a screen where a slip does the wrong one.

Both the deadline and the monthly contribution are optional, and `paceLabel(on:)`
says the most useful true thing the user has given it the means to say — months
to go at the current contribution, or what has to go in monthly to make a date,
or just what's left. A form that demands a deadline gets an invented deadline,
which then drives every "you need $N a month" line underneath it. The picker
opens six months out rather than today for a related reason: a deadline of today
contains no months, so the pace line falls back to the open-ended answer and
switching the toggle on appears to do nothing.

`CDGoal` marks name, target, saved and contribution as `secret()`, so they ride
in CloudKit's `encryptedValues` alongside the loan figures rather than sitting in
the record's plain fields. The reasoning is on `CDModel.secret(_:_:)` in
`Persistence.swift`: identifiers and flags stay in the clear because predicates
need them, and what a thing costs does not.

### Mechanics that shipped undocumented

Most of these are one idea: **a budget you've broken should offer you a move, not
just a verdict.**

- **Undo on every destructive action.** `AppModel.UndoableChange` covers nine
  cases — deleted entries (with their reactions), edits, recurring items, loans,
  members (with all their entries), cap changes, cap moves, and category edits
  and deletions. Stored as data rather than closures, so nothing captures `self`
  and the pending change stays inspectable. The offer stands 12 seconds, up from
  7: the window has to cover noticing the toast, reading it, deciding, *and*
  reaching the button, while it covers part of the list the whole time. The point
  isn't recovery — most deletions are deliberate — it's that people tap and
  explore more freely when a mistake visibly costs one tap.

- **Move money between categories.** `MoveMoneySheet` reallocates headroom from
  one category to another for the selected month, prefilled with exactly the
  shortfall. The plan total never changes, and that's what keeps it honest — it's
  a reallocation, not a quiet raise, so a household reaching for it repeatedly
  can still see the overall figure holding steady. With every other category
  already spent up, it says so and suggests raising the limit directly instead.

- **Rollover.** Off by default, toggled on Budget. What last month left on the
  table carries into this one (`AppModel.rollover` → `plannedTotal`), current
  month only, and **only ever positive** — carrying an overspend forward would be
  a punishment mechanic, and this exists to be the opposite of one.

- **Unusual months.** A month can be flagged with a reason (`markMonthUnusual`,
  `UnusualMonthSheet`: seven presets plus free text). It keeps its entries and
  its totals — it happened — but drops out of streaks, badges and the
  month-over-month comparison, and `monthOverMonth` returns `nil` when either
  side of the comparison is flagged. The argument is arithmetic before it's
  kindness: one month with a deposit and a moving van in it sits in the trailing
  average for the next six, and the app spends that whole stretch reporting a
  decline that never happened.

- **One forgiven day in the streak.** `Wins.graceDays = 1`. A single
  over-allowance day is absorbed inside a run; a second ends it. The forgiven day
  is carried, not credited — it doesn't extend the count — and `graceUsed` is
  surfaced so the next slip doesn't read as an unexplained reset. Without it the
  first dinner out in a good fortnight zeroes the counter, and a counter that
  punishes one ordinary evening gets ignored by about the third time it happens.

- **Limit alerts are opt-in.** They used to be on for everything from first
  launch: the app's loudest possible voice, carrying its least welcome message,
  unprompted. `limitAlertsEnabled` is now off until asked for, the system
  permission prompt is attached to the user turning it on rather than to launch,
  and each category can be muted individually (`Notifier.setMuted(_:for:)`) —
  health being the obvious case where an unsolicited push lands worst. Raising a
  cap clears that month's fired flags, so new headroom can alert on its own
  terms.

- **Progressive tab disclosure.** `AppModel.visibleTabs` starts at Home and Log.
  Budget appears once there's a plan or three entries, Stats at five. Both stay
  reachable from Home before that, so nothing is actually locked away, and
  `revealedTabs` makes a revealed tab permanent — having one vanish again under
  someone who just used it would be worse than never hiding it. `reload()` moves
  off a tab that's just been hidden rather than leaving it selected.

- **Dynamic Type throughout.** Every font was a hardcoded `.system(size:)`, which
  silently ignores the text size the user chose — in a money app, for the users
  most likely to have changed it. `.appFont()` (`Comfort.swift`) is the drop-in
  replacement: `@ScaledMetric` against a text style picked by size band, so a
  9.5pt tab label scales harder than a 44pt balance and the hierarchy survives
  instead of collapsing into one size. `mono()` gained `lineLimit(1)` and
  `minimumScaleFactor(0.5)`, because an unconstrained "$1,965" breaking after the
  comma isn't a degraded reading of the number — it's a different number.
  Layouts that can't survive the top of the range switch rather than truncate:
  `prefersStackedLayout` turns `StatRow`'s three columns into rows, and
  `prefersPlainList` swaps the bubble cloud for the honest ranked list §3 asks
  for.

- **Reduce Motion, honoured.** `Comfort.swift`'s header had claimed the app gave
  "motion that stops when they've asked for less of it" since the comfort pass;
  nothing in the target read the setting, so for a year that sentence was just
  aspiration. `withAppAnimation`, `.appAnimation(_:value:)` and
  `Binding.appAnimation` are the drop-in replacements, in the same shape as
  `appFont`. The rule they encode is that **Reduce Motion objects to movement,
  not to animation** — Apple names the cross-dissolve as the safe substitute for
  a slide, so an animation that moves, resizes or reflows is suppressed outright
  and one that only cross-fades is left alone. Hence `JoiningOverlay`,
  `PrivacyCover` and the appearance picker keep their plain `.animation`: fading
  is already the accommodation. `UndoToast` is the interesting case and doesn't
  fit either branch — it expires on a timer, so it has to be *noticed* to be
  taken, and suppressing its animation entirely would have it blink into
  existence mid-scroll. It swaps the slide for a cross-fade and the spring for a
  plain ease, since overshoot is precisely the motion being objected to. That
  also means `AppModel.dismissUndo` must keep animating, and it carries a comment
  saying so — routing it through `withAppAnimation` would take the fade away
  from the one view that still wants one.

Two further changes landed immediately after the pass and belong here too:

- **Categories are user-defined.** `CategoryRegistry` replaces the fixed eight,
  which can now be added to, renamed, recoloured and hidden. §1's bucket table is
  therefore the *seed* set, not the whole set. Colours come from a closed list of
  the thirteen pairs already measured in §4b rather than a free colour well: a
  free picker would let someone choose a hue with no verified light counterpart,
  which fails in exactly one direction — the light scheme, on somebody else's
  phone, where the person who chose it never looks.

- **Export and erase.** `DataSheet` puts both on one screen deliberately. An app
  that keeps everything on-device has to let you take it away *and* destroy it,
  or "we never see your data" just means "you can't leave". Erase requires typing
  `DELETE`, since a destructive-role button is one stray tap away and a word you
  have to spell is not.

### Still open

- **Home and Stats still overlap.** Home now opens with a plain-language summary
  sentence rather than a large number and a red badge, and leads with
  safe-to-spend wherever there's a plan — which is what this section asked for.
  But the bubble cloud is still on Home, directly above the same "where did the
  money go" material Stats covers retrospectively. Moving it (§3) is what
  actually separates the two questions; until then the split is softer than it
  looks. Folding Budget into Stats still gets to three tabs.
- ~~**No search in the log.** As above — the filters don't reach it.~~ Done
  4 August 2026 — see the update under "Settled" above.
- **Goals don't reach the plan arithmetic.** A goal's monthly contribution is
  displayed on its own sheet and nowhere else — it isn't in `committed`, so it
  doesn't reduce `funMoney`, and it isn't in `plannedTotal` or the forecast.
  Somebody putting $300 a month toward an emergency fund has $300 less to spend
  and the safe-to-spend figure doesn't know it. The honest fix is probably not to
  fold it in silently, since a contribution is an intention rather than a booked
  expense, and quietly shrinking someone's spending money on the strength of an
  intention is its own kind of lie. But the two numbers currently sit on adjacent
  screens disagreeing, and that has to resolve one way or the other.
- **No shared-vs-personal split, and no settle-up.** Notes, reactions and
  presence made the log feel shared; none of them answer "we each put in $X, so
  who owes whom". `SplitBar` still reports proportions of spending, not balance.
  This is the last structurally missing piece of the differentiator.

## Suggested order of work

1. ~~Fix `Palette.muted` and `Palette.sub` contrast in the dark scheme.~~ Done —
   see §4c. Every neutral now clears AA in both schemes.
2. Split `Status` from `Bucket` in `Theme.swift`, add the no-shared-hex test.
   Worth adding a contrast test alongside it: assert the neutral ladder is
   monotonic in L\* and that every rung clears 4.5:1 on `card` in both schemes.
   §4c leaves `muted` sitting exactly on that floor, so it can't absorb a nudge.
3. Add `cadence` to `Bucket` and the `PaceState` computation to `AppModel`.
4. Rebuild the Budget row with cap marker, overage tail, and status line.
5. Rebuild Home to lead with pace and safe-to-spend; move bubbles to Stats.
6. Replace the donut with the sorted stacked bar.
7. Then the pace line chart, once the fixed vs variable question is settled.
