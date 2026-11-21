Custom palettes for Mandelbrot Infinity
=======================================

Every *.pal file in this folder (and in ~/.config/mandelbrot-infinity/palettes)
is loaded at start-up and appended after the eight built-in palettes.

Format (plain text):

    name=My palette
    # position  red green blue      (comments start with # or ;)
    0.00   10   0  40
    0.35  250 120   0
    0.70  255 255 200

* position runs from 0 (inclusive) to 1 (exclusive) and must increase;
* colours are 0..255; values may be separated by blanks, tabs or commas;
* 2 to 64 control points; the gradient is cyclic (the last point blends
  back into the first) and is interpolated with a smooth cubic spline.

A file with errors is skipped and reported on the terminal.
