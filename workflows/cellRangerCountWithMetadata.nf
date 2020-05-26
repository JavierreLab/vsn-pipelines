nextflow.preview.dsl=2

import java.nio.file.Paths

//////////////////////////////////////////////////////
//  process imports:

include {
    SC__CELLRANGER__COUNT_WITH_METADATA;
} from './../processes/count' params(params)

//////////////////////////////////////////////////////
//  Define the workflow 

workflow CELLRANGER_COUNT_WITH_METADATA {

    def getFastQsFilePath = { fastqsParentDirPath, fastqsDirName ->
        if(fastqsDirName == "n/a" || fastqsDirName == "n.a." || fastqsDirName == "none" || fastqsDirName == "null")
            return file(fastqsParentDirPath)
        return file(Paths.get(fastqsParentDirPath, fastqsDirName))
    }

    take:
        transcriptome
        metadata

    main:
        // Define the sampleId
        data = Channel.from(
            metadata
        ).splitCsv(
            header:true,
            sep: '\t'
        ).map {
            row -> tuple(
                row.short_uuid + "__" + row.sample_name,
                row.fastqs_sample_prefix,
                getFastQsFilePath(row.fastqs_parent_dir_path, row.fastqs_dir_name),
                // Begin CellRanger parameters
                row.expect_cells
            )
        }
        SC__CELLRANGER__COUNT_WITH_METADATA( transcriptome, data )

    emit:
        SC__CELLRANGER__COUNT_WITH_METADATA.out

}
