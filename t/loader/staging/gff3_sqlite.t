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
my $test_input
    = Path::Class::Dir->new($Bin)->parent->subdir('test_data')->subdir('gff3')
    ->openr('test.gff3');
lives_ok { $loader->initialize } 'should initialize';
lives_ok { $loader->create_tables } 'should create staging tables';
lives_ok {

    while ( my $line = $test_input->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {

                #slurp the rest of line
            }
        }
        else {
            $loader->add_data( gff3_parse_feature($line) );
        }
    }
}
'should add_data';
lives_ok { $loader->bulk_load } 'should bulk load';
drop_schema();
