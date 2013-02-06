
use Test::Exception;
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Loader::GAF::Manager'); }

describe 'A GAF manager' => sub {
	#my ( $gaf_manager, $gaf_row, $line );
	#before all => sub {
	#    $gaf_manager = Modware::Loader::GAF::Manager->new;
	#    $line
	#        = "dictyBase\tDDB_G0267376\tacrA\t\tGO:0004016\tPMID:10556070\tIDA\t\tF\t\t\t\ttaxon:44689\t20050513\tSGD\t\t";
	#    $gaf_row = $gaf_manager->parse($line);
	#};
	#it 'should have attributes' => sub {
	#    has_attribute_ok( $gaf_manager, $_ ) for qw/schema logger/;
	#};
	it 'has empty test' => sub {
		is(1, 1);
	}

    # TODO - Test for handling multiple dbxrefs & pubs
    # TODO - Test for querying EBI
    # TODO - Test for prune
    # TODO - Parsing GAF
};
runtests unless caller;
