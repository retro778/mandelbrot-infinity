# Third-party components

The MIT License in `LICENSE` covers only the original Mandelbrot Infinity
source code, scripts, palettes and data files. The program links dynamically
against the libraries below, which keep their own licences. None of them is
bundled in this repository; they are installed through the system package
manager.

| Component | Used for | Licence |
|---|---|---|
| FreeBASIC runtime (libfb / libfbmt) | language runtime, linked statically | LGPL 2.1+ with a static-linking exception |
| SDL2 | window, input, rendering | zlib licence |
| SDL2_ttf (and FreeType) | text rendering | zlib licence (FreeType: FTL or GPLv2) |
| GNU MPFR | arbitrary-precision floating point | LGPL 3+ |
| GNU GMP | big integers underneath MPFR | LGPL 3+ or GPL 2+ |
| libpng | PNG export | PNG Reference Library License v2 |
| zlib | compression for libpng | zlib licence |

Bundled asset:

| Asset | Licence |
|---|---|
| `assets/fonts/DejaVuSansMono.ttf` | Bitstream Vera / DejaVu fonts licence (free to use, copy and redistribute) - see `assets/fonts/DejaVu-LICENSE.txt` |

MPFR and GMP are LGPL libraries: because they are linked dynamically, users
can replace them with their own builds, which satisfies the LGPL for binary
distributions (for example on itch.io). If you ever ship the shared
libraries next to the executable, include their licence texts and offer the
corresponding source code.

## Windows package

The Windows zip ships these libraries as separate, unmodified DLLs: SDL2 and
SDL2_ttf (official builds; SDL2_ttf contains FreeType and HarfBuzz), and
GMP, MPFR, libpng, zlib, `libgcc_s_dw2-1.dll` and `libwinpthread-1.dll` from
the MSYS2 mingw32 repository, where the matching source packages are
published. Their licence texts are in the `licenses/` folder of the zip.

`include/mpfr_bindings.bi` is an original FreeBASIC translation of the
function prototypes this program needs from `mpfr.h`.
