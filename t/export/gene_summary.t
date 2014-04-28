
package TestGeneSummary;

use Moose;
with 'Modware::Role::Command::WithMediaWikiFormatter';

package main;

use Test::Exception;
use Test::File;
use Test::More qw/no_plan/;
use Test::Moose::More;

my $test1 = "<summary paragraph_no=\"4162\">

The Roco family consists of multi-domain proteins that share three domains in common: the Roc domain (<u>R</u>as <u>o</u>f <u>c</u>omplex proteins), COR (<u>C</u>-terminal <u>o</u>f <u>R</u>oc), and a kinase
domain. Additionally, all Roco family members contain a leucine-rich repeat (LRR), with the exception of
<locus gene_id=\"DDB_G0267472\" name=\"roco7\"/>.  Other domains found in Roco proteins include WD40 repeats, cNB/CNMP (cyclic
	nucleotide binding), PH (pleckstrin homology), and RGS (regulator of G protein signaling) domains (<reference reference_no=\"1584\">Bosgraaf and Van Haastert 2003</reference>).  Eleven <i>Dictyostelium</i> proteins belong to the Roco family: <locus gene_id=\"DDB_G0291079\" name=\"gbpC\"/>, <locus gene_id=\"DDB_G0273259\" name=\"qkgA-1\"/>, <locus gene_id=\"DDB_G0269250\" name=\"pats1\"/>, <locus gene_id=\"DDB_G0288251\" name=\"roco4\"/>, <locus gene_id=\"DDB_G0294533\" name=\"roco5\"/>, <locus gene_id=\"DDB_G0279417\" name=\"roco6\"/>, <locus gene_id=\"DDB_G0267472\" name=\"roco7\"/>, <locus gene_id=\"DDB_G0286127\" name=\"roco8\"/>, <locus gene_id=\"DDB_G0288183\" name=\"roco9\"/>, <locus gene_id=\"DDB_G0291710\" name=\"roco10\"/>, and <locus gene_id=\"DDB_G0268636\" name=\"roco11\"/>.<br/>
	
	(<reference reference_no=\"145\">van Egmond and van Haastert 2010</reference>)
	 identified developmental defects in roco4- cells  during the transition from mound to fruiting body; prestalk cells produce reduced levels of cellulose, leading to unstable stalks that are unable to properly lift the spore head. (<reference reference_no=\"12376\">Gilsbach, et al. 2013</reference>) solved the structure of Roco4 kinase wild-type, Parkinson disease-related mutants G1179S and L1180T and the structure of Roco4 kinase in complex with the LRRK2 inhibitor H1152. Serine 1187 and serine 1189 were shown to be essential for kinase activity.<br/>
	 <curation_status>Gene has been comprehensively annotated, 15-SEP-2004 KP</curation_status></summary>";

my $eval1
    = "The Roco family consists of multi-domain proteins that share three domains in common: the Roc domain (<u>R</u>as <u>o</u>f <u>c</u>omplex proteins), COR (<u>C</u>-terminal <u>o</u>f <u>R</u>oc), and a kinasedomain. Additionally, all Roco family members contain a leucine-rich repeat (LRR), with the exception of[/gene/DDB_G0267472 roco7]. Other domains found in Roco proteins include WD40 repeats, cNB/CNMP (cyclicnucleotide binding), PH (pleckstrin homology), and RGS (regulator of G protein signaling) domains ([http://www.ncbi.nlm.nih.gov/pubmed/14654223 Bosgraaf and Van Haastert 2003]). Eleven ''Dictyostelium'' proteins belong to the Roco family: [/gene/DDB_G0291079 gbpC], [/gene/DDB_G0273259 qkgA-1], [/gene/DDB_G0269250 pats1], [/gene/DDB_G0288251 roco4], [/gene/DDB_G0294533 roco5], [/gene/DDB_G0279417 roco6], [/gene/DDB_G0267472 roco7], [/gene/DDB_G0286127 roco8], [/gene/DDB_G0288183 roco9], [/gene/DDB_G0291710 roco10], and [/gene/DDB_G0268636 roco11].<br />([http://www.ncbi.nlm.nih.gov/pubmed/20348387 van Egmond and van Haastert 2010]) identified developmental defects in roco4- cells during the transition from mound to fruiting body; prestalk cells produce reduced levels of cellulose, leading to unstable stalks that are unable to properly lift the spore head. ([http://www.ncbi.nlm.nih.gov/pubmed/22689969 Gilsbach, et al. 2013]) solved the structure of Roco4 kinase wild-type, Parkinson disease-related mutants G1179S and L1180T and the structure of Roco4 kinase in complex with the LRRK2 inhibitor H1152. Serine 1187 and serine 1189 were shown to be essential for kinase activity.<br />Gene has been comprehensively annotated, 15-SEP-2004 KP";

my $test = new_ok('TestGeneSummary');
does_ok(
    $test,
    'Modware::Role::Command::WithMediaWikiFormatter',
    'does the MediaWikiFormatter role'
);

# TODO
# Requires Oracle backend
# ok($test->convert_to_mediawiki($test1) eq $eval1, "successfully converted gene summary to mediawiki - 1");
