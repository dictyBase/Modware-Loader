use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema/;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use IO::File;
use Bio::Chado::Schema;
use File::Spec::Functions;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use SQL::Library;
use Log::Log4perl qw/:easy/;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

use_ok 'Modware::Loader::TransitiveClosure::Staging::Sqlite';
my $loader = new_ok 'Modware::Loader::TransitiveClosure::Staging::Sqlite';

my $tmp_schema = chado_schema();
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
my $sqllib = SQL::Library->new(
    {   lib =>
            catfile( module_dir('Modware::Loader'), 'sqlite_transitive.lib' )
    }
);
Log::Log4perl->easy_init($ERROR);
$loader->schema($schema);
$loader->sqlmanager($sqllib);
$loader->namespace('eco');
$loader->logger( get_logger('MyStaging::Loader') );

is( $schema->source('Staging::Cvtermpath')->from,
    'temp_cvtermpath', 'should load the resultsource' );

my $test_handler
    = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
    ->subdir('obo_closure')->file('eco.inf')->openr;

lives_ok { $loader->create_tables } 'should create staging tables';
lives_ok {
    while ( my $row = $test_handler->getline() ) { $loader->add_data($row) }
}
'should add all rows to loader';

is( $loader->count_entries_in_cvtermpath_cache,
    1525, 'should have 1525 entries in cache' );
lives_ok { $loader->bulk_load } 'should load to staging';
is_deeply(
    $loader->count_entries_in_staging,
    { 'temp_cvtermpath' => 1525 },
    'should have correct entries in staging table'
);
is( $schema->resultset('Staging::Cvtermpath')->count(
        { 'subject_accession' => '0000114', 'type_accession' => 'is_a' }
    ),
    6,
    '0000114 accession should have 6 entries'
);
is( $schema->resultset('Staging::Cvtermpath')
        ->count( { 'type_accession' => 'used_in' } ),
    164,
    'should have 164 entries for used_in type'
);

my $row = $schema->resultset('Staging::Cvtermpath')
    ->search( { 'type_accession' => 'used_in' }, { rows => 1 } )->first;
is( $schema->resultset('General::Db')->find( { db_id => $row->type_db_id } )
        ->name,
    'eco',
    'should match the default namespace'
);

drop_schema();
$test_handler->close;
$schema->storage->disconnect;

