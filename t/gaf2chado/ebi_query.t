
use Test::Exception;
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Load::Command::ebiGaf2dictyChado'); }

describe "An EBI query object" => sub {
    my $ebi_query;
    before all => sub {
        $ebi_query = EBIQuery->new;
    };
    it 'should be an object of EBIQuery' => sub {
        isa_ok( $ebi_query, 'EBIQuery' );
    };
    it 'should have attributes' => sub {
        has_attribute_ok( $ebi_query, $_ ) for qw/ebi_base_url ua format db/;
    };
    it 'should have method' => sub {
        can_ok( $ebi_query, 'query_ebi' );
    };

    #it 'should die' => sub {
    #$ebi_query->format('');
    #$ebi_query->db('');
    #dies_ok( sub { $ebi_query->query_ebi('') } );
    #};

    it 'should return GAF as response' => sub {
        lives_ok( sub { $ebi_query->query_ebi('DDB_G0272616') } );
    };

};
runtests unless caller;

