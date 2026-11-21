#!/bin/sh
# Build the 32-bit Windows release into dist/:
#   mandelbrot-infinity-<version>-win32.zip
# (run scripts/package.sh first if you also want the Linux packages:
#  that script empties dist/, this one only adds to it)
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^const APP_VERSION = "\(.*\)"/\1/p' include/common.bi)
./scripts/build-win32.sh
Z=mandelbrot-infinity-$VERSION-win32
mkdir -p dist
rm -rf dist/$Z dist/$Z.zip
cp -r win32/build dist/$Z
rm -rf dist/$Z/tests
cp README.md LICENSE THIRD-PARTY.md CHANGELOG.md dist/$Z/
# licences of the bundled DLLs
mkdir -p dist/$Z/licenses
cp -r win32/deps/licenses/. dist/$Z/licenses/
for f in LGPL-3 GPL-3 GPL-2; do
    [ -f /usr/share/common-licenses/$f ] && cp /usr/share/common-licenses/$f dist/$Z/licenses/GNU-$f.txt
done
cat > dist/$Z/licenses/README.txt <<TXT
Licences of the libraries shipped as DLLs with the Windows version:

  SDL2.dll, SDL2_ttf.dll          zlib licence (SDL2_ttf includes FreeType and HarfBuzz)
  libgmp-10.dll                   GNU LGPL 3+ or GPL 2+   (GNU-LGPL-3.txt, GNU-GPL-2.txt)
  libmpfr-6.dll                   GNU LGPL 3+             (GNU-LGPL-3.txt, GNU-GPL-3.txt)
  libpng16-16.dll                 PNG Reference Library License   (libpng/)
  zlib1.dll                       zlib licence                    (zlib/)
  libgcc_s_dw2-1.dll              GPL 3 with GCC Runtime Library Exception (libgcc/)
  libwinpthread-1.dll             MIT / BSD (mingw-w64 winpthreads)        (libwinpthread/)

The GMP, MPFR, libpng, zlib and runtime DLLs are unmodified binaries from the
MSYS2 project (https://www.msys2.org, mingw32 repository), where their
source packages are also available.  SDL2 and SDL2_ttf are the official
builds from https://github.com/libsdl-org.  Because they are separate DLLs
you can replace any of them with your own build.
TXT
(cd dist && zip -qr $Z.zip $Z && rm -rf $Z && rm -f SHA256SUMS && sha256sum * > SHA256SUMS)
ls -l dist
