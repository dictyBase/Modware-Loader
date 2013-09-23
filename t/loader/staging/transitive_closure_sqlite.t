use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema/;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use IO::File;
use Bio::Chado::Schema;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

use_ok 'Modware::Loader::TransitiveClosure::Staging::Sqlite';
my $loader = new_ok 'Modware::Loader::TransitiveClosure::Staging::Sqlite';

my $tmp_schema = chado_schema();
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );

$loader->schema($schema);
is( $schema->source('Staging::Cvtermpath')->from,
    'temp_cvtermpath', 'should load the resultsource' );
isa_ok( $loader->sqlmanager, 'SQL::Library' );

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
drop_schema();
$test_handler->close;
$schema->storage->disconnect;

