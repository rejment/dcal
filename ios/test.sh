#!/bin/sh
# Run the DcalKit test suite on a Mac with only the command line tools.
#
# The CLT ship Testing.framework but SwiftPM does not add its search paths by
# itself (Xcode normally does that), so they are spelled out here. With Xcode
# installed, a plain `swift test` works too.

set -eu
cd "$(dirname "$0")"

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
INTEROP=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

exec swift test \
  -Xswiftc -F"$FRAMEWORKS" \
  -Xlinker -F"$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$INTEROP" \
  "$@"
