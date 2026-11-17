# -*- mode: makefile -*-
# Benchmark intron-prospector against STAR SJ.out.tab.
#
# Each dataset is one full pass over a multi-gigabyte BAM, so use `make -j` to
# overlap them.  Datasets and their inputs are in conf/datasets.tsv.
#
#   make calls       run intron-prospector, write output/<ds>.<run>.calls.tsv
#   make flair       run flair's junctions_from_sam, write output/<ds>.flair.bed
#   make compare     compare the three junction sets (depends on calls and flair)
#
# One intron-prospector pass per dataset per run in ${runs}, and one comparison
# of each against SJ.out.tab and the flair BED per filter in ${filters}.
# bin/sj-compare --help lists the filters and what each keeps.

datasets = $(shell tail -n +2 conf/datasets.tsv | cut -f1)
outDir = output

# intron-prospector source tree, which is a separate repository;
# `make prospectorDir=/some/where` to build against another one
prospectorDir = ../intron-prospector
prospector = ${prospectorDir}/bin/intron-prospector

# flair's junctions_from_sam, in the flair-mddev conda environment beside the
# markd one this benchmark runs in.  Its shebang names that environment's
# python, so it runs without activating it.
flairJuncs = $(dir ${CONDA_PREFIX})flair-mddev/bin/junctions_from_sam

# SJ.out.tab of the dataset in $*, looked up at recipe time
sjOutTab = $$(awk -F'\t' -v name=$* 'NR>1 && $$1==name{print $$3}' conf/datasets.tsv)

# intron-prospector passes to compare, each naming the alignment categories it
# reads that the default run excludes.  base is the default run; qcfail adds the
# alignments the sequencer's chastity filter flagged, which SJ.out.tab and
# junctions_from_sam both count; secondary adds the other loci of a
# multi-mapping read on top of those, which junctions_from_sam counts and
# SJ.out.tab counts in its multi-mapping column.  The BAMs have no duplicate
# flags, so the secondary run reads every alignment junctions_from_sam reads.
runs = base qcfail secondary
baseRunOpts =
qcfailRunOpts = --include=qcfail
secondaryRunOpts = --include=qcfail,secondary

# bin/sj-compare filters, each applied to both sides
filters = raw filt_similar filt_flair

# compare only chr1..chr22, chrX, chrY, chrM; `make compareOpts=` to include
# scaffolds, patches, alts and spike-ins
compareOpts = --main-chroms-only

.PHONY: all
all: compare

.PHONY: calls
calls: $(foreach r,${runs},${datasets:%=${outDir}/%.$r.calls.tsv})

.PHONY: flair
flair: ${datasets:%=${outDir}/%.flair.bed}

.PHONY: compare
compare: $(foreach r,${runs},$(foreach f,${filters},${datasets:%=${outDir}/%.$r.$f.summary.tsv}))

# one rule per run, with the dataset as the stem
define callsRule
${outDir}/%.$(1).calls.tsv: bin/run-prospector bin/benchconf.py conf/datasets.tsv $${prospector}
	./bin/run-prospector --prospector=$${prospector} $${$(1)RunOpts} $$* $$@
endef
$(foreach r,${runs},$(eval $(call callsRule,$r)))

${outDir}/%.flair.bed: bin/run-flair-juncs bin/benchconf.py conf/datasets.tsv
	./bin/run-flair-juncs --junctions-from-sam=${flairJuncs} $* $@

# one rule per run and filter, with the dataset as the stem.
# junctions_from_sam reads every alignment, so one flair BED serves both runs.
define compareRule
${outDir}/%.$(1).$(2).compare.tsv.gz ${outDir}/%.$(1).$(2).summary.tsv: ${outDir}/%.$(1).calls.tsv ${outDir}/%.flair.bed bin/sj-compare
	./bin/sj-compare --filter=$(2) $${compareOpts} \
	    --flair-bed=$${outDir}/$$*.flair.bed \
	    $${sjOutTab} $${outDir}/$$*.$(1).calls.tsv \
	    $${outDir}/$$*.$(1).$(2).compare.tsv.gz $${outDir}/$$*.$(1).$(2).summary.tsv
endef
$(foreach r,${runs},$(foreach f,${filters},$(eval $(call compareRule,$r,$f))))

${prospector}:
	cd ${prospectorDir} && ${MAKE}

.PHONY: clean
clean:
	rm -rf ${outDir}

.DELETE_ON_ERROR:

# Local Variables:
# mode: makefile-gmake
# End:
