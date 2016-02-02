use Test::More qw/no_plan/;
use Test::DatabaseRow;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:all/;
use Test::Chado::Common qw/:all/;
use Test::Chado::Cvterm qw/:all/;

my $data_dir    = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
my $obo_fixture = $data_dir->subdir('preset')->file('cvprop.tar.bz2');

use_ok('Modware::Load');

subtest 'loading of obo file without default namespace' => sub {
    my $schema = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    local $Test::DatabaseRow::dbh = $dbmanager->dbh;
    my $loader = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('ro-filter.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load ro obo file";
    has_cv( $schema, 'ro', 'cv namespace should match with ontology tag' );
    has_dbxref( $schema, 'results_in_morphogenesis_of',
        'should have dbxref' );
    has_cvterm(
        $schema,
        'results in morphogenesis of',
        'should have the cvterm'
    );

    my $sql = <<'SQL';
    SELECT DBXREF.* from dbxref JOIN DB ON DBXREF.DB_ID=DB.DB_ID
    WHERE
    DBXREF.ACCESSION=?
    AND
    DB.NAME='ro'
SQL
    row_ok(
        sql         => [$sql, $_],
        results     => 1,
        description => 'should have term with db namespace from ontology namespace'
    ) for qw/results_in_morphogenesis_of results_in_development_of results_in_formation_of/;

    drop_schema();
};

