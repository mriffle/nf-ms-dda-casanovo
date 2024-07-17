process GH_DOWNLOAD_WEIGHTS {
    publishDir "${params.result_dir}/casanovo", failOnError: true, mode: 'copy'
    label 'process_low_constant'
    container params.images.ubuntu

    input:
        path weights_url

    output:
        path("*.ckpt"), emit: ckpt_file
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:
    """
    echo "Downloading weights..."
    wget ${weights_url} \
        > >(tee "gh_weights_dl.stdout") 2> >(tee "gh_weights_dl.stderr" >&2)

    echo "DONE!" # Needed for proper exit
    """

}
