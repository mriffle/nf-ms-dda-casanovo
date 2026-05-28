# nf-ms-dda-casanovo

Nextflow DSL2 pipeline for de novo peptide identification from DDA mass spec data using Casanovo. Requires Nextflow >= 25.04.0 (manifest floor); tested against the Nextflow 25 and 26 lines. The config and scripts are written for Nextflow 26's strict parser (the runtime default in 26.x), which is also accepted by the legacy parser in 25.x — see the Nextflow 26 compatibility notes under Conventions.

## Pipeline Flow

Entry: `main.nf` → `workflows/casanovo.nf`.

1. **Input resolution (`main.nf`)** — resolves three inputs:
   - `params.spectra_file` (.raw / .mzML / .mzXML)
   - `params.casanovo_params` (YAML config)
   - `params.casanovo_weights` (.ckpt)

   Paths starting with `https://` are treated as PanoramaWeb WebDAV URLs and fetched via `PANORAMA_GET_*` (`modules/panorama.nf`). **Exception:** for `casanovo_weights`, GitHub URLs (`https://*github.com*`) are passed straight to `file()` — Nextflow stages the remote ckpt directly. Only non-GitHub HTTPS weights go through Panorama. The commented-out block in `main.nf:46-54` is an older GH-download path via `modules/gh_download.nf` — keep it commented unless intentionally reviving.

2. **MSCONVERT** (`modules/msconvert.nf`) — only runs if input is `.raw`. Uses ProteoWizard + wine. Output is cached via `storeDir = params.mzml_cache_directory` so repeated runs skip conversion.

3. **CASANOVO** (`modules/casanovo.nf`) — runs `casanovo sequence` → `results.mztab` + `results.log`. Container options are built dynamically:
   - Docker: `--shm-size 1g`, `--gpus all` when `use_gpus`
   - Singularity/Apptainer: `--nv` when `use_gpus` (no `--shm-size` — intentionally removed, see commit `801aa9d`)
   - `-e CUDA_LAUNCH_BLOCKING=1` added when `params.cuda_launch_blocking`
   - `maxForks params.use_gpus ? 1 : null` caps concurrency at 1 on GPUs ("don't melt the GPU"), no limit otherwise. Written as a **directive in the process body** (not a config `withName` selector): it must be evaluated *after* the full config merge so `--use_gpus` / `-c` overrides are honored — a config-selector ternary resolves at parse time against the default and silently ignores overrides. Directives take no `=` and no `if` under the strict parser, hence the ternary form.

4. **Optional Limelight upload** (gated on `params.limelight_upload`):
   - `CONVERT_TO_LIMELIGHT_XML` (`modules/limelight_xml_convert.nf`) — `casanovoToLimelightXML.jar` turns mzTab into Limelight XML.
   - `UPLOAD_TO_LIMELIGHT` (`modules/limelight_upload.nf`) — `limelightSubmitImport.jar` posts XML + scan files + the pipeline config to a Limelight webapp.

## Config Layout

- **`nextflow.config`** — params defaults (including resource ceilings `max_cpus`/`max_memory`/`max_time`), AWS Batch settings (us-west-2, `nextflow_basic_ec2` queue, INTELLIGENT_TIERING), and profiles: `standard` (local, 12GB/8cpu), `aws` (awsbatch, 124GB/32cpu, s3:// cache dirs), `slurm` (12GB/8cpu) — each profile overrides the `max_*` ceilings. Secrets `LIMELIGHT_SUBMIT_UPLOAD_KEY` and `PANORAMA_API_KEY` are loaded from Nextflow secrets into `env.*` at config time via bare `env.X = nextflow.secret.SecretsLoader.instance.load().getSecret(...)?.value` assignments — deliberate because AWS Batch can't consume Nextflow secrets directly, and bare (no `def`/`if`) because the strict parser requires it; `?.value` yields null when unset.
- **`conf/base.config`** — nf-core-style resource labels (`process_low`, `process_medium`, `process_high`, `process_*_constant`, `process_long`, `process_very_long_constant`, `process_high_memory`, `error_retry`, `error_ignore`). Retry-on-OOM exit codes: `[143,137,104,134,139,5,6,null]`, `maxRetries = 3`. Resource requests are clamped by `process.resourceLimits = [cpus, memory, time]` (driven by `params.max_*` from the active profile) — the Nextflow 26-compatible replacement for the old `check_max()` helper (functions in config are rejected by the strict parser). The stub harness overrides `resourceLimits` directly in `tests/stub/stub.config` so its tiny CI ceilings win regardless of profile.
- **`container_images.config`** — single source of truth for container image tags. Bump versions here, not inside modules.
- **`resources/casanovo.yaml`** — default Casanovo inference config shipped with the repo.
- **`resources/pipeline.config`** — user-facing template shown in docs; not loaded by the pipeline itself.

## Modules Inventory (`modules/`)

| File | Process | Purpose |
|---|---|---|
| `casanovo.nf` | `CASANOVO` | Inference on mzML → mzTab |
| `msconvert.nf` | `MSCONVERT` | RAW → mzML (cached via `storeDir`) |
| `limelight_xml_convert.nf` | `CONVERT_TO_LIMELIGHT_XML` | mzTab → Limelight XML |
| `limelight_upload.nf` | `UPLOAD_TO_LIMELIGHT` | Submit to Limelight webapp |
| `panorama.nf` | `PANORAMA_GET_{RAW_FILE,CASANOVO_PARAMS,CASANOVO_WEIGHTS}` | WebDAV downloads (three near-identical processes, one per input type) |
| `gh_download.nf` | `GH_DOWNLOAD_WEIGHTS` | Legacy GitHub download path (currently unused, see `main.nf:46-54`) |

## Conventions

- Every long-running process tees stdout/stderr into `*.stdout` / `*.stderr` outputs and ends with `echo "Done!"` — the trailing echo is load-bearing ("Needed for proper exit" comment).
- JAR-based processes (panorama, limelight) use a local `exec_java_command(mem)` helper that sets `-Xmx` to `task.memory.toGiga() - 1` GB.
- Results land in `${params.result_dir}/<stage>/` via `publishDir` (`casanovo/`, `limelight/`, `panorama/`). Reports (timeline/trace/report HTML) land in `${params.report_dir}/`.
- `process.shell = ['/bin/bash', '-euo', 'pipefail']` is set globally — scripts should be safe under strict mode.
- Email notifications on workflow completion via `lib/EmailTemplate.groovy` + `assets/email_template.html`, triggered only when `params.email` is set and `mail { ... }` SMTP config is supplied. The `workflow.onComplete` handler lives **inside the entry `workflow {}` block** in `main.nf`; the strict parser forbids top-level `workflow.onComplete` statements. (`nextflow lint` flags `EmailTemplate` as "not defined" — a false positive; it doesn't resolve `lib/*.groovy`, which Nextflow 26 still auto-compiles at runtime.)

### Nextflow 26 strict-parser constraints

Nextflow 26.x makes the strict config/script parser the runtime default. When editing config or `.nf` files, keep these rules (all are also accepted by the 25.x legacy parser, so the code stays valid on both lines):
- **No function definitions or `def` variable declarations in config files** (killed `check_max` and the `trace_timestamp` def — report file names now inline `new java.util.Date().format(...)`).
- **No `if`/arbitrary statements in config** — secrets use bare assignments with `?.`.
- **Process directives take no `=`**: `containerOptions { ... }`, `maxForks <expr>` — not `containerOptions = {`/`maxForks = ...`. No conditional (`if`) directives in a process body.
- **`maxForks` cannot be a closure** (it's compared as an int) — use a plain value/ternary directive.
- **`workflow.onComplete`/`onError` must be inside a workflow block**, not top-level.
- Validate edits with `nextflow lint main.nf workflows/ modules/ nextflow.config conf/base.config` and the stub harness; both must be clean under Nextflow 26.

## Running

```bash
nextflow run -resume -r main mriffle/nf-ms-dda-casanovo -c pipeline.config
```

Profile is selected with `-profile {standard|aws|slurm}`. Docker is enabled by default (`docker.enabled = true`).

## Tests

`tests/stub/run_stub_tests.sh` is a **self-contained** stub-test harness. It runs `nextflow ... -stub-run` across 12 input permutations (local/Panorama × raw/mzML/mzXML, Panorama-routed weights/params, Limelight on/off) **under each pinned Nextflow version**, for 12 × N total runs. Every process has a `stub:` block that touches its declared outputs — missing outputs will fail the process. Two tests tagged `(regression)` cover the Panorama-mzML direct path fixed in `workflows/casanovo.nf:22`.

**Setup / running on any machine** — no Nextflow install needed; only `bash`, `curl` or `wget`, and Java 17+:

```bash
tests/stub/run_stub_tests.sh                 # all permutations, all pinned versions
tests/stub/run_stub_tests.sh -v              # dump last 40 log lines on failure
tests/stub/run_stub_tests.sh -k panorama     # only tests whose name matches
tests/stub/run_stub_tests.sh -V 26           # only Nextflow versions matching "26"
NXF_VERSIONS="25.10.5 26.04.3" tests/stub/run_stub_tests.sh   # override the version list
```

On first run the harness downloads the Nextflow launcher and each pinned framework version into **`tests/stub/.nextflow-dist/`** (an isolated `NXF_HOME`); nothing is installed system-wide and `~/.nextflow` is never touched. Delete that directory to force a clean re-download. The pinned versions live in the `DEFAULT_VERSIONS` variable near the top of the script — currently the Nextflow 25 floor (`25.04.8`) and the Nextflow 26 target (`26.04.3`); keep the lowest in sync with the manifest `nextflowVersion` floor.

Per-test work lands in `tests/stub/.work/<version>/<n>_<name>/` (gitignored); fixtures are empty files created on first run under `tests/stub/fixtures/` (gitignored). `tests/stub/stub.config` disables containers/reports, forces the local executor, and pins a small `process.resourceLimits` so the large resource labels fit on CI runners. CI: `.github/workflows/stub-tests.yml` runs the harness (Java 17 + caches `.nextflow-dist/`) on pushes to `casanovo4-branch`.

## Branches

- `main` — default/PR target.
- `casanovo4-branch` — current working branch tracking Casanovo 4.x. Recent commits: cache directory paths, Casanovo image bump to a build that works with Apptainer, removed `--shm-size` for Apptainer, ProteoWizard and Limelight converter updates.
