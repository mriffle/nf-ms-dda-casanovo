process CASANOVO {
    publishDir "${params.result_dir}/casanovo", failOnError: true, mode: 'copy'
    label 'process_high_constant'
    label 'process_long'
    container params.images.casanovo
    containerOptions '--shm-size 1000000000'

    // don't melt the GPU
    if (params.use_gpus) {
        maxForks = 1
    }

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
    echo "Running casanovo..."
    casanovo sequence \
        --config ${casanovo_params_file} \
        --model ${casanovo_weights_file} \
        --output results.mztab \
        ${mzml_file} \
        > >(tee "${mzml_file.baseName}.casanovo.stdout") 2> >(tee "${mzml_file.baseName}.casanovo.stderr" >&2)

    echo "DONE!" # Needed for proper exit
    """
}
