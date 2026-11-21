#!/bin/sh
# Build if necessary, check the shared libraries, start Mandelbrot Infinity.
cd "$(dirname "$0")/.."
[ -x ./mandelbrot-infinity ] || ./scripts/build.sh || exit 1
missing=$(ldd ./mandelbrot-infinity 2>/dev/null | grep "not found")
if [ -n "$missing" ]; then
    echo "Mandelbrot Infinity cannot start - missing shared libraries:"
    echo "$missing"
    echo "Install them on MX Linux / Debian with:"
    echo "  sudo apt install libsdl2-2.0-0 libsdl2-ttf-2.0-0 libmpfr6 libgmp10 libpng16-16"
    exit 1
fi
exec ./mandelbrot-infinity "$@"
