# intron-prospector benchmarking

Tools for benchmarking intron-prospector 

This is mostly for intron-prospector developers and not geared for general use

Compares three sets of junctions over one STAR BAM:

- what `intron-prospector` calls from the BAM
- what STAR itself wrote in `SJ.out.tab` during the alignment run
- what flair's `junctions_from_sam` calls from the same BAM

## Running

```
make -j                                     # one job per dataset
```

Each dataset is three passes over a 14-22 GB BAM: two intron-prospector runs
and one junctions_from_sam run.
`junctions_from_sam` reads the BAM with pysam and converts each record back to a
SAM line, around 28,000 alignments a second, so WTC11's 256 million alignments
take about two and a half hours.

The binary under test is `${prospectorDir}/bin/intron-prospector`, where
`prospectorDir` defaults to `../intron-prospector`, the intron-prospector source
tree checked out beside this one.  The Makefile builds it if it is missing.
Use `make prospectorDir=/some/where` for another checkout.

`data/` holds the genome FASTAs and is not in git.  A bgzip-compressed FASTA
needs both the `.fai` and the `.gzi` that `samtools faidx` writes.

Run in the `markd` conda environment, which supplies samtools and a `python3`
with pycbio and pipettor importable.

## Datasets

`conf/datasets.tsv`, one row per dataset.  A relative path is relative to this
directory, not to the current directory:

| column                 | meaning                                                                |
|------------------------|------------------------------------------------------------------------|
| `name`                 | dataset name, used for output file names                               |
| `bam`                  | STAR `Aligned.sortedByCoord.out.bam`                                   |
| `sj_out_tab`           | `SJ.out.tab` from the same STAR run                                    |
| `genome`               | FASTA indexed by `samtools faidx`, or empty for no splice site calling |
| `min_intron`           | STAR `--alignIntronMin` for that run                                   |
| `max_intron`           | STAR `--alignIntronMax` for that run                                   |
| `star_sj_overhang_min` | STAR `--alignSJoverhangMin` for that run, reference only               |

Current rows:

- A549: CCLE SRR8616017, STAR 2.7.11b, GRCh38 primary + GENCODE v49, paired end.
  `--alignIntronMax 500000`, `--outSAMstrandField intronMotif` so the BAM has XS tags.
  Genome is `data/GRCh38.p14.genome.fa.gz`.  The STAR index that BAM was built
  against is not readable, so this is the GENCODE release rather than that exact
  index input; the BAM names the 169 scaffolds by bare accession, `GL000008.2`
  style, and any name the FASTA lacks is dropped by `--skip-missing-targets`.
- WTC11: LRGASP Illumina, STAR 2.5.3a, GRCh38 + SIRV/ERCC, paired end.
  `--alignIntronMax 1000000`, `--alignSJoverhangMin 8`, `--outFilterType BySJout`,
  `--twopassMode Basic`. No XS in the BAM, so strand comes from the genome.
  Tab is `lrgasp-WTC11-illumina-all-STARSJ.out.tab`, written beside the BAM by the
  run that produced it.  Not `lrgasp-wtc11/WTC11_all.SJ.out.tab`, which is three
  runs' tabs end to end, 809,210 rows for 390,424 junctions.

## How intron-prospector is run

`bin/run-prospector` disables every intron-prospector filter so the calls file
holds everything in the BAM:

- `--min-confidence-score=0.0`, `--sj-filter=all`, `--min-anchor-length=1`
- `--min-intron-length` / `--max-intron-length` set from the STAR run

`bin/sj-compare` filters afterwards, which avoids a second pass over the BAM.

### Runs

Which alignments intron-prospector reads is decided during the pass, so it
cannot be deferred to `bin/sj-compare` the way the thresholds are.  Each
dataset therefore gets one pass per run named in the Makefile's `runs`, each
writing `output/<ds>.<run>.calls.tsv`:

- `base`, the default, which skips the alignments flagged by the sequencer's
  chastity filter, QC fail, along with duplicates and secondary alignments
- `qcfail`, `--include=qcfail`, which counts the QC fail alignments
- `secondary`, `--include=qcfail,secondary`, which also counts the other loci of
  a multi-mapping read

`SJ.out.tab` counts QC fail alignments in both of its count columns and
secondary alignments in the multi-mapping one.  `junctions_from_sam` does not
test the flags at all, so `secondary` is the run whose read set equals its own:
the BAMs have no duplicate flags, and both tools read supplementary alignments.

- `qcfail` is the control for `doc/wtc11-star-only.org`, where QC fail
  alignments account for the WTC11 junctions STAR reports and intron-prospector
  does not.
- `secondary` is the control for `doc/wtc11-flair-only.org`, where secondary
  alignments account for the junctions `junctions_from_sam` reports and
  intron-prospector does not.

## How junctions_from_sam is run

`bin/run-flair-juncs` runs it with `-c 1.0`, the default of both
`junctions_from_sam -c` and `intron-prospector --min-confidence-score`.  Both
are the same statistic, the Shannon entropy of the distinct alignment offsets
supporting a junction, from JuncBASE.  This filtering cannot be deferred the way
intron-prospector's is: `junctions_from_sam` writes only the junctions that pass,
so the flair side of a comparison is never unfiltered.

It is installed in the `flair-mddev` conda environment.  Its shebang names that
environment's python, so the Makefile runs it by absolute path without
activating it, from the `markd` environment the rest of the benchmark runs in.
`make flairJuncs=/some/where/junctions_from_sam` for another install.

Its output is a headerless BED6 per junction: the interval is the intron,
`score` is the number of supporting alignments capped at 1000, and `strand`
comes from the `XS:A:` tag, or is `.` when the BAM has none.

## Comparison

`bin/sj-compare` keys junctions on (chrom, intron start, intron end), converting
`SJ.out.tab` columns 2 and 3 from 1-based inclusive to 0-based half open.

### raw and filt_XX

One comparison is run per filter named in the Makefile's `filters`, each writing
its own output files.  A filter is applied to both sides, so a junction dropped
on one side is dropped on the other, and what is left is closer to real
disagreement than to a difference in what each tool reports.  `bin/sj-compare
--help` lists the filters; they are defined in `FILTERS` in that script.

- `raw` keeps everything both sides report.  The STAR side is already filtered
  by STAR, so this mode mostly measures what `SJ.out.tab` leaves out.
- `filt_similar` keeps junctions with an anchor of at least 12 and at least one
  uniquely mapped read.  The anchor threshold is STAR's
  `--outSJfilterOverhangMin` for canonical junctions; the unique-read threshold
  drops junctions seen only on multi-mapping alignments, which intron-prospector
  does not report because it skips secondary alignments.
- `filt_flair` keeps junctions with a confidence of at least 1.0, which is what
  `junctions_from_sam` applied when it wrote its BED.  This is the filter under
  which the intron-prospector and flair sets are comparable.

The flair side is not filtered by `bin/sj-compare`: `junctions_from_sam` reports
neither an anchor nor a unique read count, and its entropy filter was applied
when it ran.  `--flair-confidence` states the `-c` it was run with, 1.0 by
default, and a filter that asks for more than that is an error rather than a
comparison with the flair side the less filtered one.

Adding a filter means one entry in `FILTERS` and its name in the Makefile's
`filters`.

`--main-chroms-only` restricts both sides to chr1 through chr22, chrX, chrY and
chrM, leaving out scaffolds, patches, alts and spike-ins.  The Makefile passes
it through `compareOpts`; `make compareOpts=` includes everything.  On by
default for two reasons:

- the two assemblies use different names for the same scaffolds, UCSC form in
  the WTC11 FASTA and GENCODE accessions in the A549 BAM
- the WTC11 assembly adds 114 SIRV and ERCC spike-in sequences, which are not
  part of either genome

No filter makes the sides identical.  STAR's overhang threshold is per motif, 30
for non-canonical and 12 otherwise, `min_anchor` is one number for all motifs,
annotated junctions bypass STAR's own filters, and the two anchor measures are
not the same quantity, see below.

A junction occurring more than once in either input is an error.  A STAR run
writes each junction once, so a repeat means the tab is several runs' tabs
concatenated, whose counts are over different reads than the BAM holds.

Outputs in `output/`:

- `<ds>.<run>.calls.tsv` intron-prospector `--intron-calls` output
- `<ds>.flair.bed` `junctions_from_sam` output, one per dataset, since it reads
  every alignment whatever the run
- `<ds>.<run>.<filter>.compare.tsv.gz` one row per junction in the union of the
  sets; `found` names the sides that have it, joined by `+`, such as `star`,
  `star+prospector` or `star+prospector+flair`
- `<ds>.<run>.<filter>.summary.tsv` `section`, `metric`, `star`, `prospector`,
  `flair`, `value` rows; the `params` section records which filter produced the
  file, and the file name which run

Summary sections:

- `totals` junctions per side, `shared` by every side, and `only` for the
  junctions one side has and no other does
- `overlaps` the three pairwise intersections, from which, say, the junctions
  flair has and intron-prospector does not can be read off
- `only_by_*` breakdowns of each side's exclusive junctions; flair has a read
  count only
- `shared_*` STAR against intron-prospector over the junctions those two share,
  whatever else is in the comparison
- `shared_pros_flair_count` read counts over the junctions intron-prospector and
  flair share, which the cap at 1000 and the different alignment sets make a
  rough comparison

In the summary, `star` and `prospector` hold the same metric measured on each
side and `value` holds metrics that are not per-tool, such as the number of
junctions on which the two agree.  An empty cell means the metric does not exist
for that side: STAR has no counterpart to `unsure_mapped_count`, and
intron-prospector has no annotation to report junctions against.

`ip_anchor` is `min(max_left_overhang, max_right_overhang)`, the nearest
equivalent intron-prospector reports to `SJ.out.tab` column 9.

## Investigations

- `doc/wtc11-star-only.org`: why 20 of 20 sampled WTC11 `SJ.out.tab` junctions
  are absent from the calls.  STAR copies the Illumina chastity filter into SAM
  flag 0x200 and counts those alignments; intron-prospector skips them.
- `doc/wtc11-flair-only.org`: why `junctions_from_sam` has 14,763 WTC11
  junctions neither other tool has under `filt_similar`.  Half are dropped from
  the other two sides by the filter, half are supported only by secondary
  alignments, and all of them come from multi-mapping reads.

## How the three tools differ

All three report introns from the same STAR BAM.  What differs is which
alignments each one reads and which junctions each one writes, not how well
each finds an intron.  The sections below give every difference; these are the
ones that produce most of them.  `doc/tool-differences.org` says the same at
more length, for a reader who is not running the benchmark.

### STAR against intron-prospector

- STAR writes `SJ.out.tab` while aligning and filters it by overhang and count,
  with annotated junctions bypassing the filters; intron-prospector reads the
  finished BAM and filters nothing.
- STAR counts QC fail and secondary alignments; the calls skip both unless
  `--include` names them.
- Both count a read once per junction, a pair whose mates both cross it
  included.
- The tab's overhang, its coordinates and its annotated column have no exact
  counterpart in the calls.
- WTC11, same read set, no filters: 383,247 junctions against 383,256, 14
  differ.  Counts match on 99.1% of the 383,244 shared and are never higher in
  the calls; A549 matches on 99.75% of 946,897.  The rest is STAR counting
  alignments whose anchor holds an insertion, deletion or clip.

### junctions_from_sam against intron-prospector

- Both read the finished BAM and take introns from the CIGAR.
- It does not test the SAM flags, so it reads QC fail, secondary and
  supplementary alignments.
- It skips any alignment with an insertion, deletion or clipping, which is why
  it reports the fewest junctions, 292,346 against 383,256.
- It counts each alignment, so a pair whose mates both cross a junction counts
  twice; it applies its entropy threshold while running, so its output is never
  unfiltered; its BED count stops at 1000.
- WTC11, same read set, no filters: the calls hold all 292,346 junctions it
  reports.  Over the 281,159 shared junctions under the cap, counts are equal
  on 19.6% and lower in the calls on 57.9%, 5.2% lower at the median.  One pass
  takes 4 minutes against its 2.5 hours.

## Where intron-prospector differs from STAR

None of these is a defect in either tool.  They are the reasons two correct
tools report different junctions from one BAM.

### Which alignments are counted

- STAR counts the alignments the sequencer's chastity filter flagged, SAM flag
  0x200; intron-prospector skips them unless `--include=qcfail`.  This is the
  largest single cause on a dataset whose reads are flagged: see the `qcfail` run
  above and `doc/wtc11-star-only.org`.
- STAR counts secondary alignments in column 8; intron-prospector skips them
  unless `--include=secondary`.  A junction crossed only by secondary
  alignments is therefore STAR-only.
- `uniq` and `multi` are not the same partition on the two sides:
  intron-prospector also has `unsure_mapped_count`, for an alignment with no NH
  tag, a discordant pair, or a mate that did not map.  STAR has no counterpart.
- Both count a read once per junction, so the counts are comparable.  What is
  left is the anchor difference: STAR counts an alignment whose anchor holds an
  insertion, deletion or clip, intron-prospector rejects it, and the calls are
  then lower.  Read `shared_read_sums` before taking a per-junction count
  difference for a defect.

### Which junctions are written

- STAR applies `--outSJfilterOverhangMin` (default 30 12 12 12, by motif),
  `--outSJfilterCountUniqueMin` / `CountTotalMin` (3 1 1 1),
  `--outSJfilterDistToOtherSJmin` and `--outSJfilterIntronMaxVsReadN`
  (50000 100000 200000) to `SJ.out.tab` only, not to the BAM.  A long intron
  with few supporting reads is dropped from the tab while its alignment stays
  in the BAM, so intron-prospector reports it.
- Junctions in the annotation bypass those filters, so `SJ.out.tab` holds rows
  with an overhang of 1 that no threshold on the calls side will match.
- intron-prospector filters what the BAM holds, with `--min-anchor-length`,
  `--min-intron-length`, `--max-intron-length`, `--min-confidence-score`,
  `--min-read-count` and `--sj-filter`.  `bin/run-prospector` turns all of them
  off so `bin/sj-compare` can apply them afterwards.

### Columns that do not line up

- STAR column 9 is the maximum over reads of `min(left, right)`.
  `max_left_overhang` and `max_right_overhang` are independent maxima that can
  come from different reads, so `ip_anchor`, the smaller of the two, is an
  upper bound on STAR's value rather than the same quantity.
- `SJ.out.tab` columns 2 and 3 are the first and last intron base, 1-based
  inclusive; the calls are 0-based half open.  `bin/sj-compare` converts.
- STAR classifies the intron motif itself.  intron-prospector reports
  `splice_sites` only with `--genome-fasta`, and `--main-chroms-only` exists
  because the two assemblies name scaffolds differently.
- STAR marks junctions that are in the annotation, column 6.  There is no such
  column on the calls side.
- `confidence` has no counterpart in `SJ.out.tab`.

## Where junctions_from_sam differs

- It skips any alignment whose CIGAR holds an insertion, deletion, soft clip or
  hard clip, printing one message per kind.  On an Illumina STAR BAM that drops
  a large share of the alignments, and with them junctions supported only by
  clipped reads or reads with an indel.
- It does not test the SAM flags, so it counts secondary, supplementary and QC
  fail alignments.  Its read set is that of the `secondary` run.
- It counts each alignment, so a pair whose mates both cross one junction
  counts twice, where `SJ.out.tab` and the calls count the read once.
- It applies its entropy threshold while running, so the flair side of a
  comparison is never unfiltered.
- It caps its score at 1000 supporting alignments, so a count of 1000 is a
  floor, not a count.
