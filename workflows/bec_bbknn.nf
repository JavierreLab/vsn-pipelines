/*
 * BEC__BBKNN workflow 
 * Source: https://github.com/Teichlab/bbknn/blob/master/examples/pancreas.ipynb
 * 
 * Steps considered: 
 * - normalize
 * - concatenate the batches
 * - feature selection
 * - log transform
 * - feature scaling
 * - dimensionality reduction (PCA)
 * - batch effect correction using python package bbknn (Park et al. (2018), Fast Batch Alignment of Single Cell Transcriptomes Unifies Multiple Mouse Cell Atlases into an Integrated Landscape)
 */ 

nextflow.preview.dsl=2

//////////////////////////////////////////////////////
//  process imports:

include '../../utils/processes/utils.nf' params(params)
include COMBINE_BY_PARAMS from "../../utils/workflows/utils.nf" params(params)
include PUBLISH as PUBLISH_BEC_OUTPUT from "../../utils/workflows/utils.nf" params(params)
include PUBLISH as PUBLISH_BEC_DIMRED_OUTPUT from "../../utils/workflows/utils.nf" params(params)
include PUBLISH as PUBLISH_FINAL_BBKNN_OUTPUT from "../../utils/workflows/utils.nf" params(params)

// scanpy:
include '../processes/batch_effect_correct.nf' params(params)

include '../processes/dim_reduction.nf' params(params)
include SC__SCANPY__DIM_REDUCTION as SC__SCANPY__DIM_REDUCTION__UMAP from '../processes/dim_reduction.nf' params(params + [method: "umap"])
include '../processes/cluster.nf' params(params)
include './cluster_identification.nf' params(params) // Don't only import a specific process (the function needs also to be imported)

// reporting:
include GENERATE_DUAL_INPUT_REPORT from './create_report.nf' params(params + params.global)

//////////////////////////////////////////////////////
//  Define the workflow 

workflow BEC_BBKNN {

    take:
        normalizedTransformedData
        dimReductionData
        // Expects (sampleId, anndata)
        clusterIdentificationPreBatchEffectCorrection

    main:
        SC__SCANPY__BATCH_EFFECT_CORRECTION( 
            dimReductionData.map { 
                it -> tuple(it[0], it[1], it[2]) 
            } 
        )
        PUBLISH_BEC_OUTPUT(
            SC__SCANPY__BATCH_EFFECT_CORRECTION.out,
            "BEC_BBKNN.output",
            null,
            false
        )

        // Define the parameters for dimensionality reduction
        def dimRedParams = SC__SCANPY__DIM_REDUCTION_PARAMS( clean(params.sc.scanpy.dim_reduction.umap) )
        SC__SCANPY__DIM_REDUCTION__UMAP( 
            SC__SCANPY__BATCH_EFFECT_CORRECTION.out.combine(
                dimRedParams.$()
            ).view()
        )

        PUBLISH_BEC_DIMRED_OUTPUT(
            SC__SCANPY__DIM_REDUCTION__UMAP.out,
            "BEC_BBKNN.dimred_output",
            null,
            false
        )

        // Define the parameters for clustering
        def clusteringParams = SC__SCANPY__CLUSTERING_PARAMS( clean(params.sc.scanpy.clustering) )
        CLUSTER_IDENTIFICATION(
            normalizedTransformedData,
            SC__SCANPY__DIM_REDUCTION__UMAP.out,
            "Post Batch Effect Correction (BBKNN)"
        )

        PUBLISH_FINAL_BBKNN_OUTPUT(
            CLUSTER_IDENTIFICATION.out.marker_genes.map {
                it -> tuple(
                    it[0], // sampleId
                    it[1], // data
                    !clusteringParams.isParameterExplorationModeOn() ? null : it[2..(it.size()-1)], // Stash params
                )
            },
            "BEC_BBKNN.final_output",
            null,
            clusteringParams.isParameterExplorationModeOn()
        )

        // This will generate a dual report with results from
        // - Pre batch effect correction
        // - Post batch effect correction
        becDualDataPrePost = COMBINE_BY_PARAMS(
            clusterIdentificationPreBatchEffectCorrection,
            // Use PUBLISH output to avoid "input file name collision"
            PUBLISH_FINAL_BBKNN_OUTPUT.out,
            clusteringParams
        )

        bbknn_report = GENERATE_DUAL_INPUT_REPORT(
            becDualDataPrePost,
            file(workflow.projectDir + params.sc.scanpy.batch_effect_correct.report_ipynb),
            "SC_BEC_BBKNN_report",
            clusteringParams.isParameterExplorationModeOn()
        )

    emit:
        data = CLUSTER_IDENTIFICATION.out.marker_genes
        cluster_report = CLUSTER_IDENTIFICATION.out.report
        bbknn_report

}
