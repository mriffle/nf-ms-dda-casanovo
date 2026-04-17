#!/usr/bin/env bash
#
# Stub tests for the nf-ms-dda-casanovo workflow.
#
# Runs `nextflow run ... -stub-run` across a matrix of input permutations to
# catch wiring bugs (e.g. the Panorama-mzML channel-vs-Path bug in
# workflows/casanovo.nf). Every process must declare a working `stub:` block
# for this to pass; missing outputs in a stub are caught by Nextflow as
# process failures.
#
# Usage:
#   tests/stub/run_stub_tests.sh           # run all
#   tests/stub/run_stub_tests.sh -v        # show nextflow output on failure
#   tests/stub/run_stub_tests.sh -k foo    # run only tests whose name matches
#
# Exits non-zero if any test fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
WORK_BASE="$SCRIPT_DIR/.work"
STUB_CONFIG="$SCRIPT_DIR/stub.config"

VERBOSE=0
FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        -k|--filter)  FILTER="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,18p' "$0"
            exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v nextflow >/dev/null || { echo "nextflow not on PATH" >&2; exit 2; }

# --- Fixtures ---------------------------------------------------------------
mkdir -p "$FIXTURES_DIR"
touch "$FIXTURES_DIR/dummy.raw"
touch "$FIXTURES_DIR/dummy.mzML"
touch "$FIXTURES_DIR/dummy.mzXML"
touch "$FIXTURES_DIR/dummy_weights.ckpt"
touch "$FIXTURES_DIR/dummy_casanovo.yaml"

# Fake Panorama URLs — stub processes never touch the network.
PAN_RAW="https://panoramaweb.org/_webdav/stub/@files/dummy.raw"
PAN_MZML="https://panoramaweb.org/_webdav/stub/@files/dummy.mzML"
PAN_MZXML="https://panoramaweb.org/_webdav/stub/@files/dummy.mzXML"
PAN_WEIGHTS="https://panoramaweb.org/_webdav/stub/@files/dummy_weights.ckpt"
PAN_PARAMS="https://panoramaweb.org/_webdav/stub/@files/dummy_casanovo.yaml"

# Placeholder Limelight params — passed when `--limelight_upload true`.
LIMELIGHT_ARGS=(
    --limelight_upload true
    --limelight_webapp_url "https://limelight.example.com/limelight"
    --limelight_project_id 999
    --limelight_search_description "stub test"
    --limelight_search_short_name "stub"
    --limelight_tags "stub,test"
)

# --- Runner -----------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

run_test() {
    local name="$1"; shift
    local args=("$@")

    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
        return
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    local slug
    slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_' | tr -s '_')
    local work_dir="$WORK_BASE/${TESTS_RUN}_${slug}"
    mkdir -p "$work_dir"
    local log="$work_dir/run.log"

    printf '[%02d] %-60s ' "$TESTS_RUN" "$name"

    if ( cd "$work_dir" && nextflow \
            -log "$work_dir/nextflow.log" \
            run "$REPO_ROOT/main.nf" \
            -stub-run \
            -profile standard \
            -c "$STUB_CONFIG" \
            -work-dir "$work_dir/work" \
            "${args[@]}" \
            --mzml_cache_directory     "$work_dir/mzml_cache" \
            --panorama_cache_directory "$work_dir/panorama_cache" \
            --result_dir               "$work_dir/results" \
            --report_dir               "$work_dir/reports" \
            > "$log" 2>&1 ); then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$name  ($log)")
        if [[ $VERBOSE -eq 1 ]]; then
            echo "---- last 40 lines of $log ----"
            tail -n 40 "$log" | sed 's/^/     /'
            echo "--------------------------------"
        fi
    fi
}

# --- Reset prior work -------------------------------------------------------
rm -rf "$WORK_BASE"
mkdir -p "$WORK_BASE"

echo "nf-ms-dda-casanovo stub tests"
echo "  repo:     $REPO_ROOT"
echo "  fixtures: $FIXTURES_DIR"
echo "  work:     $WORK_BASE"
[[ -n "$FILTER" ]] && echo "  filter:   $FILTER"
echo ""

# --- Local-spectra tests ---------------------------------------------------

run_test "local .raw, no limelight" \
    --spectra_file      "$FIXTURES_DIR/dummy.raw" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

run_test "local .mzML, no limelight" \
    --spectra_file      "$FIXTURES_DIR/dummy.mzML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

run_test "local .mzXML, no limelight" \
    --spectra_file      "$FIXTURES_DIR/dummy.mzXML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

# --- Panorama-spectra tests (stub mode, URLs never fetched) ----------------

run_test "panorama .raw, no limelight" \
    --spectra_file      "$PAN_RAW" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

# REGRESSION: Panorama-hosted mzML is the path that crashed with
# `Channel.fromPath` before the fix in workflows/casanovo.nf.
run_test "panorama .mzML, no limelight (regression)" \
    --spectra_file      "$PAN_MZML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

run_test "panorama .mzXML, no limelight" \
    --spectra_file      "$PAN_MZXML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

# --- Panorama weights / params routing -------------------------------------

run_test "local .raw, panorama weights" \
    --spectra_file      "$FIXTURES_DIR/dummy.raw" \
    --casanovo_weights  "$PAN_WEIGHTS" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

run_test "local .raw, panorama params" \
    --spectra_file      "$FIXTURES_DIR/dummy.raw" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$PAN_PARAMS"

# --- Limelight upload branch -----------------------------------------------

run_test "local .raw + limelight upload" \
    --spectra_file      "$FIXTURES_DIR/dummy.raw" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
    "${LIMELIGHT_ARGS[@]}"

run_test "local .mzML + limelight upload" \
    --spectra_file      "$FIXTURES_DIR/dummy.mzML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
    "${LIMELIGHT_ARGS[@]}"

run_test "panorama .mzML + limelight upload (regression)" \
    --spectra_file      "$PAN_MZML" \
    --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
    --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
    "${LIMELIGHT_ARGS[@]}"

run_test "all panorama + limelight" \
    --spectra_file      "$PAN_MZML" \
    --casanovo_weights  "$PAN_WEIGHTS" \
    --casanovo_params   "$PAN_PARAMS" \
    "${LIMELIGHT_ARGS[@]}"

# --- Summary ----------------------------------------------------------------
echo ""
echo "=============================================================="
echo " $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "=============================================================="
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo ""
    echo "FAILED:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    echo ""
    echo "Re-run with -v to see failure output, or inspect the logs directly."
    exit 1
fi

exit 0
