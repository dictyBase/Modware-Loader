
use Test::Exception;
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Load::Command::ebiGaf2dictyChado'); }

describe 'A GAF manager' => sub {
    my $gaf_manager;
    before all => sub {
        $gaf_manager = GAFManager->new;
    };
    it 'should have schema attribute' => sub {
        has_attribute_ok( $gaf_manager, 'schema' );
    };
    it 'should have method' => sub {
        can_ok( $gaf_manager, $_ ) for qw/parse get_gene_ids/;
    };
};
runtests unless caller;
