version 1.0

import "tasks/common.wdl" as common
import "tasks/picard.wdl" as picard
import "tasks/samtools.wdl" as samtools

workflow BamMetrics {
    input {
        IndexedBamFile bam
        String outputDir = "."
        Reference reference

        File? refRefflat
        String strandedness = "None"

        Array[File]+? targetIntervals
        File? ampliconIntervals

        Map[String, String] dockerImages = {
          "samtools":"quay.io/biocontainers/samtools:1.8--h46bd0b3_5",
          "picard":"quay.io/biocontainers/picard:2.20.5--0",
        }
    }

    String prefix = outputDir + "/" + basename(bam.file, ".bam")

    call samtools.Flagstat as Flagstat {
        input:
            inputBam = bam.file,
            outputPath = prefix + ".flagstats",
            dockerImage = dockerImages["samtools"]
    }

    call picard.CollectMultipleMetrics as picardMetrics {
        input:
            inputBam = bam.file,
            inputBamIndex = bam.index,
            basename = prefix,
            referenceFasta = reference.fasta,
            referenceFastaDict = reference.dict,
            referenceFastaFai = reference.fai,
            dockerImage = dockerImages["picard"]
    }

    if (defined(refRefflat)) {
        Map[String, String] strandednessConversion = {"None": "NONE",
            "FR":"FIRST_READ_TRANSCRIPTION_STRAND", "RF": "SECOND_READ_TRANSCRIPTION_STRAND"}

        call picard.CollectRnaSeqMetrics as rnaSeqMetrics {
            input:
                inputBam = bam.file,
                inputBamIndex = bam.index,
                refRefflat = select_first([refRefflat]),
                basename = prefix,
                strandSpecificity = strandednessConversion[strandedness],
                dockerImage = dockerImages["picard"]
        }
    }

    if (defined(targetIntervals)) {
        Array[File] targetBeds = select_first([targetIntervals])
        scatter (targetBed in targetBeds) {
            call picard.BedToIntervalList as targetIntervalsLists {
                input:
                    bedFile = targetBed,
                    outputPath =
                        prefix + "_intervalLists/" + basename(targetBed) + ".interval_list",
                    dict = reference.dict,
                    dockerImage = dockerImages["picard"]
            }
        }

        call picard.BedToIntervalList as ampliconIntervalsLists {
             input:
                 bedFile = select_first([ampliconIntervals]),
                 outputPath = prefix + "_intervalLists/" +
                    basename(select_first([ampliconIntervals])) + ".interval_list",
                 dict = reference.dict,
                 dockerImage = dockerImages["picard"]
            }

        call picard.CollectTargetedPcrMetrics as targetMetrics {
            input:
                inputBam = bam.file,
                inputBamIndex = bam.index,
                referenceFasta = reference.fasta,
                referenceFastaDict = reference.dict,
                referenceFastaFai = reference.fai,
                basename = prefix,
                targetIntervals = targetIntervalsLists.intervalList,
                ampliconIntervals = ampliconIntervalsLists.intervalList,
                dockerImage = dockerImages["picard"]
        }
    }

    output {
        File flagstats = Flagstat.flagstat
        Array[File] picardMetricsFiles = picardMetrics.allStats
        Array[File] rnaMetrics = select_all([rnaSeqMetrics.metrics, rnaSeqMetrics.chart])
        Array[File] targetedPcrMetrics = select_all([targetMetrics.perTargetCoverage, targetMetrics.perBaseCoverage, targetMetrics.metrics])

    }
}
