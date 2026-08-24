#!/bin/sh
set -eu

remoting_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

cd "$remoting_root"
alr build
alr exec -- gprbuild -f -p -P tests/flyology_remoting_tests.gpr \
  -XFLYOLOGY_REMOTING_COMPOUND_TEST_HOOKS=true
"$remoting_root/scripts/check-test-hook-elision.sh"
"$remoting_root/bin/tests/compile_smoke"
"$remoting_root/bin/tests/identity_directory_smoke"
"$remoting_root/bin/tests/header_codec_smoke"
"$remoting_root/bin/tests/codec_payload_lease_smoke"
"$remoting_root/bin/tests/codec_transport_smoke"
"$remoting_root/bin/tests/in_process_transport_smoke"
"$remoting_root/bin/tests/in_process_compound_transport_smoke"
"$remoting_root/bin/tests/in_process_node_smoke"
"$remoting_root/bin/tests/task_lifecycle_smoke"
