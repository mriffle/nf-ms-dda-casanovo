# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Keep this file current.** It is the onboarding contract for future agents. Whenever you change the project's purpose, architecture, conventions, testing setup, linting setup, or the Nextflow-version policy — or when you fix/discover something in **Known issues** — update the relevant section here in the same change. Treat an out-of-date CLAUDE.md as a bug.

## Project purpose

A Nextflow (DSL2) pipeline that runs **Casanovo** — a transformer model for *de novo* peptide sequencing of DDA mass-spectrometry proteomics data — on a single spectra file, then optionally converts the results to **Limelight XML** and uploads them to a Limelight server for visualization/sharing. The point is turnkey, containerized execution: a user installs only Nextflow + Docker (or runs on AWS Batch / Slurm) and needs none of Casanovo, msconvert, Java, or the Limelight tools locally.

Inputs (spectra, Casanovo params YAML, model weights `.ckpt`) may each be a **local path** or a **PanoramaWeb WebDAV URL** (`https://`); weights may additionally be a **GitHub release URL**. Every step runs in a pinned container.

## Commands

There is no build step and no unit tests; development is driven by the **stub-test harness** (see Testing) and the **linter**.

```bash
# Tests — run the pipeline with -stub-run across an input matrix × Nextflow versions
./tests/stub/run_stub_tests.sh              # full matrix, all NF versions
./tests/stub/run_stub_tests.sh -v           # print failing runs' output
./tests/stub/run_stub_tests.sh -k mzML      # only tests whose name contains "mzML"
./tests/stub/run_stub_tests.sh -V 26        # only NF versions matching "26"

# Lint — must be clean (0 errors, 0 warnings) before committing (see Linting)
nextflow lint main.nf workflows/ modules/ nextflow.config conf/ container_images.config

# Run the real pipeline locally (needs Docker; -c <config> is effectively mandatory — see Known issues #1)
nextflow run main.nf -profile standard -c pipeline.config
```

Profiles: `standard` (local), `aws` (AWS Batch), `slurm`. Param/secret templates: `resources/pipeline.config`, `resources/casanovo.yaml`.

## Architecture

Data flows `main.nf` (entry workflow) → `workflows/casanovo.nf` (subworkflow `wf_casanovo`) → `modules/*.nf` (one process each). Config is layered in `nextflow.config`.

- **`main.nf` resolves inputs by URL sniffing.** `https://…` → download from Panorama (`PANORAMA_GET_*`), **except** a `github.com` weights URL, which — like local paths — is resolved with Nextflow's `file()` (it stages `https` natively). Panorama needs an API key that `file()` can't supply, which is why it is special-cased. `GH_DOWNLOAD_WEIGHTS` is imported but its call site is commented out (dead — see Known issues).
- **`wf_casanovo`**: if input is `.raw`, `MSCONVERT` (ProteoWizard/Wine) converts it to mzML and caches the result via `storeDir` keyed on `params.mzml_cache_directory`; otherwise the spectra channel is used as-is. Then `CASANOVO` → `results.mztab` + `results.log`. If `params.limelight_upload`, `CONVERT_TO_LIMELIGHT_XML` then `UPLOAD_TO_LIMELIGHT`.
- **Spectra must stay a channel end-to-end.** `main.nf` wraps local spectra in `channel.fromPath(...)` so that *both* local and Panorama spectra are channels by the time `wf_casanovo` consumes them. Do **not** re-wrap inside the workflow with `channel.fromPath(spectra_file)` — for Panorama input `spectra_file` is already a channel and `channel.fromPath(<channel>)` crashes. This was a real regression; the `(regression)` stub tests guard it — keep them green.
- **Config layering** (`nextflow.config`): `params` defaults → `profiles` (per-executor `max_*` ceilings + cache dirs) → `includeConfig conf/base.config` (resource labels) → `includeConfig container_images.config` (image pins). All container image tags live in `container_images.config`; reference them as `params.images.<name>`.
- **Resource model:** processes carry `withLabel:` tiers from `conf/base.config`; `process.resourceLimits = [cpus, memory, time]` (fed by `params.max_*`) clamps every request natively. There is no `check_max()` — do not reintroduce it (it is NF26-illegal in config).
- **Secrets → env:** `nextflow.config` copies the `PANORAMA_API_KEY` and `LIMELIGHT_SUBMIT_UPLOAD_KEY` Nextflow secrets into `env.*`, because Nextflow can't pass secrets to AWS Batch. Module scripts read them as shell env vars.

## Conventions

- **Every process must have a working `stub:` block** whose `touch`ed files satisfy that process's `output:` globs. `-stub-run` (and therefore CI) fails otherwise. When you add or change a process's outputs, update its stub to match.
- Long-running `script:` blocks tee stdout/stderr to `*.stdout`/`*.stderr` files and end with `echo "DONE!"`. This is intentional — it forces a clean exit code past the `tee >(...)` process-substitution under `set -euo pipefail`. Keep both.
- Keep `nextflow.config`'s `params.<name>` declarations in sync with what processes read.
- Prefer lowercase `channel.` over `Channel.` for channel factories (NF26 lint deprecates the capitalized form).

## Testing

The harness (`tests/stub/run_stub_tests.sh`) runs the real pipeline with `-stub-run` (each process executes its `stub:` block, not its real command) across a 12-scenario input matrix — local/Panorama × `.raw`/`.mzML`/`.mzXML` × limelight on/off, plus Panorama-routed weights/params — **once per Nextflow version**. It is **self-contained**: it downloads a private Nextflow distribution into `tests/stub/.nextflow-dist/` (an isolated `NXF_HOME`; never touches `~/.nextflow`) and needs only bash + curl/wget + Java 17+. `tests/stub/stub.config` disables container engines and report files and clamps `resourceLimits` so the large labels fit on a CI runner.

- Versions under test are pinned in the script (`DEFAULT_VERSIONS`, currently `25.04.8 26.04.3`); override with `NXF_VERSIONS="…" ./tests/stub/run_stub_tests.sh`. Keep the lowest entry in sync with the manifest `nextflowVersion` floor.
- `tests/stub/{.work,fixtures,.nextflow-dist}/` are gitignored (regenerated on each run).
- CI: `.github/workflows/stub-tests.yml` runs the harness on push/PR to `main` (Java 17, caches the NF dist).
- Caveat: stub.config disables the `timeline/report/trace` blocks, so config changes to those aren't exercised by the harness. To fully resolve the merged config on a specific version, run:
  ```bash
  NXF_HOME=tests/stub/.nextflow-dist/home NXF_VER=26.04.3 \
    tests/stub/.nextflow-dist/nextflow config main.nf -profile standard
  ```

## Linting

Lint with Nextflow's built-in linter (requires a recent Nextflow; available on the pinned 26.x in `tests/stub/.nextflow-dist/`):

```bash
nextflow lint main.nf workflows/ modules/ nextflow.config conf/ container_images.config
# auto-format files that have no errors:
nextflow lint -format main.nf workflows/ modules/ nextflow.config conf/ container_images.config
```

Useful flags: `-o concise|full|json|markdown` (output mode), `-format` (rewrite formatting), `-sort-declarations`. The tree currently lints with **0 errors and 0 warnings** — keep it that way. If you don't have NF26 on `PATH`, run via the vendored launcher:

```bash
NXF_HOME=tests/stub/.nextflow-dist/home NXF_VER=26.04.3 \
  tests/stub/.nextflow-dist/nextflow lint main.nf workflows/ modules/ nextflow.config conf/ container_images.config
```

## Nextflow 26 compatibility (strict parser)

Target both Nextflow 25 (manifest floor `!>=25.04.0`) and 26. NF26's strict parser rejects constructs the project used to rely on — when editing, obey these:

- **Config files** (`nextflow.config`, `conf/base.config`): no `def`, no `if`, no function definitions. Inline expressions instead (e.g. the timestamp in report `file =` lines), use `?.value` instead of `if`-guards, and use `process.resourceLimits` instead of helper functions.
- **Process directives**: closures take no `=` (`containerOptions { ... }`, not `containerOptions = { ... }`); no `if`/assignment in the process body (`maxForks params.use_gpus ? 1 : null`, not `if (...) { maxForks = 1 }`).
- **`main.nf`**: `workflow.onComplete { ... }` must live *inside* the entry `workflow { }` block, not at top level.

## Branches / versions

`main` tracks **Casanovo 5.x**. `casanovo4-branch` is a **parallel** branch for the older, incompatible **Casanovo 4.x** — not a downstream of `main`. Portable fixes (wiring, NF26 compatibility, stub/test infrastructure) should land on both, but **do not port Casanovo-version-specific bits**: `main` uses the v5 CLI (`casanovo sequence --output_dir . --output_root results`), v5.0.0 weights, and the v5 container tags in `container_images.config`.

## Known issues

Pre-existing problems found by audit (not regressions; not yet fixed). Severity in brackets. Update/remove entries as they're resolved.

1. **[HIGH] No-`-c` runs crash.** `main.nf:63` computes `config_file = file(workflow.configFiles[1])` unconditionally; with no `-c` config there is no index `1`, so `file(null)` throws even for non-Limelight runs. Also brittle: assumes exactly one `-c` at position 1. *Fix:* guard the index and/or only compute it inside the `params.limelight_upload` branch. The harness can't catch this — it always passes `-c stub.config`.
2. **[MED] Limelight upload params have no defaults or validation.** `limelight_webapp_url`, `limelight_project_id`, `limelight_search_description`, `limelight_search_short_name` are read in `workflows/casanovo.nf` but not declared in `nextflow.config` (only in the example `resources/pipeline.config`). If `limelight_upload=true` and one is omitted it is silently passed as `null`. *Fix:* declare defaults + add a preflight check.
3. **[MED] AWS client settings silently ignored.** `aws.batch.{maxConnections,connectionTimeout,uploadStorageClass,storageEncryption}` (`nextflow.config:78-81`) are unrecognized keys in current `nf-amazon` (they belong under `aws.client.*`), so `AES256`/`INTELLIGENT_TIERING` etc. are not applied. *Fix:* move them under `aws.client {}` (verify against your `nf-amazon` version).
4. **[MED] JVM `headless` typo.** `-Djava.aws.headless=true` should be `-Djava.awt.headless=true` in `modules/panorama.nf:5`, `modules/limelight_upload.nf:3`, `modules/limelight_xml_convert.nf:3` — as written the JVM is not actually headless.
5. **[MED] Docs/default version drift.** `docs/source/workflow_parameters.rst:68` says the default weights are `v4.2.0`; the config default is `v5.0.0`. `docs/source/results.rst:11` shows Nextflow `23.04.1` and an example run that omits MSCONVERT.
6. **[LOW] Secrets-to-env nuance.** `nextflow.config:69-70` now always exports `env.PANORAMA_API_KEY`/`env.LIMELIGHT_SUBMIT_UPLOAD_KEY`, set to empty when the secret is absent (the comment's claim of "matching the previous guarded behavior" is imprecise for the Panorama key, which used to be left unset). Low impact; correct the comment or restore guarding.
7. **[LOW] `-Xmx${mem.toGiga()-1}G` underflows** to `0`/negative if `max_memory` is clamped below `2.GB` (the three Java helper functions). Use `Math.max(1, …)`.
8. **[LOW] `panorama_cache_directory` is dead.** Set in every profile and documented as a download cache, but no process references it (only `MSCONVERT` uses `storeDir`). Panorama downloads are re-fetched every run. *Fix:* wire a `storeDir` into `PANORAMA_GET_*`, or drop the param + docs.
9. **[LOW] Unused process input.** `CONVERT_TO_LIMELIGHT_XML` (`modules/limelight_xml_convert.nf`) declares `path casanovo_log` but never uses it in the script — either pass it to the converter or drop the input.
10. **[LOW] Root-owned local outputs.** No `docker.runOptions` user mapping, so Docker steps run as root and emit root-owned files on local runs.
11. **[LOW] `MSCONVERT` cache collisions.** `storeDir` keyed on `raw_file.baseName` collides for same-named raws from different directories.
12. **[NIT]** Wrong `nextflow.config` header comment ("Parameters for nf-maccoss-trex … data-ind"); stale "4.2" strings in `resources/pipeline.config:21-23`; dead `GH_DOWNLOAD_WEIGHTS` import + commented block (`main.nf:9,46-54`); unused params `limelight_import_decoys`/`limelight_entrapment_prefix`; three near-identical `PANORAMA_GET_*` processes (DRY).
