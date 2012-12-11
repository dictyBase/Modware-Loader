
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Load::Command::ebiGaf2dictyChado'); }

describe 'An Annotation object' => sub {
    my $annotation;
    before all => sub {
        $annotation = Annotation->new;
    };
    it 'should have attributes' => sub {
        has_attribute_ok( $annotation, $_ )
            for
            qw/db gene_id gene_symbol qualifier go_id db_ref evidence_code with_from aspect taxon date assigned_by/;
    };

};
runtests unless caller;
