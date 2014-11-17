use Test::More qw/no_plan/;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:schema :manager/;
use Test::Chado::Common;

use_ok('Modware::Import');

my $data_dir = Path::Class::Dir->new($Bin)->parent->subdir('test_data')
    ->subdir('literature');

my $setup = sub {
    $schema    = chado_schema();
    $dbmanager = get_dbmanager_instance();
    return ( $schema, $dbmanager );
};

my $teardown = sub {
    drop_schema();
};

subtest 'loading of publications from bibtex file to chado database' => sub {
    my ( $schema, $dbmanager ) = $setup->();
    my $loader = new_ok('Modware::Import');
    local @ARGV = (
        'bibtex2chado',       '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->file('test.bib')
    );
    my $pub_source       = 'Pub';
    my $pubauthor_source = 'Pubauthor';
    my $pubprop_source   = 'Pubprop';
    if ( $dbmanager->can('schema_namespace') ) {
        push @ARGV, '--pg_schema', $dbmanager->schema_namespace;
        $pub_source       = 'Pub::Pub';
        $pubauthor_source = 'Pub::Pubauthor';
        $pubprop_source   = 'Pub::Pubprop';
    }

    lives_ok { $loader->run } 'should run the bibtex2chado loader';
    for my $term (
        qw/unpublished journal_article status doi month issn abstract thesis/
        )
    {
        has_cvterm( $schema, $term, "should have $term in chado" );
    }
    is( $schema->resultset($pub_source)->count( {} ),
        5, 'should have 5 entries in pub table' );
    is( $schema->resultset($pubauthor_source)->count( {} ),
        16, 'should have 16 authors' );
    is( $schema->resultset($pubprop_source)->count( {} ),
        12, 'should have 12 pubprop records' );
    $teardown->();
};
