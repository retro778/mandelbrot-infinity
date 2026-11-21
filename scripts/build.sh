#!/bin/sh
# Build Mandelbrot Infinity (native Linux x86_64, FreeBASIC)
set -e
cd "$(dirname "$0")/.."
FBC="${FBC:-fbc}"
command -v "$FBC" >/dev/null 2>&1 || { echo "error: FreeBASIC compiler '$FBC' not found (set FBC=/path/to/fbc)"; exit 1; }
missing=""
for lib in SDL2 SDL2_ttf mpfr gmp png z; do
    found=0
    for d in /usr/lib/x86_64-linux-gnu /usr/lib /usr/lib64 /usr/local/lib; do
        [ -e "$d/lib$lib.so" ] && found=1
    done
    [ $found -eq 1 ] || missing="$missing $lib"
done
if [ -n "$missing" ]; then
    echo "error: missing development libraries:$missing"
    echo "install them on MX Linux / Debian with:"
    echo "  sudo apt install libsdl2-dev libsdl2-ttf-dev libmpfr-dev libgmp-dev libpng-dev zlib1g-dev"
    exit 1
fi
OPT="${OPT:--gen gcc -O 3}"
echo "compiling mandelbrot-infinity ..."
"$FBC" $OPT -mt -w all -i include -i src src/main.bas -x mandelbrot-infinity
echo "done: ./mandelbrot-infinity"
