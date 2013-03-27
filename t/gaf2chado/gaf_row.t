
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Loader::GAF::Row'); }

describe 'A GAF row object' => sub {
    my $row;
    before all => sub {
        $row = Modware::Loader::GAF::Row->new;
    };
    it 'should have attributes' => sub {
        has_attribute_ok( $row, $_ )
            for
            qw/db gene_id gene_symbol qualifier go_id db_ref evidence_code with_from aspect taxon date assigned_by/;
    };
    it 'should have required identifiers' => sub {
        has_attribute_ok( $row, $_ )
            for qw/feature_id cvterm_id pub_id cvterm_id_evidence_code/;
    };
    it 'should have ArrayRefs for additional identifiers' => sub {
        has_attribute_ok( $row, $_ ) for qw/dbxrefs pubs/;
        isa_ok( $row->$_, 'ARRAY' ) for qw/dbxrefs pubs/;
    };
    it 'should have subroutine' => sub {
        can_ok( $row, 'is_valid' );
    };
    it 'should NOT be a valid annotation' => sub {
        isnt( $row->is_valid(), 1, 'Annotation NOT valid' );
    };
    it 'should be a valid annotation' => sub {
        $row->cvterm_id(1234567);
        $row->pub_id(192837465);
        $row->cvterm_id_evidence_code(987654321);
        is( $row->is_valid(), 1, 'Valid annotation' );
    };

};
runtests unless caller;
