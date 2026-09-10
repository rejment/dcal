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

## Backups, and editing a life on a computer

**⋯ → Backup** writes the lifeline out and hands it to the share sheet —
Files, iCloud, AirDrop, mail. **Save a backup** gives JSON, **Save as a
spreadsheet** gives CSV, and **Open a file** reads either back, asking whether
to replace everything or add to it. The kind is worked out from the contents,
not the file extension.

The file is meant to be typed in, not just parsed:

```json
{ "dcal": 1,
  "exported": "2026-09-10 22:31",
  "events": [
    { "title": "Born", "start": "1985-06-14 04:12",
      "weight": "milestone", "category": "life",
      "note": "A Friday morning, six weeks early." },
    { "title": "Japan", "start": "2016-04-02", "lasts": "16 days",
      "weight": "notable", "category": "travel" }
  ] }
```

Dates are local time, lengths say what they mean, and weights are the words
the app uses. Only `title` and `start` are required — a whole life can go in
as two columns and be filled in later. One event per line, so two backups
diff cleanly.

Reading is deliberately more forgiving than writing:

| written as | also accepted |
| --- | --- |
| `"start": "1985-06-14 04:12"` | `1985-06-14`, `1985-06`, `1985`, ISO 8601 with a timezone |
| `"lasts": "16 days"` | `16d`, `90 min`, `2h`, `1 week`, `"duration": 1382400` (seconds) |
| `"weight": "milestone"` | `0`–`3` |
| `"id": "…"` | omit it, and one is generated |

Anything the app has ever written imports, including its own store file, so an
old backup still works. Re-importing an edited export **updates** events rather
than duplicating them, because the ids come back with it — drop the `id` line
to turn an edit into a new event.

### The spreadsheet

For putting a life in from old photos and notes, a spreadsheet beats a text
editor — columns, sorting, fill-down, and a date picker. Same fields, one row
each, with the column names on the first row:

```
title,start,lasts,weight,category,note,id
Born,1985-06-14 04:12,,milestone,life,"A Friday morning, six weeks early.",…
Japan,2016-04-02,16 days,notable,travel,,…
```

Only `title` and `start` need to be there. Columns are found by name, so their
order doesn't matter, extra ones are ignored, and they can be called what a
spreadsheet would call them — `what`, `when`, `how long`, `how big` all work.

Reading copes with whatever saved the file: commas, semicolons (which is what
Excel writes on a Swedish machine) or tabs; Windows or Unix line endings; a
byte order mark; Excel's own `sep=;` first line. Fields are quoted on the way
out whenever they contain any possible separator, so a file survives being
re-saved by a spreadsheet that uses a different one.

### When something is wrong

The message names the event and says what to type — pointing at a JSON event
or a spreadsheet row, whichever you're looking at:

> "School" (row 3) has a date I can't read: "14 juni 1992". Write it as
> 1985-06-14, or 1985-06-14 04:12.


## Finding days in your photos

A calendar holds appointments; this holds the things you'd otherwise lose. The
best record of those you already have is your photo library — every picture
carries when it was taken and usually where.

**⋯ → Find days in my photos** reads that, and only that. Three fields per
photo: date, coordinate, and whether you hearted it. The pictures themselves
are never decoded, nothing is uploaded, and the scan works in aeroplane mode.

Four signals, because no single one is enough:

| | |
| --- | --- |
| **Away from home** | Photos far from where you usually were *that year*, with consecutive days merged into one trip. The strongest signal, and the only one that can carry a real name — a coordinate reverse-geocodes to "Kanazawa, Japan". |
| **A lot of photos** | Far more than a normal day for you. Catches parties, weddings, births — things photographed heavily while standing still. |
| **Photos you hearted** | Rare and deliberate. You already decided those mattered. |
| **First in a long while** | The first photos after months of quiet, which tends to mark something changing rather than something happening. |

Home is worked out per year, so moving house doesn't turn the rest of your
life into one long holiday — and it's the location where the most *days* were
spent, not the most photos, because three weeks abroad easily out-shoots a
year at home.

Each row carries a few thumbnails — hearted photos first, then spread across
the span. "40 photos, a Tuesday in 2011" is not a memory; four pictures of it
usually are. A segmented control chooses how far down the ranking to read,
because no threshold can tell a wedding from a wet Tuesday and pretending
otherwise is how the first version returned 400 days and told you nothing.

**Nothing is added on its own.** A day with forty photos was a wedding or a
flooded kitchen, and only you know which. Tapping a row opens the ordinary
event editor with the dates, length and category filled in, the whole day's
photos scrolling sideways above the title field, and any one of them a tap
away from full screen. You supply the one thing the phone cannot.

One caveat the app repeats on screen: dates come from the photos, so anything
scanned in later — an old print, a screenshot of something — carries the date
it was scanned, not the day it happened.

## What happens to your data

Updating the app — through TestFlight or the App Store — leaves it alone. iOS
keeps the app's container across updates, so the saved lifeline survives.
Deleting the app removes it; *Offload App* does not.

If the saved file ever fails to read, the app **does not write over it**. It is
moved aside as `dcal-lifeline-unreadable-<date>.json` into the app's Documents
folder, which shows up under *On My iPhone → DCAL* in Files, and the app says
so on launch instead of quietly carrying on with the sample life. Import reads
the store format too, so a rescued file can usually be opened straight back up.

That is worth stating because the first version got it wrong: a failed read
looked exactly like an empty one, and the next save replaced a real life with
a made-up one.

## Not done yet

Reading your real calendar (EventKit) is the obvious next step and the thing
that would make this useful rather than only demonstrable. Also missing:
repeating events, multi-day layout at day scale, iPad, CSV for spreadsheet
editing, and any sync at all.
