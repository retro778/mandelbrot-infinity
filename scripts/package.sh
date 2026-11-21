#!/bin/sh
# Build the Linux release packages into dist/:
#   mandelbrot-infinity-<version>-linux-x86_64.tar.gz   (portable, unpack and run)
#   mandelbrot-infinity_<version>_amd64.deb             (MX Linux / Debian / Ubuntu)
set -e
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^const APP_VERSION = "\(.*\)"/\1/p' include/common.bi)
[ -n "$VERSION" ] || { echo "error: cannot read APP_VERSION from include/common.bi"; exit 1; }
./scripts/build.sh
rm -rf dist
mkdir -p dist

# ---- portable tarball -------------------------------------------------------
T=mandelbrot-infinity-$VERSION-linux-x86_64
mkdir -p dist/$T
cp -r mandelbrot-infinity assets data README.md LICENSE THIRD-PARTY.md CHANGELOG.md dist/$T/
cp packaging/mandelbrot-infinity.png packaging/mandelbrot-infinity.desktop dist/$T/
tar -C dist --owner=0 --group=0 -czf dist/$T.tar.gz $T
rm -rf dist/$T

# ---- Debian package ---------------------------------------------------------
if command -v dpkg-deb >/dev/null 2>&1; then
    D=dist/deb
    mkdir -p $D/DEBIAN $D/opt/mandelbrot-infinity $D/usr/bin \
             $D/usr/share/applications $D/usr/share/icons/hicolor/256x256/apps \
             $D/usr/share/doc/mandelbrot-infinity
    cp -r mandelbrot-infinity assets data $D/opt/mandelbrot-infinity/
    printf '#!/bin/sh\nexec /opt/mandelbrot-infinity/mandelbrot-infinity "$@"\n' > $D/usr/bin/mandelbrot-infinity
    chmod 755 $D/usr/bin/mandelbrot-infinity $D/opt/mandelbrot-infinity/mandelbrot-infinity
    cp packaging/mandelbrot-infinity.desktop $D/usr/share/applications/
    cp packaging/mandelbrot-infinity.png $D/usr/share/icons/hicolor/256x256/apps/
    cp README.md THIRD-PARTY.md CHANGELOG.md $D/usr/share/doc/mandelbrot-infinity/
    cp LICENSE $D/usr/share/doc/mandelbrot-infinity/copyright
    SIZE=$(du -sk $D | cut -f1)
    cat > $D/DEBIAN/control <<CTRL
Package: mandelbrot-infinity
Version: $VERSION
Section: science
Priority: optional
Architecture: amd64
Depends: libc6 (>= 2.38), libsdl2-2.0-0, libsdl2-ttf-2.0-0, libmpfr6, libgmp10, libpng16-16t64 | libpng16-16, zlib1g, libtinfo6
Installed-Size: $SIZE
Maintainer: retro778 <332065915+retro778@users.noreply.github.com>
Homepage: https://github.com/retro778/mandelbrot-infinity
Description: Deep zoom Mandelbrot set explorer
 Interactive Mandelbrot explorer written in FreeBASIC with double, MPFR
 arbitrary-precision and perturbation renderers, bookmarks, palettes and
 PNG export.
CTRL
    find $D -type d -exec chmod 755 {} +
    find $D -type f -exec chmod go-w {} +
    if command -v fakeroot >/dev/null 2>&1; then
        fakeroot dpkg-deb --build $D dist/mandelbrot-infinity_${VERSION}_amd64.deb >/dev/null
    else
        dpkg-deb --root-owner-group --build $D dist/mandelbrot-infinity_${VERSION}_amd64.deb >/dev/null
    fi
    rm -rf $D
else
    echo "note: dpkg-deb not found, skipping the .deb"
fi

(cd dist && sha256sum * > SHA256SUMS)
ls -l dist
