# default probe-design parameters (in case they're not supplied by the user)
probe_length := 52
tiling_step := 10
flank_length := 34

chromosomes = $(shell seq 1 22) X Y

# input/output directories
raw_data_dir := ./raw_data
clean_data_dir := ./clean_data
output_dir := ./output
figs_dir := ./figs
scripts_dir := ./scripts
tmp_dir := ./tmp
DIRS := $(raw_data_dir) $(clean_data_dir) $(output_dir) $(figs_dir) $(tmp_dir)

# data files produced by the probe-design scrip
final_probe_coords := $(output_dir)/final_probes_$(tiling_step)bp_tiling.bed.gz
final_probe_seqs := $(output_dir)/final_probes_seqs_$(tiling_step)bp_tiling.txt.gz
probe_coords_unfiltered := $(tmp_dir)/probes_$(tiling_step)bp_tiling_unfiltered.bed.gz
unique_regions := $(clean_data_dir)/unique_regions.bed.gz
probe_count := $(tmp_dir)/probe_count_$(tiling_step)bp_tiling.txt
merged_final_probes := $(tmp_dir)/merged_final_probes_$(tiling_step)bp_tiling.bed.gz
merged_unfiltered_probes := $(tmp_dir)/merged_unfiltered_probes_$(tiling_step)bp_tiling.bed.gz
intersect_with_trf := $(tmp_dir)/intersect_with_trf_$(tiling_step)bp_tiling.bed.gz

# input files
ref_genome := /mnt/solexa/Genomes/hg19_evan/whole_genome.fa
hengs_filter := $(raw_data_dir)/hs37m_filt35_99.bed.gz
trf := $(raw_data_dir)/simpleRepeat.bed.gz

script := $(scripts_dir)/calc_probe_coords.py

.PHONY: all probes figures clean

all: probes figures

probes: $(DIRS) $(final_probe_seqs)

figures: $(DIRS) $(probe_count) $(merged_final_probes) $(intersect_with_trf)
	Rscript $(scripts_dir)/generate_figures.R $(tiling_step)

$(final_probe_seqs): $(final_probe_coords)
	bedtools getfasta -fi $(ref_genome) -bed $(final_probe_coords) -fo $@_withNs -tab
	gzip $@_withNs
	zgrep -v "N" $@_withNs | sed 's/$$/CACTGCGG/' | gzip > $@

$(final_probe_coords): $(probe_coords_unfiltered) $(trf)
	bedtools intersect -a $(probe_coords_unfiltered) -b $(trf) -c | \
	    awk '($$4 == 0)' | cut -f1,2,3 | gzip > $@

$(probe_coords_unfiltered): $(unique_regions)
	python3 $(script) \
	    --in_file=$(unique_regions) \
	    --out_file=$@_tmp \
	    --probe_length=$(probe_length) \
	    --tiling_step=$(tiling_step) \
	    --flank_length=$(flank_length)
	sort -k1,1V -k2,2n $@_tmp | gzip > $@
	rm $@_tmp

$(intersect_with_trf): $(merged_unfiltered_probes)
	bedtools intersect -a $(merged_unfiltered_probes) \
	                   -b $(trf) | gzip > $(intersect_with_trf)

$(merged_final_probes): $(final_probe_coords)
	bedtools merge -i $< | gzip > $@

$(merged_unfiltered_probes): $(probe_coords_unfiltered)
	bedtools merge -i $< | gzip > $@

$(probe_count): $(final_probe_coords)
	printf "chr\tprobes\nall\t" > $@
	zcat $< | wc -l >> $@
	for i in $(chromosomes); do \
	    printf "chr$${i}\t" >> $@; \
	    zgrep -w ^$${i} $< | wc -l >> $@; \
	done

# get coordinates of Heng's alignability regions that don't overlap TRF
$(unique_regions): $(hengs_filter) $(trf)
	bedtools subtract -a $(hengs_filter) -b $(trf) | gzip > $@

# create a local copy of Heng's alignability filter
$(hengs_filter):
	read -p "MPI login: " USERNAME; \
	scp $${USERNAME}@bio23.eva.mpg.de:/mnt/454/HCNDCAM/Hengs_Alignability_Filter/hs37m_filt35_99.bed.gz $@

# download tandem repeat filter from UCSC and extract only coordinate columns
$(trf):
	curl http://hgdownload.cse.ucsc.edu/goldenPath/hg19/database/simpleRepeat.txt.gz | \
	gunzip | \
	cut -f2,3,4 | \
	sed 's/^chr//' > $@_tmp
	bedtools merge -i $@_tmp | gzip > $@
	rm $@_tmp

# download table of chromosome lengths from UCSC
$(clean_data_dir)/chrom_lengths.txt:
	curl http://hgdownload.cse.ucsc.edu/goldenPath/hg19/database/chromInfo.txt.gz | \
	gunzip | \
	cut -f1,2 | \
	grep -w "chr[X,Y,0-9]*" | \
	sort -k1,1V > $@

$(DIRS):
	mkdir $@

clean:
	rm -rf $(DIRS)
