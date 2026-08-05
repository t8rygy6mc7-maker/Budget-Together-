# Accessibility Statement for Budget Together

**Effective date:** August 5, 2026
**Last updated:** August 5, 2026

## The short version

Budget Together is built to work with the accessibility settings you already
have switched on. Text obeys the size you chose. Movement stops when you have
asked for less of it. Every colour in the app has been measured for contrast
rather than eyeballed. Nothing important is said with colour alone.

There are things it does not do yet, and they are listed further down under
"What doesn't work yet". We would rather tell you than have you find out.

## Who this covers

This statement covers the Budget Together iPhone app, version 1.0, published by
Ren. It describes the app as it actually behaves today, not as we intend it to
behave later. If something here is wrong, or something is hard to use and isn't
mentioned, write to budgetog@icloud.com

## Text size

Every piece of text in the app scales with the text size you set in iOS
Settings, including the accessibility sizes. There are no fixed font sizes left
in the app.

Sizes scale at different rates on purpose. Small type — the tab labels, the
category captions — grows hardest, because that is the type that is actually
hard to read at default settings. Large display numbers grow most gently. The
result is that the layout keeps its hierarchy as you turn text up, instead of
collapsing into one uniform size.

Where a layout genuinely cannot survive the largest sizes, it changes shape
rather than truncating. The three-figure summary rows on Home ("Budget left /
Safe daily / Days left") stop sitting side by side and stack into a list once
you reach the accessibility sizes. Nothing is dropped and nothing is cut off;
only the direction changes.

Money amounts are the one exception to wrapping: an amount is held to a single
line and shrinks to fit if it has to. This is deliberate. "$1,965" broken after
the comma is not a harder-to-read version of the number — it is a different
number.

## Colour and contrast

Every text colour in the app has been measured against every surface it can
appear on, in both the light and dark schemes. All of them meet the WCAG 2.1 AA
threshold of 4.5:1.

The measurements were taken against the strictest surface in each scheme rather
than the most flattering one. In the dark scheme this means cards, not the
screen background — cards are the lighter surface, so they are the ones that
squeeze light text, and a colour checked only against the screen has been
checked against the easy case.

The two status colours are measured too: the amber used for "ahead of pace"
reaches 7.89:1 on cards, and the red used for "over" reaches 4.74:1.

**One documented exception.** The app's dimmest grey measures 4.17:1 on the
chip surface, below the threshold. Every remaining use of it there is an
*inactive* control — a save button that isn't ready yet, a dimmed month arrow at
the end of the range, a locked badge icon. WCAG exempts inactive components from
the contrast requirement, so this is a deliberate exemption rather than an
outstanding fault. It stops being exempt the moment that grey is used for live
text on a chip, and we treat it that way.

## Colour is never the only signal

Colour in this app tells you *what* something is, never *how it is going*. A
bar is coral because it is Housing, always and only. It never turns red to warn
you.

Status is carried separately, and always by more than one channel at once:

| State | How you can tell |
| --- | --- |
| On pace | No marker, no icon, no message. The absence of alarm is the signal. |
| Drifting | An icon **and** the words "N% ahead of pace" |
| Over | A tail past the cap marker **and** an icon **and** "Over by $N" |

So if you cannot distinguish the colours, or cannot see them at all, you have
not lost any information about whether your budget is in trouble. The words say
it.

The same rule applies to the charts. Every figure in them is also written out in
text somewhere you can read or hear it.

## VoiceOver

The app is labelled for VoiceOver throughout — roughly seventy labels across
every screen.

The charts, which would otherwise be silent shapes, are given spoken
equivalents:

- The **person split bar** reads out each person's name and their total.
- The **trend chart** reads each column as its period, what was spent, and what
  came in.
- The **category breakdown** on Home reads each row as the category, the amount
  and the share — and speaks "under 1%" where the screen shows "<1%", so
  VoiceOver doesn't have to pronounce a chevron.

Decorative artwork is hidden from VoiceOver rather than announced as
meaningless images. Selected options — categories, people, recurrence choices —
carry the selected trait, so you are told which one is currently chosen instead
of having to infer it from a highlight.

The undo offer that appears after you add or delete something is marked as
modal, so VoiceOver moves to it when it appears. That offer expires on its own
after a few seconds, and an offer you are never told about is an offer you
cannot take.

## Entering things another way

You can speak an amount instead of typing it on the add screen. The recognition
happens on your iPhone itself — nothing is sent anywhere — and it fills in the
field you were already in. It needs microphone and speech permission, and the
rest of the app works normally if you would rather not grant them.

## Motion

If you have Reduce Motion switched on in iOS Settings, the app stops moving
things. Panels that would expand, rows that would slide into place, the add
screen's details section, and the tab bar gaining a tab all simply appear in
their new state instead.

Two things deliberately keep animating, because neither of them moves anything.
The full-screen overlays fade in rather than slide, and switching between the
light and dark schemes cross-fades the colours. A fade *is* the accommodation
Reduce Motion asks for, so removing it as well would be missing the point.

The undo toast is the one case needing more thought. It expires on its own after
twelve seconds, so it has to be noticed to be used — and something appearing
from nowhere, with no change to catch the eye, is worse for the person the
setting exists for rather than better. Under Reduce Motion it trades its upward
slide for a cross-fade and keeps the same twelve seconds.

## Haptics

The app uses short vibrations sparingly and only where something actually
happened: an entry saved, an action undone, a limit crossed, a challenge
finished. A buzz on every tap stops meaning anything, so there isn't one.

## Making the app quieter

Some of what makes an app usable is not about perception at all. These are the
controls for how much the app asks of you at once:

- **"Just show me my fun money."** One tap on Home replaces the full budget
  with a single number: what is genuinely yours to spend. Everything else is
  still there when you want it.
- **Screens arrive gradually.** The app starts with Home and the Log. Budget
  appears once you have a plan or a few entries, Stats a little after that. Both
  are reachable from Home before they appear, and once a screen has appeared it
  never disappears again.
- **Alerts are off until you ask for them.** Limit notifications are opt-in, and
  each category can be muted on its own — health being the obvious one where an
  unsolicited alert about your spending lands worst.
- **The app stays quiet early in the month.** A single shop on the 2nd is not
  evidence of anything, and an app that warns you on day one is an app you learn
  to ignore. Pace warnings are suppressed until there is genuinely a signal.
- **Erasing everything requires typing the word DELETE.** A destructive button
  is one stray tap away; a word you have to spell is not.

Light and dark schemes are both fully supported, and you can pin the app to
either one rather than following the system.

## What doesn't work yet

We would rather list these than let you discover them.

- **The donut chart on Stats speaks only its total.** VoiceOver announces the
  total spent but not the individual slices, so the breakdown it shows is not
  available through it. The same figures *are* fully readable in the category
  breakdown on Home, which is labelled properly — so the information is
  reachable, but not from the donut itself.
- **Portrait only.** The app does not rotate to landscape. If you mount your
  phone, or find landscape easier with an external keyboard, that is not
  available.
- **iPhone only.** There is no iPad or Mac version, so the larger screen that
  would help some people read it is not an option yet.
- **Voice Control and Switch Control have not been audited.** VoiceOver labels
  usually carry both, so much of the app is likely to work, but we have not gone
  through it and cannot claim it.
- **Tap target sizes have not been systematically checked** against the 44×44pt
  minimum.
- **Two secondary greys swap rank between the light and dark schemes.** Both
  clear the contrast threshold, so nothing is unreadable, but the same two
  colours carry slightly different visual weight depending on which scheme you
  use.

## How this was tested

Honestly: by measurement and by inspection, not by audit.

The contrast figures in this statement are calculated, not estimated, and are
recorded with their derivations in the project's design notes. The Dynamic Type
behaviour has been exercised across the full range including the accessibility
sizes. The VoiceOver labelling has been written deliberately screen by screen.
The Reduce Motion behaviour was checked on a device with the setting actually
switched on, rather than only in code — including that the undo toast still
appears, still reads, and can still be used.

What has *not* happened: a formal accessibility audit, testing with a
screen-reader user, or testing with any assistive technology beyond VoiceOver.
Nothing here has been verified by anyone outside the project. Treat this
statement as a careful self-assessment, which is what it is.

## Standards

We use WCAG 2.1 Level AA as the reference for contrast and for
not-colour-alone, and Apple's Human Interface Guidelines for everything else.
WCAG was written for the web rather than for native apps, so parts of it map
imperfectly; where it applies cleanly, we hold to it, and the one deliberate
exemption is described above.

We do not claim full WCAG 2.1 AA conformance. The gaps listed above are real
ones.

## Feedback

If something in this app is hard to use, we want to know, and a specific report
is worth more than a polite one. Tell us what you were trying to do, what
happened, and which accessibility settings you have on.

budgetog@icloud.com

We read everything sent there. We cannot promise a fix by a particular date, but
we will tell you honestly whether one is planned.

## Changes to this statement

If the app changes in a way that affects this statement — particularly if
something in "What doesn't work yet" gets fixed — we will update this page and
change the date at the top.

---

*This document describes the behaviour of Budget Together version 1.0. It is a
self-assessment, has not been externally audited, and is not a legal
conformance claim.*
