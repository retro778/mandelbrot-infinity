#!/bin/sh
# Cross-build the 32-bit Windows version on Linux.
# Needs: wine (with 32-bit support) and the Windows FreeBASIC package
#        (FreeBASIC-1.10.1-winlibs-gcc-9.3.0); set FBWIN to its folder.
# Output: win32/build/  (two executables plus the runtime DLLs, assets, data)
set -e
cd "$(dirname "$0")/.."
FBWIN="${FBWIN:-$HOME/freebasic/FreeBASIC-1.10.1-winlibs-gcc-9.3.0}"
[ -f "$FBWIN/fbc32.exe" ] || { echo "error: fbc32.exe not found in $FBWIN (set FBWIN=/path/to/FreeBASIC-win)"; exit 1; }
command -v wine >/dev/null 2>&1 || { echo "error: wine is required to run the Windows compiler"; exit 1; }
[ -f win32/deps/lib/libmpfr.dll.a ] || ./scripts/fetch-win32-deps.sh
export WINEPREFIX="${WINEPREFIX:-$PWD/win32/wineprefix}"
export WINEDEBUG=-all
OUT=win32/build
rm -rf $OUT
mkdir -p $OUT
OPT="-gen gcc -O 3 -fpu sse -mt -w all -i include -i src -p win32/deps/lib"
echo "compiling mandelbrot-infinity.exe (GUI) ..."
wine "$FBWIN/fbc32.exe" $OPT -s gui src/main.bas -x $OUT/mandelbrot-infinity.exe
echo "compiling mandelbrot-infinity-cli.exe (console, for --render and --help) ..."
wine "$FBWIN/fbc32.exe" $OPT -s console src/main.bas -x $OUT/mandelbrot-infinity-cli.exe
cp win32/deps/bin/*.dll $OUT/
cp -r assets data $OUT/
echo "done: $OUT"
ls $OUT
