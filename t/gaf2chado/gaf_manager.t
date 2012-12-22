
use Test::Exception;
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Load::Command::ebiGaf2dictyChado'); }

describe 'A GAF manager' => sub {
    my ( $gaf_manager, $gaf_row, @annotations );
    before all => sub {
        $gaf_manager = GAFManager->new;
        $gaf_row
            = "dictyBase\tDDB_G0267376\tacrA\t\tGO:0004016\tPMID:10556070\tIDA\t\tF\t\t\t\ttaxon:44689\t20050513\tSGD\t\t";
        @annotations = $gaf_manager->parse($gaf_row);
    };
    it 'should have schema attribute' => sub {
        has_attribute_ok( $gaf_manager, $_ )
            for
            qw/schema cvterm_qualifier cvterm_with_from cvterm_assigned_by cvterm_date/;
    };
    it 'schema should not have be initialized' => sub {
        isnt( $gaf_manager->schema, 'Bio::Chado::Schema' );
    };
    it 'should have method' => sub {
        can_ok( $gaf_manager, $_ ) for qw/parse get_gene_ids/;
    };
	#it 'parse should return an array' => sub {
	#    isa_ok( @annotations, 'Array' );
	#};
    it 'elements in array returned by parser should be of type Annotation' =>
        sub {
        isa_ok( $annotations[0], 'Annotation' );
        };
};
runtests unless caller;
