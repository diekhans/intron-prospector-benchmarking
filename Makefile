# -*- mode: makefile -*-
# Benchmark intron-prospector against STAR SJ.out.tab.
#
# Each dataset is one full pass over a multi-gigabyte BAM, so use `make -j` to
# overlap them.  Datasets and their inputs are in conf/datasets.tsv.
#
#   make calls       run intron-prospector, write output/<ds>.calls.tsv
#   make compare     compare against SJ.out.tab (depends on calls)
#
# One comparison per dataset per filter in ${filters}; bin/sj-compare --help
# lists the filters and what each keeps.

datasets = $(shell tail -n +2 conf/datasets.tsv | cut -f1)
outDir = output

# intron-prospector source tree, which is a separate repository;
# `make prospectorDir=/some/where` to build against another one
prospectorDir = ../intronProspector
prospector = ${prospectorDir}/bin/intron-prospector

# SJ.out.tab of the dataset in $*, looked up at recipe time
sjOutTab = $$(awk -F'\t' -v name=$* 'NR>1 && $$1==name{print $$3}' conf/datasets.tsv)

# bin/sj-compare filters, each applied to both sides
filters = raw filt_similar

# compare only chr1..chr22, chrX, chrY, chrM; `make compareOpts=` to include
# scaffolds, patches, alts and spike-ins
compareOpts = --main-chroms-only

.PHONY: all
all: compare

.PHONY: calls
calls: ${datasets:%=${outDir}/%.calls.tsv}

.PHONY: compare
compare: $(foreach f,${filters},${datasets:%=${outDir}/%.$f.summary.tsv})

${outDir}/%.calls.tsv: bin/run-prospector conf/datasets.tsv ${prospector}
	./bin/run-prospector --prospector=${prospector} $* $@

# one pattern rule per filter, with the dataset as the stem
define compareRule
${outDir}/%.$(1).compare.tsv.gz ${outDir}/%.$(1).summary.tsv: ${outDir}/%.calls.tsv bin/sj-compare
	./bin/sj-compare --filter=$(1) $${compareOpts} $${sjOutTab} $$< \
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
