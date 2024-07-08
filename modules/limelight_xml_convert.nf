def exec_java_command(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    return "java -Djava.aws.headless=true ${xmx} -jar /usr/local/bin/casanovoToLimelightXML.jar"
}

process CONVERT_TO_LIMELIGHT_XML {
    publishDir "${params.result_dir}/limelight", failOnError: true, mode: 'copy'
    label 'process_low'
    label 'process_high_memory'
    label 'process_long'
    container params.images.limelight_xml_convert

    input:
        path mztab
        path casanovo_log
        path casanovo_params

    output:
        path("results.limelight.xml"), emit: limelight_xml
        path("*.stdout"), emit: stdout
        path("*.stderr"), emit: stderr

    script:

    """
    echo "Running Limelight XML conversion..."
        ${exec_java_command(task.memory)} \
        --config_yaml="${casanovo_params}" \
        --mztab="${mztab}" \
        --out_file="results.limelight.xml" \
        -v \
        > >(tee "limelight-xml-convert.stdout") 2> >(tee "limelight-xml-convert.stderr" >&2)
        

    echo "Done!" # Needed for proper exit
    """

    stub:
    """
    touch "results.limelight.xml"
    """
}
