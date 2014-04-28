use Test::More qw/no_plan/;
use Bio::Chado::Schema;
use Test::Exception;
use File::ShareDir qw/module_file/;
use Test::Chado qw/chado_schema drop_schema/;
use Test::Chado::Common qw/:all/;

{

    package MyChadoHelper;
    use Moose;

    has 'schema' => ( is => 'rw', isa => 'DBIx::Class::Schema' );
    with 'Modware::Loader::Role::WithChadoHelper';

    1;
}

subtest 'helpers for db and dbxrefs' => sub {
    my $preset = module_file( 'Test::Chado', 'cvpreset.tar.bz2' );
    my $tmp_schema = chado_schema( custom_fixture => $preset );
    my $schema
        = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );

    my $helper = new_ok('MyChadoHelper');
    $helper->schema($schema);

    my $dbrow;
    lives_ok { $dbrow = $helper->find_or_create_dbrow('chado-helper') }
    'should run dbrow helper';
    is( $dbrow->name, 'chado-helper',
        'should have created chado-helper db namespace' );

    my @xref;
    lives_ok { @xref = $helper->normalize_id('TC:34398493') }
    'should run normalize_id method';
    like( $xref[0], qr/\d{1,}/, "should get the db namespace" );
    is( $xref[1], '34398493', "should get the xref" );
    is( $schema->resultset('General::Db')->count( { name => 'TC' } ),
        1, 'should have DB namespace in database' );
    lives_ok { $helper->normalize_id('logger') } 'should run normalize_id';
    is( $schema->resultset('General::Db')->count( { name => 'internal' } ),
        1, 'should have internal db namespace in database' );

    lives_ok { @xref = $helper->normalize_id( 'testnormal', 'testdb' ) }
    'should run with provided db name';
    is( $schema->resultset('General::Db')->find( { db_id => $xref[0] } )
            ->name,
        'testdb',
        'should retrieve the correct db'
    );

    lives_ok {
        $dbrow
            = $helper->find_or_create_dbxref_row( 'dbxref_test', 'db_test' );
    }
    'should run to create dbxref';
    is( $dbrow->accession, 'dbxref_test', 'should match the dbxref' );
    is( $dbrow->db->name,  'db_test',     'should match the db' );

    lives_ok {
        $dbrow
            = $helper->find_or_create_dbxref_row( 'remark', 'cv_property' );
    }
    'should run to lookup dbxref';
    is( $dbrow->accession, 'remark',      'should match the dbxref' );
    is( $dbrow->db->name,  'cv_property', 'should match the db' );
    drop_schema();
};

subtest 'helpers for cv and cvterms' => sub {
    my $preset = module_file( 'Test::Chado', 'cvpreset.tar.bz2' );
    my $tmp_schema = chado_schema( custom_fixture => $preset );
    my $schema
        = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );

    my $helper = new_ok('MyChadoHelper');
    $helper->schema($schema);

    my $cvrow;
    lives_ok { $cvrow = $helper->find_or_create_cvrow('cv-helper') }
    'should run cvrow helper';
    has_cv( $schema, $cvrow->name,
        'should have created cv-helper cv namespace' );
    lives_ok { $cvrow = $helper->find_or_create_cvrow('cv_property') }
    'should run cvrow helper';
    is( $cvrow->name, 'cv_property',
        'should have found cv_property cv namespace' );

    my $cvterm_row;
    lives_ok {
        $cvterm_row
            = $helper->find_or_create_cvterm_namespace('cvterm-helper');
    }
    'should run cvterm_namespace helper';
    has_cv( $schema, 'cvterm_property_type',
        'should have created cvterm_property_type cv name' );
    has_cvterm( $schema, $cvterm_row->name,
        'should have created cvterm-helper term' );
    has_dbxref( $schema, $cvterm_row->name,
        'should have created cvterm-helper dbxref' );

    lives_ok {
        $cvterm_row = $helper->find_or_create_cvterm_row(
            { cv => 'cv_property', cvterm => 'remark' } );
    }
    'should run cvterm lookup';
    is( $cvterm_row->name,     'remark',      'should match the cvterm' );
    is( $cvterm_row->cv->name, 'cv_property', 'should match the cv name' );

    lives_ok {
        $cvterm_row = $helper->find_or_create_cvterm_row(
            {   cv       => 'cv_test',
                cvterm   => 'cvterm_test',
                'dbxref' => 'dbxref_test',
                'db'     => 'db_test'
            }
        );
    }
    'should run for creating cvterm';
    is( $cvterm_row->name,     'cvterm_test', 'should match the cvterm' );
    is( $cvterm_row->cv->name, 'cv_test',     'should match the cv' );
    is( $cvterm_row->dbxref->accession,
        'dbxref_test', 'should match the dbxref' );
    is( $cvterm_row->dbxref->db->name, 'db_test', 'should match the db' );
    drop_schema();
};
