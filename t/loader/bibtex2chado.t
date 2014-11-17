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

subtest
    'loading of publication records in pub module in chado database' => sub {
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

    my $pub;
    lives_ok {
        $pub = $schema->resultset($pub_source)
            ->find( { uniquename => '20443635' } );
    }
    'should retrieve a pub record with pubmed id';
    is( $pub->pyear,  2010, 'should have a publication year' );
    is( $pub->volume, 9,    'should have a publication volume' );
    like( $pub->title, qr/\w+/, 'should have a title' );
    my @props;
    lives_ok { @pubprops = $pub->pubprops }
    'should retrieve all publication properties';
    is( scalar @pubprops, 5, 'should have 5 publication properties' );

    for my $p (@pubprops) {
        if ( $p->type->name eq 'doi' ) {
            is( $p->value, '10.1021/pr901195c', 'should match the doi' );
        }
    }
    my @authors;
    lives_ok { @authors = $pub->pubauthors } 'should retrieve all authors';
    is( scalar @authors, 4, 'should have 4 authors' );

    my $pub2;
    lives_ok {
        $pub2 = $schema->resultset($pub_source)
            ->find( { uniquename => '0000004' } );
    }
    'should retreive an unpublished record';
    is( $pub2->pyear, 2000, 'should have a value for year' );
    my @authors2;
    lives_ok { @authors2 = $pub2->pubauthors } 'should retrieve author';
    is( scalar @authors2, 1, 'should have one author' );
    is( $authors2[0]->surname, 'GOA curators',
        'should match the last name of author' );
    $teardown->();
    };
