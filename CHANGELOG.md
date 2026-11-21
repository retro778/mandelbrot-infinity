# Changelog

## 1.0.2 - 2026-11-21

- 32-bit Windows version, cross-built on Linux with the Windows FreeBASIC
  compiler under wine (`scripts/build-win32.sh`, `scripts/package-win32.sh`).
- Platform-neutral paths: settings and bookmarks live in `%APPDATA%` on
  Windows, exports in `%USERPROFILE%\Pictures`.
- Start-up failures are shown in a message box on Windows and logged to
  `log.txt`.

## 1.0.1 - 2026-11-21

Packaging release; the program itself is unchanged.

- `scripts/package.sh` builds a portable tarball and a `.deb` package.
- Desktop entry and application icon.
- Screenshots in the README.

## 1.0.0 - 2026-11-21

First release.

- SDL2 explorer window: resizable, fullscreen, high-DPI aware, dark UI with
  status bar, help overlay, context menu, settings, bookmark and export panels.
- Three renderers: native double, full MPFR reference, and perturbation with
  rebasing, an extended-exponent path beyond 1e300 and optional series
  approximation. Automatic mode selection and manual override.
- Arbitrary-precision view state (centre and scale never pass through a
  DOUBLE); automatic precision with configurable guard bits; explicit
  "precision insufficient" warning.
- Progressive, tiled, multi-threaded rendering with cancellation and
  generation ids; instant pan/zoom preview from the previous frame.
- Smooth colouring relative to the frame's lowest iteration value, eight
  built-in palettes, custom palette files, palette offset / intensity /
  animation.
- Adaptive iteration limit with refinement passes.
- Bookmarks (add, load, rename, delete, export, import) and location presets
  in human-readable files with exact decimal coordinates.
- PNG export at any resolution with supersampling, optional transparent
  interior and a metadata text file; headless `--render` mode.
- Mini-Mandelbrot finder (period detection + Newton's method in MPFR).
- In-app verification of the current frame against the MPFR reference.
- Automated test suite (212 checks) and benchmark program.
