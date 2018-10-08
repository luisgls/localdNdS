#!/bin/bash
##Luis Zapata 2017. Identify negative selection in cancer genes

###Important to edit before running
####Hardcode where genome and fasta file are
#GENOME=data/hg19.genome
#FASTA=data/hg19.fasta
SUPA=data 
TRANS=data/ensemble_transcriptID.fasta
TMP=tmp

##Check arguments before running
if (($# < 8));  then
	echo "Please provide the four mandatory arguments and optionals (default in parenthesis)
	 -i Annotation - VEP annotated file
         -b Bed file - Provide bed file with Protein coordinates named by Transcript (ENSTXXXXXX 123 135)
         -o Results - Directory
         -n Name - Give name to results
         -r (target)/random - (optional, to calculate a dNdS value for a random region similar to the target)
         -e (true)/false - exclude driver genes (optional, to calculate a dNdS value excluding driver genes)
"
	exit 1
fi	

##Check all arguments
while getopts "i:b:o:n:r:e:" opt; do
    case $opt in
	i)
	echo "#-i was triggered, Parameter: $OPTARG" >&2 
	FILE=$OPTARG
	;;
        o)
        echo "#-o was triggered, Parameter: $OPTARG" >&2
        OUT=$OPTARG
        ;;
        b)
        echo "#-b was triggered, Parameter: $OPTARG" >&2
        BED=$OPTARG
        ;;
        n)
        echo "#-n was triggered, Parameter: $OPTARG" >&2
        NAME=$OPTARG
        ;;
        r)
        echo "#-r was triggered, Parameter: $OPTARG" >&2
        MODEL=$OPTARG
        ;;
        e)
        echo "#-e was triggered, Parameter: $OPTARG" >&2
        DRIVER=$OPTARG
        ;;
	\?)
	echo "#Invalid option: -$OPTARG" >&2
	exit 1
	;;
	:)
	echo "#Option -$OPTARG requires an argumrent." >&2
	exit 1
	;;	
    esac
done

###Get list of transcripts, and filter those transcripts from list of proteins and cds to get the length
cut -f1 $BED | sort -u | fgrep -w -f - $SUPA/ensemble_transcript_protein.length > $TMP/$NAME.protein_length_filt.txt
cut -f1 $BED | sort -u | fgrep -w -f - $SUPA/ensemble_transcript.length > $TMP/$NAME.transcript_length_filt.txt

##Randomize protein positions of target region
if [[ $MODEL = "random" ]];
    then
        echo "#Option random enabled, running dN/dS for matching target region length"
        ## Define excluded regions for the randomization
        ## Excluding region to be tested
        rm $TMP/$NAME.exclusion.ori
        cut -f1,2,3 $BED > $TMP/$NAME.exclusion.ori
        ## Excluding the first two aminoacids of the transcript to be tested
        cut -f1 $BED | awk '{OFS="\t"}{print $1,0,2}' | sortBed -i stdin  >> $TMP/$NAME.exclusion.ori
        
        ##Sort excluded regions file
        sortBed -i $TMP/$NAME.exclusion.ori > $TMP/$NAME.exclusion.bed
        bedtools shuffle -i $BED -g $TMP/$NAME.protein_length_filt.txt -excl $TMP/$NAME.exclusion.bed -chrom > $TMP/$NAME.epitopes.ori2
else
	##If non randomized
        sort -u $BED > $TMP/$NAME.epitopes.ori2    
        echo "#Calculating dN/dS for target region"
fi

##Exclude positively selected genes
if [[ $DRIVER = "false" ]];
    then
        echo "#Option excluding driver disabled"
        cp $TMP/$NAME.epitopes.ori2 $TMP/$NAME.epitopes.bed
else
    ##
    fgrep -w -v -f $SUPA/genes2exclude.txt $TMP/$NAME.epitopes.ori2 > $TMP/$NAME.epitopes.bed
    echo "#Option excluding driver enabled (default)"
fi

##Get the complement for the rest of the protein (nonepitope) and make sure we dont look into other proteins not present in the epitope file
sortBed -i $TMP/$NAME.epitopes.bed | complementBed -i stdin -g $TMP/$NAME.protein_length_filt.txt > $TMP/$NAME.intra_epitopes_prot.tmp
cut -f1 $TMP/$NAME.epitopes.bed | sort -u | fgrep -w -f - $TMP/$NAME.intra_epitopes_prot.tmp > $TMP/$NAME.intra_epitopes_prot.bed

## transform protein coordinates to CDS coordinates and get the complement at the transcript level
awk '{OFS="\t"}{print $1,($2*3)-3,$3*3,$0}' $TMP/$NAME.epitopes.bed > $TMP/$NAME.epitopes_cds.bed
sortBed -i $TMP/$NAME.epitopes_cds.bed | complementBed -i stdin -g $TMP/$NAME.transcript_length_filt.txt > $TMP/$NAME.intra_epitopes.tmp
cut -f1 $TMP/$NAME.epitopes.bed | sort -u | fgrep -w -f - $TMP/$NAME.intra_epitopes.tmp > $TMP/$NAME.intra_epitopes_cds.bed

##get transcript sequence or epitopes and nonepitopes
## get fasta sequence for each epitope peptide
bedtools getfasta -fi $TRANS -bed $TMP/$NAME.epitopes_cds.bed -fo $TMP/$NAME.epitopes_cds.fasta
bedtools getfasta -fi $TRANS -bed $TMP/$NAME.intra_epitopes_cds.bed -fo $TMP/$NAME.intra_epitopes_cds.fasta

#List of transcript:regions to estimate number of sites
grep ">" $TMP/$NAME.epitopes_cds.fasta | sed 's/>//g' > $TMP/$NAME.listA
grep ">" $TMP/$NAME.intra_epitopes_cds.fasta | sed 's/>//g' > $TMP/$NAME.listB

echo "#Estimate all theoretically possible 7 substitutions in target and non-target regions"
perl scripts/calculate_sites_signaturesLZ.pl $TMP/$NAME.epitopes_cds.fasta $TMP/$NAME.listA > $TMP/$NAME.listA.sites
perl scripts/calculate_sites_signaturesLZ.pl $TMP/$NAME.intra_epitopes_cds.fasta $TMP/$NAME.listB > $TMP/$NAME.listB.sites

#Sum all possible accross the target region and the non-target region
awk '{print "test_"$2"_"$3"\t0\t1\t"$0}' $TMP/$NAME.listA.sites | sortBed -i stdin |
mergeBed -i stdin -c 7,8 -o sum,sum | cut -f1,4,5 > $TMP/$NAME.listA.totalsites
awk '{print "test_"$2"_"$3"\t0\t1\t"$0}' $TMP/$NAME.listB.sites | sortBed -i stdin |
mergeBed -i stdin -c 7,8 -o sum,sum | cut -f1,4,5 > $TMP/$NAME.listB.totalsites

echo "#Make correction based on total sites" 
perl scripts/correct_update_epitope_sites.pl $TMP/$NAME.listA.totalsites $SUPA/all_ttype_freqs.txt $SUPA/all_ttype_ssb7_freqs.txt > $TMP/$NAME.final_corrected_matrix_A.txt
perl scripts/correct_update_epitope_sites.pl $TMP/$NAME.listB.totalsites $SUPA/all_ttype_freqs.txt $SUPA/all_ttype_ssb7_freqs.txt  > $TMP/$NAME.final_corrected_matrix_B.txt

##By frequency of mutations
awk '{NA+=$8}{NS+=$9}END{print NA"\t"NS}' $TMP/$NAME.final_corrected_matrix_A.txt > $TMP/$NAME.epitope_NaNs.txt
awk '{NA+=$8}{NS+=$9}END{print NA"\t"NS}' $TMP/$NAME.final_corrected_matrix_B.txt > $TMP/$NAME.nonepitope_NaNs.txt


#####Get variant counts from vep annotated file, split into silent and nonsilent
##silent
egrep -v -e '#|intergenic_variant|UTR|downstream|intron|miRNA|frameshift|non_coding|splice_acceptor_variant|splice_donor_variant|upstream|incomplete|retained|\?' $FILE | grep -w synonymous_variant |
awk '{if(length($3)>1){}else{print}}' | cut -f4,5,7,10,89 -  | sed 's/\//\t/g' | awk '{print $2"\t"$4"\t"$4"\t"$3}' |  egrep -v -w -e "coding_sequence_variant" |  grep -v "ENSEMBLTRANSCRIPT" > $TMP/$NAME.silent.bed

##nonsilent
egrep -v -e '#|intergenic_variant|UTR|downstream|intron|miRNA|frameshift|non_coding|splice_acceptor_variant|splice_donor_variant|upstream|incomplete|retained|\?' $FILE | grep -w -v synonymous_variant |
awk '{if(length($3)>1){}else{print}}'  |cut -f4,5,7,10,89 -  | sed 's/\//\t/g' | awk '{print $2"\t"$4"\t"$4"\t"$3}' |  egrep -v -w -e "coding_sequence_variant" | grep -v "ENSEMBLTRANSCRIPT" > $TMP/$NAME.nonsilent.bed

##missense only
egrep -v -e '#|intergenic_variant|UTR|downstream|intron|miRNA|frameshift|non_coding|splice_acceptor_variant|splice_donor_variant|upstream|incomplete|retained|\?' $FILE | grep -w -v synonymous_variant | grep -w missense_variant |
awk '{if(length($3)>1){}else{print}}'  |cut -f4,5,7,10,89 -  | sed 's/\//\t/g' | awk '{print $2"\t"$4"\t"$4"\t"$3}' |  egrep -v -w -e "coding_sequence_variant" | grep -v "ENSEMBLTRANSCRIPT" > $TMP/$NAME.missense.bed

##intronic
grep -v "^#" $FILE | grep -w "intron_variant" | grep -v "splice" | awk -F"\t|_" '{FS="\t|_"}{print $1"_"$7"\t"$2"\t"$2"\t"$3}' > $TMP/$NAME.intronic.bed

##Silent
if [ -s "$TMP/$NAME.silent.bed" ]
then
        sils=`wc -l $TMP/$NAME.silent.bed | awk '{ print $1 }'`
        echo "$sils number of silent mutations in file"
        
else
        echo "file silent mutations empty"
fi

##Nonsilent (nonsense + missense)
if [ -s "$TMP/$NAME.nonsilent.bed" ]
then
        nonsils=`wc -l $TMP/$NAME.nonsilent.bed | awk '{ print $1 }'`
        echo "$nonsils number of nonsilent mutations in file"
        
else
        echo "file nonsilent mutations empty"
fi

##Missense only
if [ -s "$TMP/$NAME.missense.bed" ]
then
        missense=`wc -l $TMP/$NAME.missense.bed | awk '{ print $1 }'`
        echo "$missense number of missense mutations in file"
        
else
        echo "file missense mutations empty"
fi

###ntersect different regions from the protein to calculate dNdS
##Check if counts has value larger than 0
if [ -s "$TMP/$NAME.data_epitopes" ]
then
        rm $TMP/$NAME.data_epitopes
else
        echo "Checking for previous data file."
fi

###Modified from nonsilent to missense to calculate for missense only

intersectBed -b $TMP/$NAME.nonsilent.bed -a $TMP/$NAME.epitopes.bed -wo | awk '{OFS="\t"}{print $1,"1","2",$0}' | sortBed -i stdin | mergeBed -i stdin -c 11 -o count | cut -f1,4 | awk '{print $0"\textra_missense_variant"}' >> $TMP/$NAME.data_epitopes
intersectBed -b $TMP/$NAME.silent.bed -a $TMP/$NAME.epitopes.bed -wo | awk '{OFS="\t"}{print $1,"1","2",$0}' | sortBed -i stdin | mergeBed -i stdin -c 11 -o count | cut -f1,4 | awk '{print $0"\textra_synonymous_variant"}' >> $TMP/$NAME.data_epitopes
intersectBed -b $TMP/$NAME.silent.bed -a $TMP/$NAME.intra_epitopes_prot.bed -wo | awk '{OFS="\t"}{print $1,"1","2",$0}' | sortBed -i stdin | mergeBed -i stdin -c 10 -o count | cut -f1,4 | awk '{print $0"\tintra_synonymous_variant"}' >> $TMP/$NAME.data_epitopes
intersectBed -b $TMP/$NAME.nonsilent.bed -a $TMP/$NAME.intra_epitopes_prot.bed -wo | awk '{OFS="\t"}{print $1,"1","2",$0}' | sortBed -i stdin | mergeBed -i stdin -c 10 -o count | cut -f1,4 | awk '{print $0"\tintra_missense_variant"}' >> $TMP/$NAME.data_epitopes

    innonsil=`intersectBed -b $TMP/$NAME.nonsilent.bed -a $TMP/$NAME.epitopes.bed -wo | wc -l | awk '{ print $1 }'`
    inmissen=`intersectBed -b $TMP/$NAME.missense.bed -a $TMP/$NAME.epitopes.bed -wo | wc -l | awk '{ print $1 }'`
    insil=`intersectBed -b $TMP/$NAME.silent.bed -a $TMP/$NAME.epitopes.bed -wo | wc -l | awk '{ print $1 }'`
    outnonsil=`intersectBed -b $TMP/$NAME.nonsilent.bed -a $TMP/$NAME.intra_epitopes_prot.bed -wo | wc -l | awk '{ print $1 }'`
    outmissen=`intersectBed -b $TMP/$NAME.missense.bed -a $TMP/$NAME.intra_epitopes_prot.bed -wo | wc -l | awk '{ print $1 }'`
    outsil=`intersectBed -b $TMP/$NAME.silent.bed -a $TMP/$NAME.intra_epitopes_prot.bed -wo | wc -l | awk '{ print $1 }'`
    
echo "There are $innonsil non-silent, $inmissen missense-only, and $insil silent mutations in the target region"
echo "There are $outnonsil non-silent, $outmissen missense-only, and $outsil silent mutations in the non-target region"
    
### For intronic
intersectBed -a data/transcript_intron_length.bed -b $TMP/$NAME.intronic.bed -wo | mergeBed -i stdin -c 4,5,6,10,11 -o mode,mode,mode,collapse,count | awk '{print $4"\t"$8/($6+1)"\t"$8"\t"$6}' >  $TMP/$NAME.intronic.rate
    
Rscript scripts/calculateKaKsEpiCorrected_CI_intron.R $TMP/$NAME.data_epitopes $TMP/$NAME.epitope_NaNs.txt $TMP/$NAME.nonepitope_NaNs.txt $TMP/$NAME.intronic.rate > $OUT/$NAME.SSB_dNdS.txt