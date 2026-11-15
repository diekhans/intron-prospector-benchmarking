# -*- mode: makefile -*-
# Benchmark intron-prospector against STAR SJ.out.tab.
#
# Each dataset is one full pass over a multi-gigabyte BAM, so use `make -j` to
# overlap them.  Datasets and their inputs are in conf/datasets.tsv.
#
#   make calls       run intron-prospector, write output/<ds>.calls.tsv
#   make flair       run flair's junctions_from_sam, write output/<ds>.flair.bed
#   make compare     compare the three junction sets (depends on calls and flair)
#
# One comparison per dataset per filter in ${filters}; bin/sj-compare --help
# lists the filters and what each keeps.

datasets = $(shell tail -n +2 conf/datasets.tsv | cut -f1)
outDir = output

# intron-prospector source tree, which is a separate repository;
# `make prospectorDir=/some/where` to build against another one
prospectorDir = ../intronProspector
prospector = ${prospectorDir}/bin/intron-prospector

# flair's junctions_from_sam, in the flair-mddev conda environment beside the
# markd one this benchmark runs in.  Its shebang names that environment's
# python, so it runs without activating it.
flairJuncs = $(dir ${CONDA_PREFIX})flair-mddev/bin/junctions_from_sam

# SJ.out.tab of the dataset in $*, looked up at recipe time
sjOutTab = $$(awk -F'\t' -v name=$* 'NR>1 && $$1==name{print $$3}' conf/datasets.tsv)

# bin/sj-compare filters, each applied to both sides
filters = raw filt_similar filt_flair

# compare only chr1..chr22, chrX, chrY, chrM; `make compareOpts=` to include
# scaffolds, patches, alts and spike-ins
compareOpts = --main-chroms-only

.PHONY: all
all: compare

.PHONY: calls
calls: ${datasets:%=${outDir}/%.calls.tsv}

.PHONY: flair
flair: ${datasets:%=${outDir}/%.flair.bed}

.PHONY: compare
compare: $(foreach f,${filters},${datasets:%=${outDir}/%.$f.summary.tsv})

${outDir}/%.calls.tsv: bin/run-prospector bin/benchconf.py conf/datasets.tsv ${prospector}
	./bin/run-prospector --prospector=${prospector} $* $@

${outDir}/%.flair.bed: bin/run-flair-juncs bin/benchconf.py conf/datasets.tsv
	./bin/run-flair-juncs --junctions-from-sam=${flairJuncs} $* $@

# one pattern rule per filter, with the dataset as the stem
define compareRule
${outDir}/%.$(1).compare.tsv.gz ${outDir}/%.$(1).summary.tsv: ${outDir}/%.calls.tsv ${outDir}/%.flair.bed bin/sj-compare
	./bin/sj-compare --filter=$(1) $${compareOpts} \
	    --flair-bed=$${outDir}/$$*.flair.bed \
	    $${sjOutTab} $${outDir}/$$*.calls.tsv \
	    $${outDir}/$$*.$(1).compare.tsv.gz $${outDir}/$$*.$(1).summary.tsv
endef
$(foreach f,${filters},$(eval $(call compareRule,$f)))

${prospector}:
	cd ${prospectorDir} && ${MAKE}

.PHONY: clean
clean:
	rm -rf ${outDir}

.DELETE_ON_ERROR:

# Local Variables:
# mode: makefile-gmake
# End:
