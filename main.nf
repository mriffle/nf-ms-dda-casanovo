#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// modules
include { PANORAMA_GET_CASANOVO_PARAMS } from "./modules/panorama"
include { PANORAMA_GET_CASANOVO_WEIGHTS } from "./modules/panorama"
include { PANORAMA_GET_RAW_FILE } from "./modules/panorama"
include { GH_DOWNLOAD_WEIGHTS } from "./modules/gh_download"

// Sub workflows
include { wf_casanovo } from "./workflows/casanovo"

//
// The main workflow
//
workflow {

    // ensure we have a valid extension for the spectra file
    def valid_extensions = [".raw", ".mzml", ".mzxml"]
    def file_extension = params.spectra_file.toLowerCase().tokenize('.').last()
    if (!valid_extensions.contains('.' + file_extension)) {
        error "`spectra_file` must end with one of the following extensions: ${valid_extensions.join(', ')}"
    }

    // whether or not we're starting from a raw file
    from_raw_file = params.spectra_file.toLowerCase().endsWith(".raw");

    // get spectra file from Panorama, if requested
    if(params.spectra_file.startsWith("https://")) {
        PANORAMA_GET_RAW_FILE(params.spectra_file)
        spectra_file = PANORAMA_GET_RAW_FILE.out.panorama_file
    } else {
        spectra_file = file(params.spectra_file, checkIfExists: true)
    }

    // get Casanovo params from Panorama, if requested
    if(params.casanovo_params.startsWith("https://")) {
        PANORAMA_GET_CASANOVO_PARAMS(params.casanovo_params)
        casanovo_params = PANORAMA_GET_CASANOVO_PARAMS.out.panorama_file
    } else {
        casanovo_params = file(params.casanovo_params, checkIfExists: true)
    }

    // get weights file from requested location
    // if (params.casanovo_weights.startsWith("https://") && params.casanovo_weights =~ /^https:\/\/[^\/]*github\.com/) {
    //     GH_DOWNLOAD_WEIGHTS(params.casanovo_weights)
    //     casanovo_weights = GH_DOWNLOAD_WEIGHTS.out.ckpt_file
    // } else if(params.casanovo_weights.startsWith("https://")) {
    //     PANORAMA_GET_CASANOVO_WEIGHTS(params.casanovo_weights)
    //     casanovo_weights = PANORAMA_GET_CASANOVO_WEIGHTS.out.panorama_file
    // } else {
    //     casanovo_weights = file(params.casanovo_weights, checkIfExists: true)
    // }

    if (params.casanovo_weights.startsWith("https://") && !(params.casanovo_weights =~ /^https:\/\/[^\/]*github\.com/)) {
        PANORAMA_GET_CASANOVO_WEIGHTS(params.casanovo_weights)
        casanovo_weights = PANORAMA_GET_CASANOVO_WEIGHTS.out.panorama_file
    } else {
        casanovo_weights = file(params.casanovo_weights, checkIfExists: true)
    }

    wf_casanovo(spectra_file, casanovo_params, casanovo_weights, from_raw_file)
}

//
// Used for email notifications
//
def email() {
    // Create the email text:
    def (subject, msg) = EmailTemplate.email(workflow, params)
    // Send the email:
    if (params.email) {
        sendMail(
            to: "$params.email",
            subject: subject,
            body: msg
        )
    }
}

//
// This is a dummy workflow for testing
//
workflow dummy {
    println "This is a workflow that doesn't do anything."
}

// Email notifications:
workflow.onComplete {
    try {
        email()
    } catch (Exception e) {
        println "Warning: Error sending completion email."
    }
}
