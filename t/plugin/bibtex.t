use Test::More qw/no_plan/;
use feature qw/say/;
use FindBin qw($Bin);
use BibTeX::Parser;
use autodie qw/open close/;
use IO::File;
use File::Spec::Functions;

{

    package MyConsumer;
    use Moose;
    with 'MooseX::Object::Pluggable';

    sub consume_plugin {
        my $self = shift;
        $self->load_plugin('+Modware::Plugin::Import::Publication::BibTeX');
    }

    1;

}

my $consumer = new_ok('MyConsumer');
$consumer->consume_plugin;
my $parser = BibTeX::Parser->new(
    IO::File->new(
        catfile( $Bin, '..', 'test_data', 'literature', 'test_plugin.bib' )
    )
);

my $expected_data = {
    'endnotePUB3187' => {
        uniquename => '3187',
        source     => 'ENDNOTE'
    },
    'go_ref0000004' => {
        uniquename => '0000004',
        source     => 'GO_REF'
    }
};

while ( my $entry = $parser->next ) {
    if ( $entry->parse_ok ) {
        if ( $entry->has('pmid') ) {
            is( $consumer->parse_uniquename($entry),
                $entry->field('pmid'), 'should have pubmed id' );
            is( $consumer->parse_pub_source($entry),
                'PubMed', 'should have pubmed as source of publcation' );
            is( $consumer->parse_pub_type($entry),
                'journal_article', 'should have type of publication' );
        }
        else {
            is( $consumer->parse_uniquename($entry),
                $expected_data->{ $entry->key }->{uniquename},
                'should have correct id'
            );
            is( $consumer->parse_pub_source($entry),
                $expected_data->{ $entry->key }->{source},
                'should have correct source of publication'
            );
            is( $consumer->parse_pub_type($entry),
                'unpublished', 'should have status of publication' );
        }
    }
}
