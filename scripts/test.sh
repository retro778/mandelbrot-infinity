#!/bin/sh
# Build and run the automated test suite (headless).
set -e
cd "$(dirname "$0")/.."
FBC="${FBC:-fbc}"
"$FBC" -gen gcc -O 3 -mt -i include -i src tests/test_main.bas -x tests/test_main
MI_TEST_TMP="${MI_TEST_TMP:-$(mktemp -d)}" ./tests/test_main
