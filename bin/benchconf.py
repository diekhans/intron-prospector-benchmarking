"""Dataset catalog in conf/datasets.tsv, shared by the benchmark programs."""
import os.path as osp
from pycbio.sys import cli
from pycbio.tsv import TsvReader, TsvRow

BENCH_DIR = osp.dirname(osp.dirname(osp.abspath(__file__)))
DATASETS_TSV = osp.join(BENCH_DIR, "conf", "datasets.tsv")

DATASET_TYPES = {"min_intron": int, "max_intron": int, "star_sj_overhang_min": int}


class Dataset(TsvRow):
    """one row of conf/datasets.tsv; a relative path in the file is relative to
    the top of this repository, not to the current directory"""

    def _resolve(self, path):
        return path if osp.isabs(path) else osp.join(BENCH_DIR, path)

    @property
    def bam_path(self):
        return self._resolve(self.bam)

    @property
    def sj_out_tab_path(self):
        return self._resolve(self.sj_out_tab)

    @property
    def has_genome(self):
        return self.genome != ""

    @property
    def genome_path(self):
        return self._resolve(self.genome)

    @property
    def genome_index_paths(self):
        "faidx index, plus the bgzf block index when the FASTA is compressed"
        if self.genome_path.endswith(".gz"):
            return [self.genome_path + ".fai", self.genome_path + ".gzi"]
        return [self.genome_path + ".fai"]


def load_datasets():
    return {ds.name: ds for ds in TsvReader(DATASETS_TSV, rowClass=Dataset,
                                            typeMap=DATASET_TYPES)}


def check_dataset_name(parser, name):
    "name the catalog in the usage error rather than failing later with a KeyError"
    datasets = load_datasets()
    if name not in datasets:
        parser.error(f"unknown dataset '{name}'; conf/datasets.tsv has: "
                     + ", ".join(datasets.keys()))


def check_inputs(dataset, paths):
    "fail before a long run rather than part way through it"
    missing = [p for p in paths if not osp.exists(p)]
    if missing:
        raise cli.PycbioException(f"dataset {dataset.name} inputs not found, "
                                  "correct conf/datasets.tsv: " + ", ".join(missing))
