# DCAL for iOS

Native SwiftUI. Not a webview — the timeline is redrawn in a `Canvas`, and the
gestures are UIKit recognisers, so a pinch tracks at the screen's own refresh
rate and a fling decelerates like every other list on the phone.

## Structure

| | |
| --- | --- |
| `DcalKit/` | The model and every layout decision. Pure Foundation and CoreGraphics, no UI. |
| `DcalUI/` | The whole interface in SwiftUI. |
| `Dcal/` | The app target — a ten-line shell plus the icon. |
| `project.yml` | XcodeGen manifest that generates the Xcode project. |
| `test.sh` | Runs the suite without Xcode. |

The split is what makes the app testable at all. `TimelineLayout` turns a zoom
level and a list of events into the rectangles, ticks, notches and labels for
one frame — and stops there. `TimelineCanvas` paints exactly what it is given
and decides nothing, and a tap is resolved against the very same rectangles
that were drawn rather than a second guess at where they landed.

## Testing without Xcode

```sh
./test.sh
```

Compiles and tests on a Mac with only the command line tools — the SwiftUI
code is type-checked too (`swift build`), because the UI target builds for
macOS with the UIKit pieces behind `#if os(iOS)`.

The 39 tests cover the parts that are wrong in ways a screenshot would not
show:

- calendar boundaries, including the 23-hour and 25-hour days when the clocks
  change, and the hour ruler skipping an 02:00 that never happened
- the ruler choosing a unit you can read, and never jumping backwards down the
  ladder as you zoom in
- pinch keeping the instant under your fingers fixed, at any anchor and any
  factor, and stopping at two hours and at 140 years
- lane packing per cluster: a busy Tuesday morning must not narrow a lone
  Friday afternoon
- which labels survive at which zoom, and that a heavier one drops a lighter
  neighbour rather than nudging it to a moment it does not belong to
- the palette handing over from hours to seasons to decades without a gap
- age counting birthdays rather than years

## On your iPhone

Signing is Automatic, so with Xcode installed:

1. `cd ios && xcodegen generate`
2. `open Dcal.xcodeproj`
3. Target **Dcal** → *Signing & Capabilities* → pick your team.
4. Plug the phone in, select it, **⌘R**.
5. On the phone: *Settings → Privacy & Security → Developer Mode* on (needs a
   restart), and trust the certificate under *General → VPN & Device
   Management* if asked.

## To TestFlight, without Xcode at all

`.github/workflows/testflight.yml` archives, signs and uploads from a GitHub
macOS runner. Signing uses an App Store Connect API key, so no certificate or
`.p12` ever goes near the repo. Four repository secrets and one app record set
it up — the workflow's own header lists them step by step.

Prepared in advance: bundle id `com.rejment.dcal`, version 1.0, the 1024 icon,
and the export compliance question answered in `Info.plist` (standard TLS
only), so uploads do not stop to ask.

The Release configuration signs with `Apple Distribution` rather than letting
automatic signing pick a development certificate and swap it at export. On a
CI runner — a clean machine with an empty keychain — that swap minted a new
Apple Development certificate through the API on *every single build*, and
fifteen of those is Apple's ceiling for an account, after which it refuses to
issue any more and the archive fails. Cloud-managed distribution certificates
are not per-machine, so nothing accumulates. Debug is untouched, which is what
a local ⌘R onto a cabled phone needs.

If it ever does hit the ceiling, the certificates named "Apple Development:
Created via API" are disposable — revoke them at developer.apple.com and the
next build mints what it needs.

## What is not verified here

There is no Xcode on the machine this was written on, so the package, its
tests and the generated project are what has been checked. The app target has
never been launched: how the views behave at runtime, how the gestures feel,
and whether the frame rate holds during a pinch across a whole life are all
unproven until it runs on a device. The first run is the review.
