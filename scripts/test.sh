#!/bin/sh
set -eu

remoting_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$remoting_root"
alr build
alr exec -- gprbuild -f -p -P tests/flyology_remoting_tests.gpr
"$remoting_root/bin/tests/compile_smoke"
