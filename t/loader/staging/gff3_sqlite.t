use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema/;
use Test::DatabaseRow;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use IO::File;
use Bio::Chado::Schema;
use File::Spec::Functions;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use SQL::Library;
use Log::Log4perl qw/:easy/;
use Bio::GFF3::LowLevel qw/gff3_parse_feature gff3_parse_directive/;
use Modware::DataSource::Chado::Organism;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

use_ok 'Modware::Loader::GFF3::Staging::Sqlite';
my $loader = new_ok 'Modware::Loader::GFF3::Staging::Sqlite';

my $tmp_schema = chado_schema( load_fixture => 1 );
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
my $sqllib = SQL::Library->new(
    { lib => catfile( module_dir('Modware::Loader'), 'sqlite_gff3.lib' ) } );
Log::Log4perl->easy_init($ERROR);
$loader->schema($schema);
$loader->sqlmanager($sqllib);
$loader->logger( get_logger('MyStaging::Loader') );
$loader->organism(
    Modware::DataSource::Chado::Organism->new(
        genus   => 'Homo',
        species => 'sapiens'
    )
);
local $Test::DatabaseRow::dbh = $schema->storage->dbh;

my $test_input
    = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
    ->subdir('gff3')->file('test.gff3')->openr;
lives_ok { $loader->initialize } 'should initialize';
lives_ok { $loader->create_tables } 'should create staging tables';
row_ok(
    sql =>
        "SELECT name FROM sqlite_master where type = 'table' AND tbl_name like 'temp%'",
    results     => 8,
    description => 'should have created 8 staging tables'
);
lives_ok {

    while ( my $line = $test_input->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {
                last;
            }
        }
        else {
            my $feature_hashref = gff3_parse_feature($line);
            $loader->add_data($feature_hashref);
        }
    }
}
'should add_data';
is( $loader->count_entries_in_feature_cache,
    44, 'should have 44 entries in feature cache' );
is( $loader->count_entries_in_analysisfeature_cache,
    3, 'should have 3 entries in analysis feature cache' );
is( $loader->count_entries_in_featureloc_cache,
    44, 'should have 44 entries in featureloc cache' );
is( $loader->count_entries_in_feature_synonym_cache,
    4, 'should have 4 entries in feature synonym cache' );
is( $loader->count_entries_in_feature_relationship_cache,
    34, 'should have 34 entries in feature relationship cache' );
is( $loader->count_entries_in_feature_dbxref_cache,
    5, 'should have 5 entries in feature dbxref cache' );
is( $loader->count_entries_in_featureprop_cache,
    10, 'should have 10 entries in featureprop cache' );
lives_ok { $loader->bulk_load } 'should bulk load';
row_ok(
    sql => ["SELECT * from temp_feature where organism_id = ?", $loader->organism_id],
    results => 44,
    description => 'should have 44 feature entries'
);
row_ok(
    sql => "SELECT * from temp_feature where id = 'trans-1'",
    results => 1,
    description => 'should have id trans-1'
);
row_ok(
    sql => "SELECT * from temp_feature where name = 'abc-1'",
    results => 1,
    description => 'should have name abc-1'
);

drop_schema();
