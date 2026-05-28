process CASANOVO {
    publishDir "${params.result_dir}/casanovo", failOnError: true, mode: 'copy'
    label 'process_high_constant'
    label 'process_very_long_constant'
    container params.images.casanovo

    // Directive closures take no `=` in the strict (Nextflow 26) parser.
    containerOptions {

        // When the executor is awsbatch, --shm-size is expecting the number of MiB
        // otherwise it is expecting the number of bytes
        def options = ''
        if (workflow.containerEngine == "docker") {
            options += '--shm-size 1g'
        }

        if (params.use_gpus) {
            if (workflow.containerEngine == "singularity" || workflow.containerEngine == "apptainer") {
                options += ' --nv'
            } else if (workflow.containerEngine == "docker") {
                options += ' --gpus all'
            }
            
            if (params.cuda_launch_blocking) {
                options += ' -e CUDA_LAUNCH_BLOCKING=1'
            }
        }

        return options
    }

    // don't melt the GPU: cap concurrency at 1 on GPUs, otherwise no limit (null).
    // Written as a directive (no `=`, no `if`) so it parses under Nextflow 26's
    // strict parser while still being evaluated after the full config is merged
    // (so `--use_gpus` / `-c` overrides are honored).
    maxForks params.use_gpus ? 1 : null

    input:
        path mzml_file
        path casanovo_params_file
        path casanovo_weights_file

    output:
        path("results.mztab"), emit: mztab_file
        path("results.log"), emit: log_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    export HOME=\$PWD

    echo "Running casanovo..."
    casanovo sequence \
        --config ${casanovo_params_file} \
        --model ${casanovo_weights_file} \
        --output_dir . \
        --output_root results \
        ${mzml_file} \
        > >(tee "${mzml_file.baseName}.casanovo.stdout") 2> >(tee "${mzml_file.baseName}.casanovo.stderr" >&2)

    echo "DONE!" # Needed for proper exit
    """

    stub:
    """
    touch results.mztab results.log
    touch "${mzml_file.baseName}.casanovo.stdout"
    touch "${mzml_file.baseName}.casanovo.stderr"
    """
}
