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

subtest 'loading of discoideum genome publications to chado database' => sub {
    my ( $schema, $dbmanager ) = $setup->();
    my $loader = new_ok('Modware::Import');
    local @ARGV = (
        'bibtex2chado',       '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->file('dictygenomespub.bib')
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
        4, 'should have 4 entries in pub table' );

    #16, 'should have 16 authors' );
    #is( $schema->resultset($pubprop_source)->count( {} ),
    #12, 'should have 12 pubprop records' );

    my $pub;
    lives_ok {
        $pub = $schema->resultset($pub_source)
            ->find( { uniquename => '13319664' } );
    }
    'should retrieve a pub record with pubmed id';
    is( $pub->pyear,  1956, 'should have a publication year' );
    is( $pub->volume, 39,   'should have a publication volume' );
    like(
        $pub->title,
        qr/^Serological investigations/,
        'should have a title'
    );
    is( $pub->series_name, 'J. Gen. Physiol.', 'should match journal name' );
    is( $pub->pages,       '813-20',           'should match page no.' );

    is( $pub->count_related( 'pubauthors', {} ), 1, 'should have 1 author' );
    my @pubauthors = $pub->pubauthors;
    is( $pubauthors[0]->surname, 'GREGG', 'should match the surname' );
    is( $pubauthors[0]->givennames,
        'J H JH', 'should match the rest of the name' );

    is( $pub->count_related( 'pubprops', {} ),
        4, 'should have 4 pubprop records' );
    my %propmap;
    for my $type (qw/doi status month issn abstract/) {
        my $row = $schema->resultset('Cv::Cvterm')->find(
            {   name      => $type,
                'cv.name' => 'pub_type'
            },
            { join => 'cv' }
        );
        if ($row) {
            $propmap{$type} = $row->cvterm_id;
        }
    }
    is( $pub->pubprops( { type_id => $propmap{'issn'} } )->first->value,
        '0022-1295', 'should match the issn' );
    is( $pub->pubprops( { type_id => $propmap{'status'} } )->first->value,
        'ppublish', 'should match the status' );
    is( $pub->pubprops( { type_id => $propmap{'month'} } )->first->value,
        'may', 'should match the month' );
    like(
        $pub->pubprops( { type_id => $propmap{'abstract'} } )->first->value,
        qr/Antibodies to slime molds/,
        'should match the abstract'
    );

    lives_ok {
        $pub2 = $schema->resultset($pub_source)
            ->find( { uniquename => '15867862' } );
    }, 'should retrieve another pub record';
    is( $pub2->pyear, 2005, 'should have a publication year' );
    like(
        $pub2->title,
        qr/^Quantitative measurement of IgE/,
        'should have a title'
    );
    is( $pub2->count_related( 'pubauthors', {} ), 8,
        'should have 8 authors' );
    is( $pub2->count_related( 'pubprops', {} ),
        5, 'should have 5 pubprop records' );
    like( $pub2->pubprops( { type_id => $propmap{'doi'} } )->first->value,
        qr/j\.jaci\.2004/, 'should match the doi' );


    my $pub3;
    lives_ok {
        $pub3 = $schema->resultset($pub_source)
            ->find( { uniquename => '20143343' } );
    }, 'should retrieve another pub record';
    like($pub3->title, qr/^Strategies for DNA interstrand/, 'should match the title');
    is( $pub3->count_related( 'pubauthors', {} ), 1,
        'should have 1 author' );
    is( $pub3->count_related( 'pubprops', {} ),
        5, 'should have 5 pubprop records' );


    $teardown->();
};

