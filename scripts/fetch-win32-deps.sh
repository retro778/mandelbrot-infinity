#!/bin/sh
# Download the 32-bit Windows libraries needed to build the win32 version
# into win32/deps/ (nothing is installed system-wide).
#   SDL2, SDL2_ttf          official MinGW development packages (libsdl.org)
#   GMP, MPFR, libpng, zlib MSYS2 mingw32 packages, plus their runtime DLLs
set -e
cd "$(dirname "$0")/.."
D=win32/deps
mkdir -p $D/dl $D/lib $D/bin $D/licenses
M=https://repo.msys2.org/mingw/mingw32
fetch() { [ -s "$D/dl/$(basename "$1")" ] || curl -fsL --retry 3 -o "$D/dl/$(basename "$1")" "$1"; }
fetch https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-devel-2.32.10-mingw.tar.gz
fetch https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.24.0/SDL2_ttf-devel-2.24.0-mingw.tar.gz
for p in gmp-6.3.0-2 mpfr-4.2.2-3 libpng-1.6.59-2 zlib-1.4-2 libgcc-16.2.0-7 \
         libwinpthread-14.0.0.r598.ge3d18511f-1; do
    fetch $M/mingw-w64-i686-$p-any.pkg.tar.zst
done
rm -rf $D/x && mkdir -p $D/x
for f in $D/dl/*.tar.gz; do tar -C $D/x -xzf "$f"; done
for f in $D/dl/*.pkg.tar.zst; do tar -C $D/x --zstd -xf "$f" mingw32; done
# import libraries
cp $D/x/SDL2-*/i686-w64-mingw32/lib/libSDL2.dll.a $D/x/SDL2-*/i686-w64-mingw32/lib/libSDL2main.a $D/lib/
cp $D/x/SDL2_ttf-*/i686-w64-mingw32/lib/libSDL2_ttf.dll.a $D/lib/
cp $D/x/mingw32/lib/libgmp.dll.a $D/x/mingw32/lib/libmpfr.dll.a $D/lib/
cp $D/x/mingw32/lib/libpng16.dll.a $D/lib/libpng.dll.a
cp $D/x/mingw32/lib/libz.dll.a $D/lib/
# runtime DLLs shipped next to the executable
cp $D/x/SDL2-*/i686-w64-mingw32/bin/SDL2.dll $D/x/SDL2_ttf-*/i686-w64-mingw32/bin/SDL2_ttf.dll $D/bin/
for d in libgmp-10.dll libmpfr-6.dll libpng16-16.dll zlib1.dll libgcc_s_dw2-1.dll libwinpthread-1.dll; do
    cp $D/x/mingw32/bin/$d $D/bin/
done
# licence texts
cp $D/x/SDL2-*/i686-w64-mingw32/share/licenses/SDL2/* $D/licenses/ 2>/dev/null || cp $D/x/SDL2-*/LICENSE.txt $D/licenses/SDL2-LICENSE.txt
ls $D/x/SDL2_ttf-*/ | head -20 >/dev/null
find $D/x/SDL2_ttf-* -maxdepth 4 -iname "LICENSE*" -exec sh -c 'cp "$1" "'$D'/licenses/SDL2_ttf-$(basename "$1")"' _ {} \;
for p in gmp mpfr libpng zlib libgcc gcc-libs libwinpthread; do
    [ -d $D/x/mingw32/share/licenses/$p ] && mkdir -p $D/licenses/$p && cp -r $D/x/mingw32/share/licenses/$p/. $D/licenses/$p/
done
rm -rf $D/x
echo "win32 dependencies ready in $D"
ls $D/lib $D/bin
