# intron-prospector benchmarking

Tools for benchmarking intron-prospector 

This is mostly for intron-prospector developers and not geared for general use

Compares the junctions `intron-prospector` calls from a STAR BAM against the
`SJ.out.tab` STAR wrote from the same alignment run.

## Running

```
make -j                                     # one job per dataset
```

Each dataset is one pass over a 14-22 GB BAM.

The binary under test is `${prospectorDir}/bin/intron-prospector`, where
`prospectorDir` defaults to `../intronProspector`, the intron-prospector source
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
  `--alignIntronMax 500000`, `--outSAMstrandField intronMotif` so the BAM carries XS.
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

- `<ds>.calls.tsv` intron-prospector `--intron-calls` output
- `<ds>.<filter>.compare.tsv.gz` one row per junction in the union of the two
  sets, `found` is `both`, `star` or `prospector`
- `<ds>.<filter>.summary.tsv` `section`, `metric`, `star`, `prospector`, `value`
  rows; the `params` section records which filter produced the file

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

## Reasons the two legitimately differ

- STAR applies `--outSJfilterOverhangMin` (default 30 12 12 12, by motif),
  `--outSJfilterCountUniqueMin` / `CountTotalMin` (3 1 1 1),
  `--outSJfilterDistToOtherSJmin` and `--outSJfilterIntronMaxVsReadN`
  (50000 100000 200000) to `SJ.out.tab` only, not to the BAM. A long intron with
  few supporting reads is dropped from the tab while its alignment stays in the BAM.
- Junctions in the annotation bypass those filters, so `SJ.out.tab` contains
  rows with overhang 1.
- STAR column 9 is the maximum over reads of `min(left, right)`;
  `max_left_overhang` and `max_right_overhang` are independent maxima that can
  come from different reads, so `ip_anchor` is an upper bound on STAR's value.
- For paired-end data, STAR counts a fragment once when both mates cross a
  junction; intron-prospector counts each alignment. Check
  `shared_read_sums` before reading per-junction count differences as a defect.
- intron-prospector drops secondary alignments (`junction_qc` in
  `src/junctions_extractor.cc` of the intronProspector tree), while `SJ.out.tab` counts them in column 8.  A
  junction crossed only by secondary alignments is therefore STAR-only: 13,939
  of WTC11's 18,178 STAR-only junctions have `uniq_count` 0.
- `uniq`/`multi` are not the same partition: intron-prospector also has
  `unsure_mapped_count` for alignments with no NH tag or a discordant or
  partially mapped pair.
