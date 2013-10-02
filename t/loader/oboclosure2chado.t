use Test::More qw/no_plan/;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:schema :manager/;

use_ok('Modware::Load');

my ( $schema, $dbmanager );
my $data_dir    = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
my $obo_fixture = $data_dir->subdir('preset')->file('cvprop.tar.bz2');
my $setup       = sub {
    $schema = chado_schema( custom_fixture => $obo_fixture );
    $dbmanager = get_dbmanager_instance();
    my $loader = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('eco.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');
    $loader->run;
};
my $teardown = sub {
    drop_schema();
};

subtest 'loading of obo closure in chado database' => sub {
    $setup->();
    my $loader = new_ok('Modware::Load');
    local @ARGV = (
        'oboclosure2chado',                                '--dsn',
        $dbmanager->dsn,                                   '--user',
        $dbmanager->user,                                  '--password',
        $dbmanager->password,                              '--input',
        $data_dir->subdir('obo_closure')->file('eco.inf'), '--namespace',
        'eco'
    );
    my $result_source = 'Cvtermpath';
    if ( $dbmanager->can('schema_namespace') ) {
        push @ARGV, '--pg_schema', $dbmanager->schema_namespace;
        $result_source = 'Cv::Cvtermpath';
    }

    lives_ok { $loader->run } 'should run the loader command';
    is( $schema->resultset($result_source)->count( {} ),
        1525, 'should have 1525 entries in cvtermpath table' );
    $teardown->();
};

