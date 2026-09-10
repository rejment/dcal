# DCAL

A visual calendar for people with limited capability to understand time.

One continuous vertical timeline you pinch to zoom, from the hours of today
out to a whole life on one screen.

| | |
| --- | --- |
| `ios/` | The native SwiftUI app. See [ios/README.md](ios/README.md). |
| `index.html` | The web prototype the app was designed in. No build, no dependencies. |
| `make_icon.py` | Draws the app icon. Regenerated and checked by CI. |

## The idea

**The colour of the timeline is the time.** Close in, the column is painted
with the actual sky: deep blue at 3am, warm at sunrise, pale at midday. Zoom
out and the hours dissolve into seasons — cold blue January, gold July. Zoom
out further and the seasons dissolve into decades as visible strata. You can
tell roughly where you are before reading a single number.

**Detail arrives as you get closer, like a map.** At day scale every
appointment is a block, laid out in lanes like any calendar. Pan out and those
collapse: only milestones keep their labels, everything else stays as a notch
cut into the ribbon, so you can still see where life was busy. Which things
survive is a property of the event — *how big is this?* — not of its category.

**Age is a unit.** Every milestone is labelled with how old you were, and the
header carries your age at whatever point you're looking at.

**No gesture is required.** Pinch and double-tap work, but every one of them
has a button: the scale row, ±, Now, and a date jump in the ⋯ menu.

**The header always answers two questions, in the same shape.** A small line
naming the larger thing you are inside, a big line naming where you are:
*Thursday / 10 September 2026*, then *Week 37 / September 2026*, then
*The 2020s / 2026*. The units change; the shape never does.

## Interaction

| | |
|---|---|
| Drag / scroll | move through time |
| Pinch, or ctrl+scroll on the web | zoom |
| Double-tap | zoom into that spot |
| Press and hold | add something at that moment |
| Tap an event | open it |

## The web prototype

`index.html` is a single self-contained file. Open it directly, or serve the
folder:

    python3 -m http.server 8000 --directory ~/Projects/dcal

Its events live in `localStorage` under `dcal.lifeline.v1`. The app and the
prototype do not share data — the prototype is where the design was worked
out, and it is kept because it is still the fastest way to try a change.

## Not done yet

Reading your real calendar (EventKit) is the obvious next step and the thing
that would make this useful rather than only demonstrable. Also missing:
repeating events, multi-day layout at day scale, iPad, and any sync at all.
