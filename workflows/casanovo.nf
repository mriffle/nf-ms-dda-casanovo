// Modules
include { MSCONVERT } from "../modules/msconvert"
include { CASANOVO } from "../modules/casanovo"
include { CONVERT_TO_LIMELIGHT_XML } from "../modules/limelight_xml_convert"
include { UPLOAD_TO_LIMELIGHT } from "../modules/limelight_upload"

workflow wf_casanovo {

    take:
        spectra_file_ch
        casanovo_params
        casanovo_weights
        from_raw_file
        config_file
    
    main:

        // convert raw files to mzML files if necessary
        if(from_raw_file) {
            mzml_file_ch = MSCONVERT(spectra_file_ch)
        } else {
            mzml_file_ch = spectra_file_ch
        }

        CASANOVO(mzml_file_ch, casanovo_params, casanovo_weights)

        if (params.limelight_upload) {

            CONVERT_TO_LIMELIGHT_XML(
                CASANOVO.out.mztab_file, 
                CASANOVO.out.log_file,
                casanovo_params
            )

            UPLOAD_TO_LIMELIGHT(
                CONVERT_TO_LIMELIGHT_XML.out.limelight_xml,
                mzml_file_ch.collect(),
                params.limelight_webapp_url,
                params.limelight_project_id,
                params.limelight_search_description,
                params.limelight_search_short_name,
                params.limelight_tags,
                config_file
            )
        }

}
