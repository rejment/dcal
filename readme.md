# DCAL

A visual calendar for people with limited capability to understand time.

One continuous vertical timeline you pinch to zoom, from the hours of today
out to a whole life on one screen.

## Running it

`index.html` is the whole prototype — no build, no dependencies. Open it
directly in a browser, or serve the folder:

    python3 -m http.server 8000 --directory ~/Projects/dcal

To try it on the phone, put the phone on the same wifi and open
`http://<this-mac's-ip>:8000`. Add it to the home screen and it runs
full-screen with no browser chrome.

## The idea

**The colour of the timeline is the time.** Close in, the column is painted
with the actual sky: deep blue at 3am, warm at sunrise, bright at midday.
Zoom out and the hours dissolve into seasons — cold blue January, gold July.
Zoom out further and the seasons dissolve into decades as visible strata.
You can tell roughly where you are before reading a single number.

**Detail arrives as you get closer, like a map.** At day scale every
appointment is a block, laid out in lanes like any calendar. Pan out and
those collapse: only milestones keep their labels, everything else stays as
a notch cut into the ribbon, so you can still see where life was busy.

**Age is a unit.** Every milestone is labelled with how old you were, and
the header carries your age at whatever point you're looking at.

**No gesture is required.** Pinch and double-tap work, but every one of them
has a button: the scale row, ± , Now, and a date jump in the ⋯ menu.

## Interaction

| | |
|---|---|
| Drag / scroll | move through time |
| Pinch, or ctrl+scroll | zoom |
| Double-tap | zoom into that spot |
| Press and hold | add something at that moment |
| Tap an event | open it |
| ↑ ↓ + − T | pan, zoom, jump to now |

## State of the prototype

Events live in `localStorage` under `dcal.lifeline.v1` and start as a sample
lifeline (reset it from the ⋯ menu). Rendering is a single canvas; the DOM
holds only the header, the control rail and the sheet.

Not done yet: repeating events, multi-day layout at day scale, sync,
importing a real calendar.
