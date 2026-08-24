#!/bin/sh
set -eu

remoting_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
production_archive="$remoting_root/lib/libFlyology_Remoting.a"
testing_archive="$remoting_root/lib/test-hooks/libFlyology_Remoting.a"
hook_symbol='compound_test_hooks__raise_if_armed'
disabled_symbol='flyology_remoting_disabled_hook_must_be_elided'
probe_project="$remoting_root/tests/probes/compound_hook_elision_probe.gpr"
probe_unit='compound_hook_elision_probe.adb'
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/flyology-remoting-hook-elision.XXXXXX")

cleanup () {
  rm -rf -- "$temp_root"
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ ! -f "$production_archive" ] || [ ! -f "$testing_archive" ]; then
  printf '%s\n' "hook-elision check requires production and test-hook builds" >&2
  exit 1
fi

production_symbols=$(nm "$production_archive")
testing_symbols=$(nm "$testing_archive")

if printf '%s\n' "$production_symbols" | grep -E "$hook_symbol|$disabled_symbol" >/dev/null; then
  printf '%s\n' "compound test-hook reference survived in the production archive" >&2
  exit 1
fi

if ! printf '%s\n' "$testing_symbols" | grep -F "$hook_symbol" >/dev/null; then
  printf '%s\n' "enabled compound test-hook implementation is absent" >&2
  exit 1
fi

compile_disabled_probe () {
  mode=$1
  shift
  object_dir="$temp_root/$mode"
  alr exec -- gprbuild -c -u -f -p -q \
    -P "$probe_project" \
    -XFLYOLOGY_REMOTING_COMPOUND_TEST_HOOKS=false \
    -XFLYOLOGY_REMOTING_HOOK_PROBE_OBJECT_DIR="$object_dir" \
    "$probe_unit" -cargs:Ada "$@"
  symbols=$(nm -a "$object_dir/compound_hook_elision_probe.o")
  if printf '%s\n' "$symbols" | grep -E \
    'inject_failure|compound_test_hooks__raise_if_armed|flyology_remoting_disabled_hook_must_be_elided' \
    >/dev/null
  then
    printf '%s\n' "compound test hook survived in disabled $mode instantiation" >&2
    exit 1
  fi
}

compile_enabled_probe () {
  mode=$1
  shift
  object_dir="$temp_root/enabled-$mode"
  alr exec -- gprbuild -c -u -f -p -q \
    -P "$probe_project" \
    -XFLYOLOGY_REMOTING_COMPOUND_TEST_HOOKS=true \
    -XFLYOLOGY_REMOTING_HOOK_PROBE_OBJECT_DIR="$object_dir" \
    "$probe_unit" -cargs:Ada "$@"
  symbols=$(nm -a "$object_dir/compound_hook_elision_probe.o")
  if ! printf '%s\n' "$symbols" | grep -F "$hook_symbol" >/dev/null; then
    printf '%s\n' "compound test hook disappeared from enabled $mode instantiation" >&2
    exit 1
  fi
}

check_selection () {
  external_state=$1
  state=$2
  opposite=$3
  inspection=$(alr exec -- gprinspect \
    -P "$remoting_root/flyology_remoting.gpr" \
    --attributes --display=textual --views=flyology_remoting \
    -XFLYOLOGY_REMOTING_COMPOUND_TEST_HOOKS="$external_state")
  if ! printf '%s\n' "$inspection" | grep -F "/src/test_hooks/compound/$state" >/dev/null; then
    printf '%s\n' "compound $state hook source was not selected" >&2
    exit 1
  fi
  if printf '%s\n' "$inspection" | grep -F "/src/test_hooks/compound/$opposite" >/dev/null; then
    printf '%s\n' "compound $opposite hook source leaked into $state selection" >&2
    exit 1
  fi
}

check_selection false disabled enabled
check_selection true enabled disabled

compile_disabled_probe O0-strict \
  -O0 -fno-inline -fno-inline-functions -fno-tree-dce -fno-dce
compile_enabled_probe O0-strict \
  -O0 -fno-inline -fno-inline-functions -fno-tree-dce -fno-dce
compile_disabled_probe O0 -O0
compile_enabled_probe O0 -O0
compile_disabled_probe Og -Og
compile_enabled_probe Og -Og
compile_disabled_probe O1 -O1
compile_enabled_probe O1 -O1
compile_disabled_probe O2 -O2
compile_enabled_probe O2 -O2
compile_disabled_probe O3 -O3
compile_enabled_probe O3 -O3
compile_disabled_probe Os -Os
compile_enabled_probe Os -Os
compile_disabled_probe Oz -Oz
compile_enabled_probe Oz -Oz
compile_disabled_probe Ofast -Ofast
compile_enabled_probe Ofast -Ofast
