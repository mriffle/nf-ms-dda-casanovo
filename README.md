# nf-ms-dda-casanovo

A Nextflow workflow for *de novo* DDA MS/MS peptide sequencing using [Casanovo](https://github.com/Noble-Lab/casanovo).

📖 **Full documentation:** https://nf-ms-dda-casanovo.readthedocs.io/

## What it is

Casanovo is a deep-learning (transformer) model that identifies peptides directly from DDA tandem mass spectra — no sequence database required. This workflow wraps Casanovo end to end: it optionally converts instrument RAW files to mzML, runs Casanovo to generate peptide-spectrum matches, and can convert and upload the results to [Limelight](https://limelight-ms.org/) for visualization and sharing.

Every step runs in a pinned container, so you only need Nextflow and a container engine (or a cloud/cluster executor) — there's no need to install Casanovo, msconvert, Java, or any other component. Input files (spectra, the Casanovo config, and the model weights) may be local paths or **PanoramaWeb** WebDAV URLs; model weights may also be a GitHub release URL.

## Running it

Install Nextflow and Docker, create a `pipeline.config` describing your inputs and options (templates are in [`resources/`](resources/)), then:

```bash
nextflow run -resume -r main mriffle/nf-ms-dda-casanovo -c pipeline.config
```

The workflow downloads its container images automatically and writes results to a `results/` directory. Full installation, parameter, AWS Batch, and results documentation is on [Read the Docs](https://nf-ms-dda-casanovo.readthedocs.io/).

## Architecture & design

The pipeline is written in Nextflow DSL2. The entry workflow (`main.nf`) resolves inputs and dispatches to the `wf_casanovo` subworkflow (`workflows/casanovo.nf`), which orchestrates one process per step (`modules/*.nf`):

```
input resolution ─▶ MSCONVERT (RAW only) ─▶ CASANOVO ─▶ [ CONVERT_TO_LIMELIGHT_XML ─▶ UPLOAD_TO_LIMELIGHT ]
                                                          └─ only when limelight_upload = true
```

Notable design points:

- **Pluggable input sources.** Each input is a local path or an `https://` URL. URLs are routed automatically: PanoramaWeb downloads go through an API-key client process, while GitHub-hosted weights and local files use Nextflow's native file staging.
- **Fully containerized & portable.** All image tags are centralized in `container_images.config` and referenced as `params.images.<name>`. The same workflow runs unchanged on a laptop (Docker), an HPC cluster (Slurm), or the cloud (AWS Batch) — selected via execution profiles in `nextflow.config`.
- **Resource model.** Processes declare coarse `withLabel:` resource tiers (`conf/base.config`); Nextflow's `process.resourceLimits`, fed by per-profile `max_cpus`/`max_memory`/`max_time`, clamps every request to what the target system can provide.
- **Caching.** Converted mzML files are cached with `storeDir`, so re-runs skip msconvert.
- **Secrets.** Panorama/Limelight credentials are read from Nextflow secrets and injected into the task environment (so they work on AWS Batch, which can't consume Nextflow secrets directly).

## Development

- **Tests:** a self-contained stub-test harness (`tests/stub/run_stub_tests.sh`) runs the pipeline with `-stub-run` across an input matrix on multiple Nextflow versions (25 and 26); GitHub Actions runs it on every push/PR.
- **Lint:** `nextflow lint main.nf workflows/ modules/ nextflow.config conf/ container_images.config`.
- See [`CLAUDE.md`](CLAUDE.md) for architecture details, conventions, the Nextflow-26 compatibility rules, and known issues.
