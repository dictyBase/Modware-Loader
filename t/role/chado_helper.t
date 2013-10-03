use Test::More qw/no_plan/;
use Bio::Chado::Schema;
use Test::Exception;
use Test::Chado qw/chado_schema drop_schema/;
use Test::Chado::Common qw/:all/;

{

    package MyChadoHelper;
    use Moose;

    has 'schema' => ( is => 'rw', isa => 'DBIx::Class::Schema' );
    with 'Modware::Loader::Role::WithChadoHelper';

    1;
}

my $tmp_schema = chado_schema();
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );

my $helper = new_ok('MyChadoHelper');
$helper->schema($schema);

my $dbrow;
lives_ok { $dbrow = $helper->find_or_create_dbrow('chado-helper') }
'should run dbrow helper';
is( $dbrow->name, 'chado-helper',
    'should have created chado-helper db namespace' );

my $cvrow;
lives_ok { $cvrow = $helper->find_or_create_cvrow('cv-helper') }
'should run cvrow helper';
has_cv( $schema, $cvrow->name, 'should have created cv-helper cv namespace' );


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


my $cvterm_row;
lives_ok {
    $cvterm_row = $helper->find_or_create_cvterm_namespace('cvterm-helper');
}
'should run cvterm_namespace helper';
has_cv( $schema, 'cvterm_property_type',
    'should have created cvterm_property_type cv namespace' );
has_cvterm( $schema, $cvterm_row->name,
    'should have created cvterm-helper term' );
has_dbxref( $schema, $cvterm_row->name,
    'should have created cvterm-helper dbxref' );

drop_schema();
$schema->storage->disconnect;
