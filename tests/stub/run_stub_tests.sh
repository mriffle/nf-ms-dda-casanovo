#!/usr/bin/env bash
#
# Self-contained stub tests for the nf-ms-dda-casanovo workflow.
#
# Runs `nextflow run ... -stub-run` across a matrix of input permutations, under
# each supported Nextflow version, to catch wiring bugs (e.g. the Panorama-mzML
# channel-vs-Path bug in workflows/casanovo.nf) and version-compatibility breaks.
# Every process must declare a working `stub:` block for this to pass; missing
# outputs in a stub are caught by Nextflow as process failures.
#
# SELF-CONTAINED: the script downloads the Nextflow launcher and each pinned
# framework version into tests/stub/.nextflow-dist/ (an isolated NXF_HOME) on
# first run. Nothing is installed system-wide and ~/.nextflow is never touched,
# so the suite runs identically on any machine with bash + curl/wget + Java 17+.
#
# Requirements: bash, curl or wget, and Java 17+ on PATH. Network access is
# needed the first time (to fetch the launcher, framework jars, and plugins);
# subsequent runs are offline-cached under .nextflow-dist/.
#
# Usage:
#   tests/stub/run_stub_tests.sh                 # all tests, all versions
#   tests/stub/run_stub_tests.sh -v              # show nextflow output on failure
#   tests/stub/run_stub_tests.sh -k foo          # only tests whose name matches "foo"
#   tests/stub/run_stub_tests.sh -V 26           # only Nextflow versions matching "26"
#   NXF_VERSIONS="25.04.8 26.04.3" tests/stub/run_stub_tests.sh   # override versions
#
# Exits non-zero if any test fails.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
WORK_BASE="$SCRIPT_DIR/.work"
STUB_CONFIG="$SCRIPT_DIR/stub.config"

# --- Self-contained Nextflow distribution -----------------------------------
# Launcher, framework jars and plugins all live here (gitignored). Delete this
# directory to force a clean re-download.
DIST_DIR="$SCRIPT_DIR/.nextflow-dist"
LAUNCHER="$DIST_DIR/nextflow"
export NXF_HOME="$DIST_DIR/home"

# Nextflow versions under test: the supported floor (the Nextflow 25 line, which
# matches the manifest `nextflowVersion` in nextflow.config) and the current
# Nextflow 26 target. Keep the lowest entry in sync with the manifest floor.
# Override at runtime with e.g. NXF_VERSIONS="25.10.5 26.04.3".
DEFAULT_VERSIONS="25.04.8 26.04.3"
read -r -a NXF_VERSIONS <<< "${NXF_VERSIONS:-$DEFAULT_VERSIONS}"

VERBOSE=0
FILTER=""
VER_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        -k|--filter)  FILTER="$2"; shift 2 ;;
        -V|--version-filter) VER_FILTER="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,32p' "$0"
            exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# --- Prerequisites -----------------------------------------------------------
command -v java >/dev/null || { echo "Java 17+ is required but not found on PATH" >&2; exit 2; }

ensure_launcher() {
    if [[ -x "$LAUNCHER" ]]; then return; fi
    mkdir -p "$DIST_DIR"
    echo "Downloading the Nextflow launcher into $DIST_DIR ..."
    if command -v curl >/dev/null; then
        curl -fsSL https://get.nextflow.io -o "$LAUNCHER" || { echo "launcher download failed" >&2; exit 2; }
    elif command -v wget >/dev/null; then
        wget -qO "$LAUNCHER" https://get.nextflow.io || { echo "launcher download failed" >&2; exit 2; }
    else
        echo "need 'curl' or 'wget' to download the Nextflow launcher" >&2; exit 2
    fi
    chmod +x "$LAUNCHER"
}

# --- Fixtures ----------------------------------------------------------------
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

# --- Runner ------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
SUITE_IDX=0
declare -a FAILED_TESTS=()

run_test() {
    local ver="$1"; local name="$2"; shift 2
    local args=("$@")

    if [[ -n "$FILTER" && "$name" != *"$FILTER"* ]]; then
        return
    fi

    SUITE_IDX=$((SUITE_IDX + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    local slug
    slug=$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_' | tr -s '_')
    local work_dir="$WORK_BASE/$ver/${SUITE_IDX}_${slug}"
    mkdir -p "$work_dir"
    local log="$work_dir/run.log"

    printf '  [%02d] %-58s ' "$SUITE_IDX" "$name"

    if ( cd "$work_dir" && NXF_VER="$ver" "$LAUNCHER" \
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
        FAILED_TESTS+=("[nf-$ver] $name  ($log)")
        if [[ $VERBOSE -eq 1 ]]; then
            echo "       ---- last 40 lines of $log ----"
            tail -n 40 "$log" | sed 's/^/       /'
            echo "       --------------------------------"
        fi
    fi
}

# The full permutation matrix, run once per Nextflow version.
suite() {
    local ver="$1"
    SUITE_IDX=0

    # --- Local-spectra tests ---
    run_test "$ver" "local .raw, no limelight" \
        --spectra_file      "$FIXTURES_DIR/dummy.raw" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    run_test "$ver" "local .mzML, no limelight" \
        --spectra_file      "$FIXTURES_DIR/dummy.mzML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    run_test "$ver" "local .mzXML, no limelight" \
        --spectra_file      "$FIXTURES_DIR/dummy.mzXML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    # --- Panorama-spectra tests (stub mode, URLs never fetched) ---
    run_test "$ver" "panorama .raw, no limelight" \
        --spectra_file      "$PAN_RAW" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    # REGRESSION: Panorama-hosted mzML is the path that crashed with
    # `Channel.fromPath` before the fix in workflows/casanovo.nf.
    run_test "$ver" "panorama .mzML, no limelight (regression)" \
        --spectra_file      "$PAN_MZML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    run_test "$ver" "panorama .mzXML, no limelight" \
        --spectra_file      "$PAN_MZXML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    # --- Panorama weights / params routing ---
    run_test "$ver" "local .raw, panorama weights" \
        --spectra_file      "$FIXTURES_DIR/dummy.raw" \
        --casanovo_weights  "$PAN_WEIGHTS" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml"

    run_test "$ver" "local .raw, panorama params" \
        --spectra_file      "$FIXTURES_DIR/dummy.raw" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$PAN_PARAMS"

    # --- Limelight upload branch ---
    run_test "$ver" "local .raw + limelight upload" \
        --spectra_file      "$FIXTURES_DIR/dummy.raw" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
        "${LIMELIGHT_ARGS[@]}"

    run_test "$ver" "local .mzML + limelight upload" \
        --spectra_file      "$FIXTURES_DIR/dummy.mzML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
        "${LIMELIGHT_ARGS[@]}"

    run_test "$ver" "panorama .mzML + limelight upload (regression)" \
        --spectra_file      "$PAN_MZML" \
        --casanovo_weights  "$FIXTURES_DIR/dummy_weights.ckpt" \
        --casanovo_params   "$FIXTURES_DIR/dummy_casanovo.yaml" \
        "${LIMELIGHT_ARGS[@]}"

    run_test "$ver" "all panorama + limelight" \
        --spectra_file      "$PAN_MZML" \
        --casanovo_weights  "$PAN_WEIGHTS" \
        --casanovo_params   "$PAN_PARAMS" \
        "${LIMELIGHT_ARGS[@]}"
}

# --- Reset prior work (keep the downloaded distribution) --------------------
rm -rf "$WORK_BASE"
mkdir -p "$WORK_BASE"

ensure_launcher

echo "nf-ms-dda-casanovo stub tests"
echo "  repo:     $REPO_ROOT"
echo "  fixtures: $FIXTURES_DIR"
echo "  nxf dist: $DIST_DIR"
echo "  work:     $WORK_BASE"
echo "  versions: ${NXF_VERSIONS[*]}"
[[ -n "$FILTER" ]]     && echo "  filter:   $FILTER"
[[ -n "$VER_FILTER" ]] && echo "  ver match: $VER_FILTER"
echo ""

# --- Prefetch + run each version --------------------------------------------
ANY_VERSION_RAN=0
for ver in "${NXF_VERSIONS[@]}"; do
    if [[ -n "$VER_FILTER" && "$ver" != *"$VER_FILTER"* ]]; then
        continue
    fi
    ANY_VERSION_RAN=1
    echo "===== Nextflow $ver ====="
    if ! NXF_VER="$ver" "$LAUNCHER" -version >/dev/null 2>&1; then
        echo "  ERROR: could not download/run Nextflow $ver — marking its tests failed" >&2
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("[nf-$ver] could not fetch this Nextflow version")
        echo ""
        continue
    fi
    suite "$ver"
    echo ""
done

if [[ $ANY_VERSION_RAN -eq 0 ]]; then
    echo "No versions matched '$VER_FILTER' (available: ${NXF_VERSIONS[*]})" >&2
    exit 2
fi

# --- Summary ----------------------------------------------------------------
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
