# SOPRANO: Selection On PRotein ANnotated regiOns
SOPRANO was developed to analyse selection in specific regions of the genome. It uses a VEP annotated file to estimate ON target dN/dS values and OFF target dN/dS values.

## Installation

#### To install first create a directory called SOPRANO and then clone the tool to this directory

```{bash}
mkdir /my/home/directory/SOPRANO
cd /my/home/directory/SOPRANO

git clone https://github.com/luisgls/SOPRANO.git 
```
#### Edit the head of the master script: run_localSSBselection_v3.sh
- Specify the basedirectory of the installation
BASEDIR=/my/home/directory/SOPRANO/

- Copy or link the genome file (e.g. hg19.genome) and the fasta file (e.g. hg19.fasta) to /my/home/directory/SOPRANO/data/

#### Make sure you have your data folder with all necessary files to run SOPRANO
```{bash}
cd data
gzip -d ensemble_transcriptID.fasta.gz
```
#### Now you should be able to run the tool if all the dependencies are met.

### Dependencies
- bedtools 2.26.0 or higher
- R-3.3.3 or higher.
- R library tidyr
- perl 5
- GNU command line tools

#The input for SOPRANO is the same as for SSB_selection, A VEP annotated TAB delimited input file.
- Ensembl variant effect predictor v89 or higher (VEP)

#### Important Notes
- earlier versions of bedtools will not work
- tab encoding should be \t (might be a problem for windows/OSX versions)
- genome file is a two column file specifying the fasta id and the length of the sequence (see how to obtain it at the bottom)
- Restrict your input dataset to chromosomes 1-22 and X and Y. Remove the rest.

## Input file
The input file is the standard output of variant effect predictor using the following command line (by providing to vep the ensembl default input file format)
perl variant_effect_predictor.pl -i input -o input.annotated --cache --all_refseq --assembly GRCh37 --pick --symbol --no_stats --fasta genome.fasta
If you want to filter putative germline variants use the option --plugin ExAC when running VEP. It is important that you restrict your analysis to the list of ensemb transcripts observed in data folder, be aware of updates on the EnsemblID from previous versions.

Example input files can be found on synapse: ID syn11681983

#### Important points before running
  - a) No header needed for input VEP file
  - b) VEP annotated first column must be in the format (chr_pos_ref/alt)
  - c) VEP annotated file must only have chromosomes that are 1,2,3,4...22 or uppercase X,Y
  - d) After you run vep with the option for ExAC frequencies, it would be necessary to remove all variants present in more than 0.1 percent of the population. You could apply the   filter using:
filter_vep -i input.annotated -f "ExAC_AF < 0.1 or not ExAC_AF" --ontology --filter "Consequence is coding_sequence_variant" 
  - e) Be sure that you are using the GNU command line if you are running in a MacOS (https://www.topbug.net/blog/2013/04/14/install-and-use-gnu-command-line-tools-in-mac-os-x/)
  - f) Add dependencies to your path for easy running or hardcode the scripts
  - g) The genome file used in SSB is a two column file that contains the info of the name of the fasta id (column 1) and the length of that sequence (column 2).
  - h) The UNIX system used should be able to recognize \t as a tab separator

## Genomes
To get hg19 fasta genome, you can download it from UCSC:

```{bash
wget http://hgdownload.cse.ucsc.edu/goldenPath/hg19/bigZips/hg19.fa.gz

wget http://hgdownload.cse.ucsc.edu/goldenPath/hg19/bigZips/hg19.chrom.sizes

```

## Output
The output of SOPRANO consists of two lines and the header is:

coverage ON_dnds ON_lowci ON_highci ON_muts OFF_dnds OFF_lowci OFF_highci OFF_muts P-val ON_na ON_NA ON_ns ON_NS OFF_na OFF_NA OFF_ns OFF_NS

coverage = Two options: ExonicOnly and ExonicIntronic. The latest should be used if there are intronic mutations in the mutation file. The algorithm uses intronic mutations to improve the background counts of silent mutations.

ON_dnds =  dN/dS of the target region provided in the bed file

ON_lowci = lower value for the 95% CI of the target

ON_highci = upper value for the 95% CI of the target

ON_muts = number of mutations observed within the target

OFF_dnds = dN/dS of the OFF-target region provided in the bed file

OFF_lowci = lower value for the 95% CI of the OFF-target

OFF_highci = upper value for the 95% CI of the OFF-target

OFF_muts = number of mutations observed within the OFF-target

P-val = P-value estimated from the comparison of the confidence intervals from ON and OFF dN/dS values

ON_na = Observed number of nonsilent mutations ON target

ON_NA = Number of nonsilent sites (corrected) ON target

ON_ns = Observed number of silent mutations ON target

ON_NS = Number of silent sites (corrected) ON target

OFF_na = Observed number of nonsilent mutations OFF target

OFF_NA = Number of nonsilent sites (corrected) OFF target

OFF_ns = Number of silent sites (corrected) OFF target

OFF_NS = Number of silent sites (corrected) OFF target

## Obtain patient specific dN/dS values
To determine the patient specific immunopeptidome you should run the script get_epitope_HLA.pl:

As an example for :
```{bash}
perl scripts/get_epitope_HLA.pl examples/TCGA_hlaTypesTEST.tsv 
```

This will create a command that you can run in a HPC cluster.
In our example case, the command is:

```{bash}
egrep -w -e "HLA-A2402|HLA-A0301|HLA-B1501|HLA-B1801|HLA-C0701|HLA-C0303|" data/allhlaBinders_exprmean1.IEDBpeps.mgd.bed | sortBed -i stdin | mergeBed -i stdin > TCGA-HQ-A5ND.exprmean1.IEDBpeps.SB.epitope.bed
egrep -w -e "HLA-A0205|HLA-A3303|HLA-B5301|HLA-B5301|HLA-C0401|HLA-C0401|" data/allhlaBinders_exprmean1.IEDBpeps.mgd.bed | sortBed -i stdin | mergeBed -i stdin > TCGA-FD-A6TC.exprmean1.IEDBpeps.SB.epitope.bed
```

After obtaining the immunopeptidome file, you can run SOPRANO using the command following:
```{bash}
./run_localSSBselection_v3.sh -i  TCGA-FD-A6TC.annotated -b TCGA-FD-A6TC.exprmean1.IEDBpeps.SB.epitope.bed -n TCGA-FD-A6TC.ssb192 -o results_immuno -m ssb192"; done
```
