# nf-ms-dda-casanovo

Nextflow DSL2 pipeline for de novo peptide identification from DDA mass spec data using Casanovo. Requires Nextflow >= 24.04.4.

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
   - `maxForks = 1` when GPUs are on ("don't melt the GPU")

4. **Optional Limelight upload** (gated on `params.limelight_upload`):
   - `CONVERT_TO_LIMELIGHT_XML` (`modules/limelight_xml_convert.nf`) — `casanovoToLimelightXML.jar` turns mzTab into Limelight XML.
   - `UPLOAD_TO_LIMELIGHT` (`modules/limelight_upload.nf`) — `limelightSubmitImport.jar` posts XML + scan files + the pipeline config to a Limelight webapp.

## Config Layout

- **`nextflow.config`** — params defaults, AWS Batch settings (us-west-2, `nextflow_basic_ec2` queue, INTELLIGENT_TIERING), and profiles: `standard` (local, 12GB/8cpu), `aws` (awsbatch, 124GB/32cpu, s3:// cache dirs), `slurm` (12GB/8cpu). Secrets `LIMELIGHT_SUBMIT_UPLOAD_KEY` and `PANORAMA_API_KEY` are loaded from Nextflow secrets into `env.*` at config time — this is deliberate because AWS Batch can't consume Nextflow secrets directly.
- **`conf/base.config`** — nf-core-style resource labels (`process_low`, `process_medium`, `process_high`, `process_*_constant`, `process_long`, `process_very_long_constant`, `process_high_memory`, `error_retry`, `error_ignore`). Retry-on-OOM exit codes: `[143,137,104,134,139,5,6,null]`, `maxRetries = 3`. All resource requests are clamped via the `check_max` helper at the bottom of `nextflow.config`.
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
- Email notifications on workflow completion via `lib/EmailTemplate.groovy` + `assets/email_template.html`, triggered only when `params.email` is set and `mail { ... }` SMTP config is supplied.

## Running

```bash
nextflow run -resume -r main mriffle/nf-ms-dda-casanovo -c pipeline.config
```

Profile is selected with `-profile {standard|aws|slurm}`. Docker is enabled by default (`docker.enabled = true`).

## Tests

`tests/stub/run_stub_tests.sh` runs `nextflow ... -stub-run` across 12 input permutations (local/Panorama × raw/mzML/mzXML, Panorama-routed weights/params, Limelight on/off). Every process has a `stub:` block that touches its declared outputs — missing outputs will fail the process. Two tests tagged `(regression)` cover the Panorama-mzML direct path fixed in `workflows/casanovo.nf:22`. Run with `-v` to dump failure logs, `-k <substring>` to filter. Fixtures are empty files created on first run under `tests/stub/fixtures/` (gitignored).

## Branches

- `main` — default/PR target.
- `casanovo4-branch` — current working branch tracking Casanovo 4.x. Recent commits: cache directory paths, Casanovo image bump to a build that works with Apptainer, removed `--shm-size` for Apptainer, ProteoWizard and Limelight converter updates.
